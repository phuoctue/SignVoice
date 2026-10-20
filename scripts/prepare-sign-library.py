"""Select clear, source-labelled TRAIN examples and prepare web/mobile media.

Reuses the inventory rules and existing model vocabulary. Never loads AI weights.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import zipfile

import cv2
import imageio_ffmpeg
import numpy as np
import requests

spec = importlib.util.spec_from_file_location('audit', Path(__file__).with_name('audit-sign-library.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

SOURCES = {'namwu/ViSignLanguage-Video': 'cc-by-4.0', 'KhangCN/Video_VSL': 'apache-2.0'}
RECIPE = 'rgb-reference-h264-640-crf23-5frames-v2'
# Visually checked: plain background and clear waving hand in the source review.
VISUAL_SOURCE_PREFERENCES = {'chào': 'namwu/ViSignLanguage-Video'}


def clarity(path):
    cap = cv2.VideoCapture(str(path))
    try:
        count, fps = cap.get(cv2.CAP_PROP_FRAME_COUNT), cap.get(cv2.CAP_PROP_FPS)
        width, height = cap.get(cv2.CAP_PROP_FRAME_WIDTH), cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
        if not (fps > 0 and .4 <= count/fps <= 20 and min(width, height) >= 160):
            raise ValueError('Unsupported duration or resolution')
        sharpness, exposure, clutter, frames = [], [], [], []
        for fraction in (.15, .325, .5, .675, .85):
            cap.set(cv2.CAP_PROP_POS_FRAMES, min(count-1, round(count*fraction)))
            ok, frame = cap.read()
            if not ok: raise ValueError('Frame decode failed')
            # Compare at a common scale so resolution does not masquerade as sharpness.
            factor = 320/max(frame.shape[:2])
            small = cv2.resize(frame, None, fx=factor, fy=factor)
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            sharpness.append(float(cv2.Laplacian(gray, cv2.CV_64F).var()))
            lap = cv2.Laplacian(gray, cv2.CV_64F)
            h, w = gray.shape
            border = np.ones(gray.shape, bool)
            border[round(h*.1):round(h*.9), round(w*.2):round(w*.8)] = False
            clutter.append(float(lap[border].var()))
            exposure.append(float(((gray > 15) & (gray < 245)).mean()))
            frames.append(frame)
        score = (math.log1p(float(np.median(sharpness)))
                 + .7*math.log2(max(1., min(width, height)/160)) + float(np.mean(exposure))
                 - .8*math.log1p(float(np.median(clutter))))
        return dict(score=round(score, 5), width=int(width), height=int(height),
                    duration_seconds=round(count/fps, 3), sharpness=float(np.median(sharpness))), frames
    finally:
        cap.release()


def transcode(job):
    source, target, media_id = job
    _, frames = clarity(source)
    video = target / f'{media_id}.mp4'
    # Same recipe+source identity is immutable; keep previously completed assets.
    if not video.is_file():
        partial = target / f'{media_id}.partial.mp4'
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error', '-y',
                        '-i', str(source), '-an', '-vf',
                        'scale=640:640:force_original_aspect_ratio=decrease:force_divisible_by=2',
                        '-c:v', 'libx264', '-preset', 'veryfast', '-threads', '1', '-crf', '23',
                        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-map_metadata', '-1',
                        str(partial)], check=True, timeout=120, capture_output=True)
        partial.replace(video)
    for i, frame in enumerate(frames, 1):
        factor = min(1, 640/max(frame.shape[:2]))
        frame = cv2.resize(frame, None, fx=factor, fy=factor)
        if not cv2.imwrite(str(target / f'{media_id}-{i}.jpg'), frame, [cv2.IMWRITE_JPEG_QUALITY, 88]):
            raise ValueError('Image write failed')
    return media_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--vocabulary', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--media', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.media.mkdir(parents=True, exist_ok=True)
    for name, url in {
        'apache-2.0': 'https://www.apache.org/licenses/LICENSE-2.0.txt',
        'cc-by-4.0': 'https://creativecommons.org/licenses/by/4.0/legalcode.txt',
    }.items():
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        (args.media / f'LICENSE-{name}.txt').write_text(response.text, encoding='utf8')
    work = args.output / 'candidate-videos'
    work.mkdir(exist_ok=True)
    cards = {}
    for repo, license_name in SOURCES.items():
        response = requests.get(f'https://huggingface.co/api/datasets/{repo}', timeout=30)
        response.raise_for_status()
        card = response.json().get('cardData', {})
        if card.get('license') != license_name:
            raise ValueError(f'Source license metadata changed: {repo}')
        cards[repo] = dict(url=f'https://huggingface.co/datasets/{repo}', license=license_name,
                           cardData=card)
    (args.output / 'source_cards.json').write_text(json.dumps(cards, ensure_ascii=False, indent=2), encoding='utf8')
    words = json.loads(args.vocabulary.read_text(encoding='utf8'))['labels']
    results, missing, rejected, jobs = [], [], [], []
    with zipfile.ZipFile(args.archive) as archive:
        rows = list(csv.DictReader(io.StringIO(archive.read('manifest_all_sources.csv').decode('utf-8-sig'))))
        groups, _ = audit.build_inventory(rows, set(archive.namelist()))
        for word in words:
            candidates = []
            group = [r for r in groups.get(word, []) if r['source'] in SOURCES]
            for source in SOURCES:
                # Larger encoded payloads often preserve more detail; inspect two per source,
                # then rank decoded frames by a common-scale measure, not file size alone.
                subset = sorted([r for r in group if r['source'] == source],
                                key=lambda r: (-int(r['bytes']), r['sha256']))[:2]
                for row in subset:
                    file = work / f"{row['sha256']}.mp4"
                    try:
                        payload = file.read_bytes() if file.is_file() else archive.read(row['path'])
                        if hashlib.sha256(payload).hexdigest() != row['sha256']:
                            raise ValueError('Checksum mismatch')
                        if not file.is_file(): file.write_bytes(payload)
                        quality, frames = clarity(file)
                        candidates.append((quality['score'], row, file, frames, quality))
                    except Exception as error:
                        rejected.append(dict(word=word, path=row['path'], error=str(error)))
            if not candidates:
                missing.append(word)
                continue
            preferred = [c for c in candidates if c[1]['source'] == VISUAL_SOURCE_PREFERENCES.get(word)]
            _, row, file, frames, quality = max(preferred or candidates, key=lambda c: c[0])
            media_id = hashlib.sha256((row['sha256']+RECIPE).encode()).hexdigest()
            results.append(dict(word=word, media_id=media_id, source=row['source'],
                                source_sha256=row['sha256'], source_path=row['path'],
                                source_split=row['fixed_split'], source_revision=row.get('source_revision', ''),
                                license=SOURCES[row['source']], source_url=cards[row['source']]['url'],
                                quality=quality, candidate_count=len(candidates),
                                selection='source_verified_label_and_automatic_clarity',
                                motion_semantic_expert_review=False))
            jobs.append((file, args.media, media_id))
            if len(results) % 30 == 0: print(f'Selected {len(results)} labels', flush=True)
    # Free decoded images as each job finishes. Bounded workers avoid saturating the AI host.
    completed = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        for media_id in pool.map(transcode, jobs):
            completed.append(media_id)
            if len(completed) % 30 == 0: print(f'Prepared {len(completed)} media sets', flush=True)
    # Explicit alias from the source's xin_chao spelling; kept as a separate dictionary phrase.
    hello = next((r for r in results if r['word'] == 'chào'), None)
    if hello:
        results.append(dict(hello, word='xin chào', alias_of='chào'))
    (args.output / 'library.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf8')
    summary = dict(vocabulary_words=len(words), source_label_media=len(completed), dictionary_entries=len(results),
                   missing_words=missing, rejected_candidates=rejected, recipe=RECIPE,
                   frame_images_per_word=5, publication='ready_for_source_attributed_reference_import',
                   limitation='Automatic image clarity is not expert confirmation of sign meaning or dialect')
    (args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf8')
    main()

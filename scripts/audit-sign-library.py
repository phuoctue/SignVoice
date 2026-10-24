"""Inventory existing RGB sources and prepare local review previews, never publish.

Run with ai_service/.venv/Scripts/python.exe for OpenCV preview extraction.
No source ZIP is extracted wholesale. TEST/VAL and private recordings are excluded.
"""
import argparse
import collections
import csv
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import sys
import unicodedata
import zipfile


def normalize(value):
    return ' '.join(unicodedata.normalize('NFC', value).casefold().split())


def eligible(row):
    label = normalize(row.get('label', ''))
    return (row.get('kind') == 'rgb' and bool(label) and not label.isdecimal()
            and row.get('fixed_split') == 'train'
            and row.get('source_label_verified', '').casefold() == 'true'
            and row.get('is_personal', '').casefold() != 'true'
            and row.get('basic_quality_pass', '').casefold() != 'false'
            and not row.get('training_exclusion_reason', '').strip())


def reference_eligible(row):
    # Unassigned dictionary clips are reference material, never new training data.
    if row.get('source') != 'user_Dataset.tgz':
        return eligible(row)
    return (row.get('kind') == 'rgb' and bool(normalize(row.get('label', '')))
            and row.get('fixed_split') in ('', 'train')
            and row.get('source_label_verified', '').casefold() == 'true'
            and row.get('is_personal', '').casefold() != 'true'
            and row.get('basic_quality_pass', '').casefold() != 'false'
            and not row.get('training_exclusion_reason', '').strip())


def safe_member(name):
    member = PurePosixPath(name)
    return (not member.is_absolute() and '..' not in member.parts
            and '\\' not in name and ':' not in name)


def write_csv(path, rows, fields):
    with path.open('w', newline='', encoding='utf-8-sig') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def build_inventory(rows, members, reference=False):
    counts = collections.Counter()
    groups = collections.defaultdict(list)
    conflicts = collections.defaultdict(set)
    for row in rows:
        if row.get('kind') == 'rgb' and row.get('label'):
            conflicts[row['sha256']].add(normalize(row['label']))
    for row in rows:
        if not (reference_eligible(row) if reference else eligible(row)):
            counts['excluded_by_label_kind_split_or_quality'] += 1
            continue
        name = row['path']
        if not safe_member(name) or name not in members:
            counts['missing_or_unsafe_member'] += 1
            continue
        if len(conflicts[row['sha256']]) > 1:
            counts['conflicting_hash_labels'] += 1
            continue
        label = normalize(row['label'])
        if any(r['sha256'] == row['sha256'] for r in groups[label]):
            counts['duplicate_hash'] += 1
            continue
        groups[label].append(row)
    return groups, counts


def prepare_preview(archive, row, output):
    import cv2
    digest = row['sha256']
    if len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
        raise ValueError('Invalid SHA256')
    payload = archive.read(row['path'])
    if hashlib.sha256(payload).hexdigest() != digest:
        raise ValueError('Source checksum mismatch')
    video = output / f'{digest}.mp4'
    video.write_bytes(payload)
    cap = cv2.VideoCapture(str(video))
    try:
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = float(cap.get(cv2.CAP_PROP_FPS))
        if total < 3 or not 0 < fps < 300:
            raise ValueError('Invalid duration/FPS')
        frames = []
        for fraction in (.1, .3, .5, .7, .9):
            cap.set(cv2.CAP_PROP_POS_FRAMES, min(total - 1, int(total * fraction)))
            ok, frame = cap.read()
            if not ok:
                raise ValueError('Cannot decode preview frame')
            height, width = frame.shape[:2]
            scale = min(320 / width, 240 / height)
            resized = cv2.resize(frame, (round(width * scale), round(height * scale)))
            import numpy as np
            tile = np.full((270, 340, 3), 245, dtype=np.uint8)
            h, w = resized.shape[:2]
            tile[10:10+h, (340-w)//2:(340-w)//2+w] = resized
            cv2.putText(tile, f'{fraction * total / fps:.2f}s', (10, 258),
                        cv2.FONT_HERSHEY_SIMPLEX, .6, (30, 30, 30), 1)
            frames.append(tile)
        import numpy as np
        sheet = output / f'{digest}.jpg'
        if not cv2.imwrite(str(sheet), np.concatenate(frames, axis=1)):
            raise ValueError('Cannot write contact sheet')
        return {'video': str(video), 'contact_sheet': str(sheet),
                'duration_seconds': round(total/fps, 3), 'fps': fps,
                'decoded_preview_frames': len(frames)}
    finally:
        cap.release()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--preview-per-word', type=int, default=1)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    preview_dir = args.output / 'previews'
    preview_dir.mkdir(exist_ok=True)
    priority = ['xin chào', 'chào', 'tôi', 'là', 'bạn', 'cảm ơn',
                'nghe', 'nhìn', 'rau', 'bàn tay', 'cứu']
    with zipfile.ZipFile(args.archive) as archive:
        rows = list(csv.DictReader(io.StringIO(
            archive.read('manifest_all_sources.csv').decode('utf-8-sig'))))
        groups, excluded = build_inventory(rows, set(archive.namelist()))
        inventory = []
        for word, group in sorted(groups.items()):
            inventory.append({'word': word, 'unique_train_videos': len(group),
                              'sources': ' | '.join(sorted({r['source'] for r in group})),
                              'semantic_review': 'pending', 'publication': 'blocked_until_review'})
        write_csv(args.output / 'inventory.csv', inventory,
                  ['word', 'unique_train_videos', 'sources', 'semantic_review', 'publication'])
        candidates, failures = [], []
        for word in priority:
            group = groups.get(word, [])
            # Keep multiple sources visible, not multiple copies of one source.
            chosen = []
            for source in sorted({r['source'] for r in group}):
                subset = sorted((r for r in group if r['source'] == source),
                                key=lambda r: (int(r.get('bytes') or 0), r['sha256']))
                chosen.extend(subset[:max(0, args.preview_per_word)])
            for row in chosen:
                candidate = {k: row.get(k, '') for k in
                             ('source', 'path', 'sha256', 'raw_label', 'mapping_status', 'fixed_split')}
                candidate.update(word=word, semantic_review='pending', rights_review='pending',
                                 published=False)
                try:
                    candidate.update(prepare_preview(archive, row, preview_dir))
                    candidates.append(candidate)
                except Exception as error:
                    failures.append({'word': word, 'path': row['path'], 'error': str(error)})
        summary = {'archive': str(args.archive.resolve()), 'manifest_records': len(rows),
                   'kind_counts': dict(collections.Counter(r['kind'] for r in rows)),
                   'eligible_words': len(groups), 'eligible_unique_videos': sum(map(len, groups.values())),
                   'eligible_sources': dict(collections.Counter(r['source'] for g in groups.values() for r in g)),
                   'excluded': dict(excluded), 'missing_priority_words': [w for w in priority if w not in groups],
                   'preview_candidates': len(candidates), 'preview_failures': failures,
                   'published_entries': 0, 'scope': 'TRAIN RGB metadata candidates, not semantically approved'}
    (args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    (args.output / 'candidates.json').write_text(json.dumps(candidates, ensure_ascii=False, indent=2), encoding='utf-8')
    review_file = args.output / 'review_decisions.csv'
    # A repeated audit must not erase human review decisions.
    if not review_file.exists():
        write_csv(review_file, [dict(word=c['word'], source=c['source'], sha256=c['sha256'],
                                    semantic_approved='', rights_approved='', preferred='', reviewer='', notes='')
                                for c in candidates],
                  ['word', 'source', 'sha256', 'semantic_approved', 'rights_approved', 'preferred', 'reviewer', 'notes'])
    html = ['<!doctype html><meta charset="utf-8"><title>SignVoice: duyệt mẫu</title>',
            '<h1>Mẫu chờ duyệt — không phải nội dung đã xuất bản</h1>',
            '<p>Đối chiếu đúng nghĩa, động tác, biến thể và điều kiện sử dụng trước khi đưa lên app.</p>']
    import html as escaping
    for item in candidates:
        esc = escaping.escape
        stem = item['sha256']
        html.append(f'<h2>{esc(item["word"])} — {esc(item["source"])}</h2>'
                    f'<p>TRAIN · SHA256: {stem}</p><a href="previews/{stem}.mp4">Mở video gốc</a>'
                    f'<p><img style="max-width:100%" src="previews/{stem}.jpg"></p>')
    (args.output / 'review.html').write_text('\n'.join(html), encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    main()

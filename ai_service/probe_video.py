"""Repeatable camera/model diagnosis. Never trains or reports labeled accuracy."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np
from .engine import Engine
from .model_selection import resolve_selection


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--video', type=Path, required=True)
    source = p.add_mutually_exclusive_group(required=True)
    source.add_argument('--raw-camera', action='store_true')
    source.add_argument('--roi', type=int, nargs=4, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'))
    p.add_argument('--unmirror', action='store_true')
    p.add_argument('--model-dir')
    p.add_argument('--frames', type=int, default=150)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if not 1 <= a.frames <= 3000:
        p.error('--frames must be 1..3000')
    identity = resolve_selection(a.model_dir)
    engine = Engine(identity['model_dir'])
    session = engine.session('words', False)
    cap = cv2.VideoCapture(str(a.video))
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not np.isfinite(fps) or fps <= 0:
        raise ValueError('Cannot decode video with a valid clock')
    rows = []
    index = 0
    next_sample = 0.
    try:
        while len(rows) < a.frames:
            ok, image = cap.read()
            if not ok: break
            stamp = index / fps
            index += 1
            if stamp + 1e-6 < next_sample: continue
            next_sample = stamp + 1 / 15
            if a.roi:
                x,y,w,h = a.roi
                if min(x,y) < 0 or min(w,h) < 16 or x+w > image.shape[1] or y+h > image.shape[0]:
                    raise ValueError('ROI must be the complete camera rectangle inside the recording')
                image = image[y:y+h,x:x+w]
            if a.unmirror: image = cv2.flip(image, 1)
            result = session.process(dict(sequence=len(rows),timestamp_ms=round(stamp*1000)),image)
            rows.append({k:result.get(k) for k in ('timestamp_ms','hands','confirmed','status','events',
                         'processing_ms','timing','detector_timing','inference','prediction_age_ms')})
    finally:
        session.close();cap.release()
    h = hashlib.sha256()
    with a.video.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    rejects = Counter(reason for r in rows for reason in r.get('inference',{}).get('word',{}).get('rejection_reasons',[]))
    report = dict(identity=identity,video=str(a.video),video_sha256=h.hexdigest(),raw_camera=a.raw_camera,
                  roi=a.roi,unmirror=a.unmirror,accuracy_claim_allowed=False,training_performed=False,
                  thresholds_modified=False,frames=len(rows),with_hands=sum(r['hands']>0 for r in rows),
                  median_processing_ms=float(np.median([r['processing_ms'] for r in rows])) if rows else None,
                  rejection_counts_per_processed_frame=dict(rejects),rows=rows)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'},ensure_ascii=True))


if __name__ == '__main__':
    main()

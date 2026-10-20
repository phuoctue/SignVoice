"""Choose an informative initial photo; retain all chronological source frames."""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '3')
os.environ.setdefault('OMP_NUM_THREADS', '1')
import argparse
import json
from pathlib import Path
import sys
import cv2
import mediapipe as mp
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', required=True, type=Path)
    parser.add_argument('--media', required=True, type=Path)
    parser.add_argument('--hand-model', required=True, type=Path)
    args = parser.parse_args()
    rows = json.loads(args.catalog.read_text(encoding='utf8'))
    options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(args.hand_model.resolve())),
        running_mode=mp.tasks.vision.RunningMode.IMAGE, num_hands=2,
        min_hand_detection_confidence=.35, min_hand_presence_confidence=.35)
    results = {}
    with mp.tasks.vision.HandLandmarker.create_from_options(options) as detector:
        for row in rows:
            media_id = row['media_id']
            if media_id in results: continue
            frames = []
            for index in range(1, 6):
                frame = cv2.imread(str(args.media / f'{media_id}-{index}.jpg'))
                if frame is None: raise ValueError('Missing reference frame')
                found = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,
                    data=np.ascontiguousarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))))
                scores = []
                h, w = frame.shape[:2]
                for hand in found.hand_landmarks:
                    xs, ys = np.array([p.x for p in hand]), np.array([p.y for p in hand])
                    x0, x1 = max(0, int(xs.min()*w)-5), min(w, int(xs.max()*w)+6)
                    y0, y1 = max(0, int(ys.min()*h)-5), min(h, int(ys.max()*h)+6)
                    crop = frame[y0:y1, x0:x1]
                    if not crop.size: continue
                    detail = float(cv2.Laplacian(cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var())
                    scores.append(3*(1-float(ys.mean())) + .3*np.log1p(detail)
                                  + min(1., (x1-x0)*(y1-y0)/(w*h)*20))
                score = max(scores) if scores else -10.
                frames.append(dict(index=index, visible_hands=len(found.hand_landmarks), score=round(float(score), 5)))
            # Avoid an arbitrary first-frame default if the detector found no hand.
            best = max(frames, key=lambda f: (f['score'], -abs(f['index']-3)))
            results[media_id] = dict(keyframe_index=best['index'], frames=frames)
            if len(results) % 30 == 0: print(f'Keyframes {len(results)}', flush=True)
    for row in rows:
        row['keyframe_index'] = results[row['media_id']]['keyframe_index']
    args.catalog.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf8')
    args.catalog.with_name('keyframe_report.json').write_text(json.dumps(results, indent=2), encoding='utf8')
    print(json.dumps({'media_sets': len(results), 'frames_with_hand': sum(f['visible_hands'] > 0 for r in results.values() for f in r['frames'])}))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf8')
    main()

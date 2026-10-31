"""Read local opt-in PNG diagnostics. Never uploads pixels or changes a model.

Feature conversion replay must match; cross-delegate detector differences are
descriptive, not proof that either detector is correct. PNGs are sampled, so CPU
redetection uses IMAGE mode and is not a reproduction of VIDEO tracking state.
"""
import argparse
import base64
import hashlib
import itertools
import json
from pathlib import Path
import struct

import cv2
import numpy as np

from . import model_runtime as runtime
from .protocol import browser_hand_result

ATOL = 2e-5


def decode_snapshot(row):
    if (row.get('format') != 'png' or row.get('pixel_stage') != 'resized_detector_input'
            or row.get('mirrored') is not False or row.get('rotation') != 0):
        raise ValueError('Snapshot must be unmirrored, unrotated exact PNG detector input')
    encoded = row['png_base64']
    if not isinstance(encoded, str) or len(encoded) > 6_000_000:
        raise ValueError('PNG exceeds diagnostic limit')
    raw = base64.b64decode(encoded, validate=True)
    if len(raw) < 33 or raw[:8] != b'\x89PNG\r\n\x1a\n' or raw[12:16] != b'IHDR':
        raise ValueError('Invalid PNG header')
    width, height = struct.unpack('!II', raw[16:24])
    if not (16 <= width <= 1920 and 16 <= height <= 1920 and width * height <= 1920*1080):
        raise ValueError('PNG dimensions exceed limit')
    obs = row['hand_observation']
    if (width != row['width'] or height != row['height'] or obs['width'] != width
            or obs['height'] != height or obs['timestamp_ms'] != row['timestamp_ms']):
        raise ValueError('PNG/landmark dimensions or capture timestamp differ')
    image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    if image is None or image.shape[:2] != (height, width):
        raise ValueError('PNG could not be decoded')
    browser_hand_result(dict(width=width, height=height, timestamp_ms=row['timestamp_ms'],
        rotation=0, hand_observation=obs), obs['model_sha256'])
    return image, hashlib.sha256(raw).hexdigest()


def match_hands(first, second, aspect):
    """Min-cost assignment, not anatomical-label matching (labels can flicker)."""
    a, b = np.asarray(first, float), np.asarray(second, float)
    for points in (a, b):
        if points.size and (points.ndim != 3 or points.shape[1:] != (21, 3)
                            or not np.isfinite(points).all()):
            raise ValueError('Invalid detector XYZ')
    if len(a) > 2 or len(b) > 2:
        raise ValueError('At most two hands supported')
    if not len(a) or not len(b):
        return dict(first_hands=len(a), second_hands=len(b), matched=0, pairs=[])
    scale = np.array([1., aspect, 1.])
    assignments = [list(zip(left, right))
        for left in itertools.permutations(range(len(a)), min(len(a), len(b)))
        for right in itertools.permutations(range(len(b)), min(len(a), len(b)))]
    pairs = min(assignments, key=lambda p: sum(np.linalg.norm((a[i]-b[j])*scale, axis=1).mean() for i,j in p))
    return dict(first_hands=len(a), second_hands=len(b), matched=len(pairs), pairs=[
        dict(first=i, second=j,
             median_xy_width_units=float(np.median(np.linalg.norm(((a[i]-b[j])*scale)[:,:2], axis=1))),
             median_xyz_width_units=float(np.median(np.linalg.norm((a[i]-b[j])*scale, axis=1)))) for i,j in pairs])


def feature_replay(capture, config):
    """Rebuild the same ordered observed inputs with actual per-frame context.

    Refuse an equality claim if CPU-only inputs or missing sources prevent
    rebuilding tracker history. Do not fill holes or substitute saved features.
    """
    expected_hash = config['sha256']['hand_landmarker.task']
    observations = {}
    def add(obs):
        key = float(obs['timestamp_ms'])
        if key in observations:
            old = observations[key]
            if any(old.get(k) != obs.get(k) for k in ('landmarks', 'handedness', 'width', 'height')):
                raise ValueError('Conflicting observations share capture timestamp')
        observations[key] = obs
    records = []
    for message in capture['messages']:
        if message.get('kind') in ('sent_observation', 'observation_send') and 'observation' in message:
            add(message['observation'])
        if message.get('kind') == 'frame' and 'hand_observation' in message:
            obs = message['hand_observation']; add(obs)
            for historical in message.get('hand_history', []):
                add({**obs, **historical})
        records.extend(message.get('worker_diagnostic', {}).get('records', []))
    if not records:
        raise ValueError('No worker journal: enable local diagnostics and restart camera')
    if [r.get('index', i) for i,r in enumerate(records)] != list(range(len(records))):
        raise ValueError('Missing or repeated worker journal batches')
    missing = [round(i['time']*1000, 4) for r in records for i in r['inputs']
               if float(round(i['time']*1000)) not in observations]
    generations = {r['generation'] for r in records}
    incomplete = (capture.get('truncated') or any(m.get('worker_diagnostic', {}).get('truncated') for m in capture['messages'])
        or any(r.get('observation_overruns', 0) for r in records) or len(generations) != 1)
    if missing or incomplete:
        return dict(comparable=False, passed=None, missing_source_timestamps_ms=missing,
            reason='Missing source observation, multiple generations, overrun or truncated journal')
    tracker = runtime.HandSlotTracker()
    failures = []; checked = 0; last = -1.
    for row in records:
        for item in row['inputs']:
            now = item['time']
            if now <= last: raise ValueError('Worker input timestamps are not strictly increasing')
            last = now
            obs = observations[float(round(now*1000))]
            meta = dict(width=obs['width'], height=obs['height'], timestamp_ms=obs['timestamp_ms'],
                        rotation=0, hand_observation=obs)
            found = browser_hand_result(meta, expected_hash)
            if found is None: raise ValueError('Detector model/SDK mismatch')
            found = runtime.foreground_hand_result(found, meta['width'], meta['height'], item['context'])
            pose, wrist, _ = runtime.features_from_result(found, meta['width'], meta['height'], False,
                allow_low_hands=True, tracker=tracker, now=now,
                keep_both_hands=config.get('feature_pipeline') in runtime.TRACKED_PIPELINES)
            errors = {}
            for key, actual in [('pose',pose), ('wrist',wrist)]:
                expected = np.asarray(item[key])
                if expected.shape != actual.shape or not np.isfinite(expected).all():
                    raise ValueError('Worker feature shape or values are invalid')
                errors[key] = float(np.max(np.abs(actual-expected)))
            checked += 1
            if max(errors.values()) > ATOL: failures.append(dict(timestamp_ms=obs['timestamp_ms'], **errors))
    return dict(comparable=True, passed=not failures, checked=checked, atol=ATOL, failures=failures,
        scope='observed_XYZ_to_worker_pose_and_wrist_with_recorded_context')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--model-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--redetect', action='store_true', help='Optional CPU IMAGE comparison; not a pass/fail test')
    args = parser.parse_args()
    capture = json.loads(args.recording.read_text(encoding='utf-8'))
    if capture.get('schema') != 'signvoice_camera_diagnostic_v1': raise ValueError('Unsupported diagnostic schema')
    config = json.loads((args.model_dir/'recognizer_config.json').read_text(encoding='utf-8'))
    identity = capture.get('worker_identity') or {}
    if identity.get('model_hashes') != config['sha256']: raise ValueError('Recorded bundle differs from supplied bundle')
    actual = hashlib.sha256(Path(runtime.__file__).read_bytes()).hexdigest()
    if identity.get('code_sha256', {}).get('model_runtime.py') != actual: raise ValueError('Recorded feature runtime differs')
    snapshots = capture.get('pixel_capture', {}).get('frames', [])
    if not snapshots or len(snapshots) > 60: raise ValueError('Need 1–60 opt-in PNG snapshots; older landmark-only JSON cannot supply pixels')
    detector = None
    if args.redetect:
        import mediapipe as mp
        if mp.__version__ != '0.10.32': raise ValueError('CPU comparison requires MediaPipe 0.10.32')
        model_path = args.model_dir/'hand_landmarker.task'
        if hashlib.sha256(model_path.read_bytes()).hexdigest() != config['sha256']['hand_landmarker.task']:
            raise ValueError('CPU detector model checksum differs')
        detector = mp.tasks.vision.HandLandmarker.create_from_options(mp.tasks.vision.HandLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path), delegate=mp.tasks.BaseOptions.Delegate.CPU),
            running_mode=mp.tasks.vision.RunningMode.IMAGE, num_hands=2,
            min_hand_detection_confidence=.15, min_hand_presence_confidence=.15, min_tracking_confidence=.22))
    rows = []; seen = set()
    try:
        for row in snapshots:
            stamp = row['timestamp_ms']
            if stamp in seen: raise ValueError('Duplicate PNG capture timestamp')
            seen.add(stamp)
            image, digest = decode_snapshot(row)
            obs = row['hand_observation']
            if obs['model_sha256'] != config['sha256']['hand_landmarker.task']: raise ValueError('Snapshot detector checksum differs')
            reading = dict(timestamp_ms=stamp, png_sha256=digest, width=row['width'], height=row['height'],
                raw_hands=len(row['raw_landmarks']), retained_hands=len(obs['landmarks']))
            if detector:
                result = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(image,cv2.COLOR_BGR2RGB)))
                points = [[[p.x,p.y,p.z] for p in hand] for hand in result.hand_landmarks]
                reading['cpu_image_vs_browser_raw'] = match_hands(row['raw_landmarks'], points, row['height']/row['width'])
            rows.append(reading)
    finally:
        if detector: detector.close()
    report = dict(schema='signvoice_camera_input_check_v1', recording_sha256=hashlib.sha256(args.recording.read_bytes()).hexdigest(),
        snapshots=rows, feature_conversion=feature_replay(capture,config),
        cpu_redetection_measured=args.redetect, webcam_accuracy_measured=False,
        cpu_redetection_settings=dict(mode='IMAGE',delegate='CPU',num_hands=2,
            min_hand_detection_confidence=.15,min_hand_presence_confidence=.15,min_tracking_confidence=.22) if args.redetect else None,
        limitations=['Sampled PNGs cannot reproduce VIDEO detector tracking history.',
            'CPU IMAGE vs browser VIDEO/delegate differences are descriptive, neither is ground truth.',
            'Recorded context is reused; face detector pixel-to-anchor parity is not tested.',
            'Recording PNGs changes runtime workload; use pixel-free captures for normal latency.'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    print(json.dumps(dict(output=str(args.output), snapshots=len(rows), feature_conversion=report['feature_conversion']),ensure_ascii=False))


if __name__ == '__main__': main()

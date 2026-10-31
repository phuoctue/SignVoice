"""Frozen local development cohort; paired full-stream component comparison.

No training, app changes, policy selection, audit access or webcam accuracy claim.
Raw source videos are checked against their recorded content hash and re-extracted
with the pinned runtime. Old landmark caches are intentionally not consumed.
"""
import argparse
import copy
import csv
import hashlib
import json
from pathlib import Path
import time
import zipfile
from concurrent.futures import ProcessPoolExecutor
import cv2
import numpy as np
from .diagnostic_replay import identity, plain
from .ensemble import ProbabilityEnsemble, softmax

VARIANTS = ('reference', 'tcn_words', 'embedding_words_tcn_background', 'embedding75')
_worker_engine = None


def digest(value):
    return hashlib.sha256(json.dumps(plain(value), sort_keys=True, ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(plain(value), ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
    tmp.replace(path)


def make_cohort(engine, manifest, archive, smoke):
    calibration = {r['video']: r['true'] for r in engine.base.config['word_validation_stream']['rows']}
    if len(calibration) != 297: raise ValueError('Unexpected app calibration cohort; register a new protocol')
    training = set(engine.base.config['train_video_ids'])
    if training & calibration.keys(): raise ValueError('Calibration/train overlap')
    with manifest.open(encoding='utf-8-sig') as f: source = list(csv.DictReader(f))
    items = []
    with zipfile.ZipFile(archive) as z:
        members = set(z.namelist())
        for row in source:
            ident = row['video_id']
            role = ('calibration_development' if ident in calibration else
                    'rau_train_pipeline_diagnostic' if ident in training and row['label'] == 'rau' else None)
            if role is None: continue
            if role == 'calibration_development' and row['label'] != calibration[ident]:
                raise ValueError('Source label differs from frozen model record')
            member = 'sources/' + row['video_path'].split('/sources/', 1)[1]
            if member not in members: raise FileNotFoundError(member)
            items.append(dict(video_id=ident, label=row['label'], role=role, member=member,
                source=row['source_dataset'], content_sha1=row['content_hash'],
                group=row.get('source_group') or row.get('session_id') or ident,
                independently_verified_signer=bool(row.get('signer_id')),
                semantic_review=row.get('semantic_review'),
                unverified_chao_khangcn=row['label'] == 'chào' and row['source_dataset'] == 'KhangCN/Video_VSL'))
    if len({i['video_id'] for i in items}) != len(items): raise ValueError('Duplicate cohort ID')
    if len(items) != 331: raise ValueError('Frozen cohort missing members')
    items.sort(key=lambda i: (i['role'], i['label'], i['video_id']))
    if smoke:
        # Registered smoke: at most 8 calibration labels, then two train rau clips.
        selected = []
        seen = set()
        for i in items:
            if i['role'] == 'calibration_development' and i['label'] not in seen and len(seen) < 8:
                selected.append(i); seen.add(i['label'])
        selected += [i for i in items if i['role'] == 'rau_train_pipeline_diagnostic'][:2]
        items = selected
    return items


class ComponentFusion:
    def __init__(self, original, variant):
        self.original, self.variant = original, variant
        self.embedding75 = ProbabilityEnsemble({**original.policy, 'tcn_weight': .25})

    def __call__(self, tcn, cosine):
        if self.variant == 'reference': return self.original(tcn, cosine)
        if self.variant == 'embedding75': return self.embedding75(tcn, cosine)
        calibrated = softmax(np.log(np.maximum(tcn, 1e-12)) / self.original.tcn_temperature)
        if self.variant == 'tcn_words': return calibrated
        if self.variant != 'embedding_words_tcn_background': raise ValueError('Unknown registered variant')
        background = calibrated[:, -1:]
        words = (1-background) * softmax(cosine / self.original.embedding_temperature)
        return np.concatenate([words, background], axis=1)


class InferenceMemo:
    """Memoize identical neural inputs across variants, not model-head decisions."""
    def __init__(self, fn): self.fn, self.values, self.hits = fn, {}, 0

    def __call__(self, inputs):
        arrays = inputs if isinstance(inputs, (list, tuple)) else [inputs]
        h = hashlib.sha256()
        for a in arrays:
            a = np.asarray(a)
            h.update(str((a.shape, a.dtype.str)).encode()); h.update(a.tobytes())
        key = h.hexdigest()
        if key not in self.values: self.values[key] = np.asarray(self.fn(inputs)).copy()
        else: self.hits += 1
        return self.values[key].copy()


def extract(engine, item, archive, output, extraction_contract):
    cache = output/'features'/(item['video_id']+'.npz')
    sidecar = cache.with_suffix('.json')
    if cache.exists() and sidecar.exists():
        metadata = json.loads(sidecar.read_text(encoding='utf-8'))
        if metadata['extraction_contract'] != extraction_contract or metadata['feature_sha256'] != file_hash(cache):
            raise ValueError('Feature cache identity/checksum mismatch')
        with np.load(cache, allow_pickle=False) as z:
            return tuple(z[k].copy() for k in ('pose', 'wrist', 'times', 'context')), metadata
    source_path = output/'sources'/(item['video_id']+'.mp4')
    source_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z: raw = z.read(item['member'])
    if hashlib.sha1(raw).hexdigest() != item['content_sha1']:
        raise ValueError('Source content hash mismatch: '+item['video_id'])
    source_path.write_bytes(raw)
    source_sha256 = hashlib.sha256(raw).hexdigest()
    del raw
    cap = cv2.VideoCapture(str(source_path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not np.isfinite(fps) or fps <= 0: raise ValueError('Invalid video clock')
    r = engine.runtime
    context = r.SigningContextTracker(engine.folder/'face_detector.tflite')
    tracker = r.HandSlotTracker()
    import mediapipe as mp
    poses, wrists, times, anchors = [], [], [], []
    next_time, frame = 0., 0
    start = time.perf_counter()
    try:
        # Offline CPU VIDEO detector, no optical-flow repair or parallel context.
        # This is a common causal input stream for comparison, not Chrome GPU parity.
        with r.ResilientHandLandmarker(engine.folder/'hand_landmarker.task', video=True, opencv_assist=False) as detector:
            detector.target_hands = 2
            detector.search_regions = True
            while True:
                ok, image = cap.read()
                if not ok: break
                now = frame/fps; frame += 1
                if now+1e-6 < next_time: continue
                next_time += 1/15
                if image.shape[1] != 640:
                    image = cv2.resize(image, (640, round(image.shape[0]*640/image.shape[1])))
                height, width = image.shape[:2]
                anchor = context.update(image, now)
                result = detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB,
                    data=cv2.cvtColor(image, cv2.COLOR_BGR2RGB)), int(round(now*1000)))
                result = r.foreground_hand_result(result, width, height, anchor)
                p, w, _ = r.features_from_result(result, width, height, False, allow_low_hands=True,
                    tracker=tracker, now=now, keep_both_hands=True)
                poses.append(p); wrists.append(w); times.append(now); anchors.append(anchor)
    finally:
        cap.release(); context.close()
    if not times: raise ValueError('Empty video')
    arrays = np.asarray(poses, np.float32), np.asarray(wrists, np.float32), np.asarray(times, np.float64), np.asarray(anchors, np.float32)
    if not all(np.isfinite(a).all() for a in arrays) or (np.diff(arrays[2]) <= 0).any():
        raise ValueError('Nonfinite or unordered observations')
    cache.parent.mkdir(parents=True, exist_ok=True)
    with cache.with_suffix('.tmp').open('wb') as f:
        np.savez_compressed(f, **dict(zip(('pose', 'wrist', 'times', 'context'), arrays)))
    cache.with_suffix('.tmp').replace(cache)
    metadata = dict(extraction_contract=extraction_contract, feature_sha256=file_hash(cache),
        source_sha256=source_sha256, source_sha1=item['content_sha1'], input_fps=fps,
        frames=len(times), extraction_seconds=time.perf_counter()-start,
        observed_hand_ratio=float(np.any(arrays[0] != 0, axis=1).mean()))
    write_json(sidecar, metadata)
    return arrays, metadata


def evaluate(engine, arrays):
    r = engine.runtime
    base = engine.base.word_head
    infer, embed = InferenceMemo(base.infer), InferenceMemo(base.embed)
    result = {}
    reference_trace = []
    for variant in (*VARIANTS, 'reference_memo_control'):
        effective_variant = 'reference' if variant == 'reference_memo_control' else variant
        recognizer = copy.copy(engine.base)
        recognizer.word_head = r.TemporalWordHead(list(base.labels), copy.deepcopy(base.config), infer,
            embed=embed, centers=base.centers, mean=base.mean, std=base.std,
            probability_fusion=ComponentFusion(base.probability_fusion, effective_variant))
        recognizer.set_mode('words')
        session = r.LiveSession(recognizer, False)
        fresh_predictions = 0
        rejections = {}
        for index, (p, w, now, context) in enumerate(zip(*arrays)):
            before = session.last_prediction
            session.update(p, w, float(now), context=context)
            current = session.decision.smoothed
            if variant == 'reference':
                reference_trace.append(None if current is None else current.copy())
            elif variant == 'reference_memo_control':
                wanted = reference_trace[index]
                equal = current is None and wanted is None
                if current is not None and wanted is not None:
                    equal = current.shape == wanted.shape and np.allclose(current, wanted, atol=2e-5, rtol=5e-4)
                if not equal: raise RuntimeError('Memoized reference score control failed')
            if before != session.last_prediction:
                fresh_predictions += 1
                for reason in recognizer.word_head.last_diagnostics.get('rejection_reasons', []):
                    rejections[reason] = rejections.get(reason, 0)+1
        result[variant] = dict(events=plain(session.events),
            pred=session.events[-1]['label'] if session.events else None,
            prediction_steps=fresh_predictions, rejections=rejections)
        if variant == 'reference_memo_control' and result[variant] != result['reference']:
            raise RuntimeError('Memoized reference event/decision control failed')
    result['null_control_passed'] = True
    result['memo'] = dict(infer_misses=len(infer.values), infer_hits=infer.hits,
                          embed_misses=len(embed.values), embed_hits=embed.hits)
    return result


def metrics(rows, variant):
    by_label = {}
    correct = wrong = missing = wrong_events = duplicate_events = 0
    first_correct = []
    for row in rows:
        outcome = row['results'][variant]
        truth = row['item']['label']
        pair = by_label.setdefault(truth, [0, 0]); pair[1] += 1
        if outcome['pred'] == truth: correct += 1; pair[0] += 1
        elif outcome['pred'] is None: missing += 1
        else: wrong += 1
        events = outcome['events']
        wrong_events += sum(e['label'] != truth for e in events)
        duplicate_events += sum(a['label'] == b['label'] for a, b in zip(events, events[1:]))
        hits = [e['time'] for e in events if e['label'] == truth]
        if hits: first_correct.append(hits[0])
    return dict(videos=len(rows), labels=len(by_label), correct=correct, wrong=wrong, none=missing,
        accepted_precision=correct/(correct+wrong) if correct+wrong else None,
        coverage=(correct+wrong)/len(rows) if rows else None,
        macro_recall=float(np.mean([a/b for a, b in by_label.values()])) if by_label else None,
        wrong_events=wrong_events, consecutive_duplicate_events=duplicate_events,
        first_correct_seconds_from_clip_start_median=float(np.median(first_correct)) if first_correct else None,
        by_label={k:dict(correct=a, videos=b) for k,(a,b) in by_label.items()})


def paired(rows, variant):
    gained = lost = 0
    clusters = {}
    labels = sorted({r['item']['label'] for r in rows})
    for row in rows:
        item = row['item']; truth = item['label']
        a = row['results']['reference']['pred'] == truth
        b = row['results'][variant]['pred'] == truth
        gained += b and not a; lost += a and not b
        count, delta = clusters.setdefault(item['group'], (np.zeros(len(labels)), np.zeros(len(labels))))
        j = labels.index(truth); count[j] += 1; delta[j] += int(b)-int(a)
    count = np.array([x[0] for x in clusters.values()]); delta = np.array([x[1] for x in clusters.values()])
    intervals = []
    rng = np.random.default_rng(20261022)
    if len(clusters) >= 5:
        den = count.sum(axis=0)
        class_delta = delta.sum(axis=0)/den
        point = float(np.mean(class_delta))
        # Linearized paired ratio estimator: center each class's contribution.
        # This avoids inventing zero recall when a rare class is not resampled,
        # and avoids adding noise solely from resampled class frequencies.
        residual = delta-count*class_delta
        for _ in range(2000):
            ix = rng.integers(0, len(clusters), len(clusters))
            intervals.append(point+float(np.mean(residual[ix].sum(axis=0)/den)))
    return dict(gained=int(gained), lost=int(lost), clusters=len(clusters),
        signer_holdout_verified=all(r['item']['independently_verified_signer'] for r in rows),
        bootstrap_method='linearized paired cluster bootstrap of macro-recall delta; fixed class weights and centered per-class residuals',
        bootstrap_complete_replicates=len(intervals),
        macro_recall_delta_ci95=[float(v) for v in np.quantile(intervals, [.025,.975])] if len(intervals)>=100 else None,
        ci_unavailable_reason=None if len(intervals)>=100 else 'Too few bootstrap replicates covering every label',
        mcnemar_discordant=[int(gained),int(lost)])


def summarize(rows, cohort_size):
    cal = [r for r in rows if r['item']['role'] == 'calibration_development']
    verified_subset = [r for r in cal if not r['item']['unverified_chao_khangcn']]
    train = [r for r in rows if r['item']['role'] == 'rau_train_pipeline_diagnostic']
    return dict(complete=len(rows) == cohort_size, processed=len(rows), expected=cohort_size,
        deployment_eligible=False, real_background_measured=False, automatic_policy_selection=False,
        evaluation_scope='Repeatedly exposed development clips; source labels not independently re-reviewed',
        calibration={v:metrics(cal,v) for v in VARIANTS},
        excluding_unverified_chao_khangcn={v:metrics(verified_subset,v) for v in VARIANTS},
        rau_train_diagnostic={v:metrics(train,v) for v in VARIANTS},
        paired_calibration={v:paired(cal,v) for v in VARIANTS if v != 'reference'})


def initialize_worker(model_dir):
    global _worker_engine
    from .engine import Engine
    _worker_engine = Engine(model_dir)


def run_item(job):
    item, archive, output, extraction_id = job
    arrays, metadata = extract(_worker_engine, item, archive, output, extraction_id)
    return item, metadata, evaluate(_worker_engine, arrays)


def main():
    from .engine import Engine
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model-dir', type=Path, required=True)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true')
    p.add_argument('--workers', type=int, choices=(1,2), default=2)
    args = p.parse_args()
    engine = Engine(args.model_dir)
    if engine.ensemble is None: raise ValueError('Missing reference ensemble')
    cohort = make_cohort(engine, args.manifest, args.archive, args.smoke)
    contract = dict(version=1, smoke=args.smoke, model_identity=identity(engine,'words'),
        evaluator_sha256=file_hash(__file__), manifest_sha256=file_hash(args.manifest), cohort=cohort,
        variants=list(VARIANTS), policy=dict(engine.base.word_head.policy),
        sampling='causal 15Hz from source frame indices, resize width640, no mirroring, CPU VIDEO detector, synchronous measured face context, opencv assist off',
        fusion='reference; calibrated TCN; conditional embedding with TCN background; fixed TCN weight0.25',
        pred_definition='last completed LiveSession event label, or None',
        no_audit_access=True, no_model_selection=True, no_threshold_search=True,
        timing='first correct event from clip start; not gesture onset or device latency',
        background_false_accept_unknown=True,
        precision_floor=.95, all_variants_development_only=True)
    contract['paired_inference'] = '2000 linearized paired cluster resamples; fixed class weights and centered per-class residuals; unknown signer IDs are not signer holdout'
    contract['memo_control'] = 'repeat reference after alternatives; all input-step smoothed vectors and completed events must match'
    contract['workers'] = args.workers
    contract_id = digest(contract)
    args.output.mkdir(parents=True, exist_ok=True)
    existing = args.output/'contract.json'
    if existing.exists() and digest(json.loads(existing.read_text(encoding='utf-8'))) != contract_id:
        raise ValueError('Output contains a different frozen contract; use a separate directory')
    write_json(existing, contract)
    journal = args.output/'results.jsonl'
    done = {}
    if journal.exists():
        for line in journal.read_text(encoding='utf-8').splitlines():
            row = json.loads(line)
            if row['contract_sha256'] != contract_id: raise ValueError('Journal contract mismatch')
            key = row['item']['video_id']
            if key in done: raise ValueError('Duplicate journal row')
            done[key] = row
    expected = {i['video_id']:i for i in cohort}
    if any(key not in expected or row['item'] != expected[key] for key,row in done.items()):
        raise ValueError('Journal cohort mismatch')
    extraction_id = digest(dict(model_identity=contract['model_identity'], sampling=contract['sampling']))
    started = time.perf_counter()
    jobs = [(i, args.archive, args.output, extraction_id) for i in cohort if i['video_id'] not in done]
    with ProcessPoolExecutor(max_workers=args.workers, initializer=initialize_worker,
                             initargs=(str(args.model_dir),)) as pool:
        for item, metadata, results in pool.map(run_item, jobs):
            row = dict(contract_sha256=contract_id, item=item, features=metadata, results=results)
            with journal.open('a', encoding='utf-8') as f:
                f.write(json.dumps(plain(row), ensure_ascii=False, allow_nan=False)+'\n'); f.flush()
            done[item['video_id']] = row
            print(json.dumps(dict(processed=len(done),total=len(cohort),id=item['video_id'],
                label=item['label'],role=item['role'],elapsed_seconds=round(time.perf_counter()-started,1),
                preds={v:results[v]['pred'] for v in VARIANTS}),ensure_ascii=True),flush=True)
            # Lightweight progress is saved for every clip; bootstrap runs at the end.
            write_json(args.output/'status.json', dict(processed=len(done),expected=len(cohort),contract_sha256=contract_id))
    report = summarize([done[i['video_id']] for i in cohort],len(cohort))
    report['contract_sha256'] = contract_id
    write_json(args.output/'comparison.json', report)
    print(json.dumps(dict(complete=report['complete'],processed=len(done),output=str(args.output.resolve()))),flush=True)


if __name__ == '__main__': main()

"""Read-only component/window diagnostics with an unchanged-output replay control.

Run offline, never imported by the camera service. No threshold or model selection.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from .diagnostic_replay import identity, plain, replay
from .ensemble import softmax


def digest_features(pair):
    return hashlib.sha256(np.asarray(pair[0]).tobytes() + np.asarray(pair[1]).tobytes()).hexdigest()


def swap_features(pair):
    shape, motion = pair
    shape = shape.reshape(-1, 2, 63)[:, ::-1].reshape(-1, 126).copy()
    swapped = motion.copy()
    swapped[:, :6] = motion[:, :6].reshape(-1, 2, 3)[:, ::-1].reshape(-1, 6)
    swapped[:, 6:12] = motion[:, 6:12].reshape(-1, 2, 3)[:, ::-1].reshape(-1, 6)
    swapped[:, 12:14] = motion[:, 12:14][:, ::-1]
    swapped[:, 15:18] *= -1
    return shape, swapped


def describe(values, names, targets):
    values = np.asarray(values)
    order = np.argsort(-values)
    return dict(top3=[dict(label=names[int(i)], score=float(values[i])) for i in order[:3]],
        targets={name: dict(score=float(values[names.index(name)]),
                           rank=int(np.flatnonzero(order == names.index(name))[0]) + 1)
                 for name in targets})


class FusionTap:
    def __init__(self, original):
        self.original = original
        self.calls = []

    def __call__(self, tcn, cosine):
        result = self.original(tcn, cosine)
        self.calls.append((tcn.copy(), cosine.copy(), result.copy()))
        return result  # Do not recompute, renormalize or change the original output.


def source_comparison(runtime_path, desktop_path):
    def nodes(path):
        return {n.name: n for n in ast.parse(path.read_text(encoding='utf-8')).body
                if isinstance(n, (ast.FunctionDef, ast.ClassDef))}
    app, desktop = nodes(runtime_path), nodes(desktop_path)
    names = ('HandSlotTracker', 'features_from_result', 'normalize_pose', 'gesture_interval',
             'word_temporal_features', 'prepare_sign_sequence', 'GestureBuffer', 'StableDecision',
             'TemporalWordHead', 'LiveSession')
    return dict(desktop_sha256=hashlib.sha256(desktop_path.read_bytes()).hexdigest(),
        ast_equal={name: ast.dump(app[name], include_attributes=False) ==
                   ast.dump(desktop[name], include_attributes=False) for name in names})


def inspect(engine, capture, desktop_path):
    manifest = capture['worker_identity']
    if identity(engine, manifest['mode']) != manifest:
        raise ValueError('Model/config/code identity mismatch; inspection refused')
    if capture['truncated'] or any(m.get('worker_diagnostic', {}).get('truncated') for m in capture['messages']):
        raise ValueError('Truncated capture')
    rows = [r for m in capture['messages'] for r in m.get('worker_diagnostic', {}).get('records', [])]
    if not rows: raise ValueError('No recorded worker batches')
    recognizer = copy.copy(engine.base)
    base = engine.base.word_head
    tap = FusionTap(base.probability_fusion)
    if base.probability_fusion is None: raise ValueError('This diagnostic requires an active probability ensemble')
    head = engine.runtime.TemporalWordHead(list(base.labels), copy.deepcopy(base.config), base.infer,
        embed=base.embed, centers=base.centers, mean=base.mean, std=base.std, probability_fusion=tap)
    recognizer.word_head = head
    recognizer.set_mode(manifest['mode'])
    session = engine.runtime.LiveSession(recognizer, False)
    targets = ['chào', 'nghe', 'nhìn', 'rau']
    names = list(head.names)
    feature_metadata = {}
    steps = []
    current = {}
    consumed_calls = 0
    desktop_tree = ast.parse(desktop_path.read_text(encoding='utf-8'))
    desktop_prepare_node = next(n for n in desktop_tree.body if isinstance(n, ast.FunctionDef)
                                and n.name == 'prepare_sign_sequence')
    namespace = dict(vars(engine.runtime))
    exec(compile(ast.Module(body=[desktop_prepare_node], type_ignores=[]), str(desktop_path), 'exec'), namespace)
    desktop_prepare = namespace['prepare_sign_sequence']
    prepare_checks = dict(candidates=0, pose_or_wrist_different=0, observation_masks_corrected=0)
    feature_code = engine.runtime.word_temporal_features.__code__
    predict_code = type(head).predict.__code__

    def profile(frame, event, arg):
        nonlocal consumed_calls
        if event == 'call' and frame.f_code is predict_code:
            current.clear()
            feature_metadata.clear()
            current.update(time=float(session.last_prediction),
                candidates=[dict(start=float(c[3][0]), end=float(c[3][-1]), frames=len(c[0]))
                            for c in frame.f_locals['candidates']])
            for c in frame.f_locals['candidates']:
                desktop_p, desktop_w = desktop_prepare(c[0], c[1])
                app_p, app_w, app_mask = engine.runtime.prepare_sign_sequence(c[0], c[1], c[4])
                prepare_checks['candidates'] += 1
                if not (np.array_equal(desktop_p, app_p) and np.array_equal(desktop_w, app_w)):
                    prepare_checks['pose_or_wrist_different'] += 1
                if not np.array_equal(app_mask, c[4]): prepare_checks['observation_masks_corrected'] += 1
        if event != 'return': return
        if frame.f_code is feature_code and isinstance(arg, tuple):
            clock = frame.f_locals['times']
            feature_metadata[digest_features(arg)] = dict(start=float(clock[0]), end=float(clock[-1]),
                frames=len(frame.f_locals['pose']))
        if frame.f_code is not predict_code: return
        loc = frame.f_locals
        if not loc.get('batches'):
            steps.append({**current, 'inference_ran': False, 'diagnostic': plain(head.last_diagnostics)})
            return
        if len(tap.calls) != consumed_calls + 1: raise RuntimeError('Fusion/profile call mismatch')
        tcn, cosine, fused = tap.calls[-1]
        consumed_calls += 1
        embedding = softmax(cosine / tap.original.embedding_temperature)
        calibrated_tcn = softmax(np.log(np.maximum(tcn, 1e-12)) / tap.original.tcn_temperature)
        windows = []
        for i, pair in enumerate(loc['batches']):
            clock = feature_metadata.get(digest_features(pair))
            if clock is None: clock = feature_metadata.get(digest_features(swap_features(pair)))
            if clock is None: raise RuntimeError('Cannot identify exact candidate window')
            windows.append(dict(index=i, selected=i == int(loc['best']),
                feature_sha256=digest_features(pair), interval=clock,
                swapped=bool(loc['variants'][i]), eligible=bool(loc['eligible'][i]),
                raw_supported=bool(loc['raw_supported'][i]), quality=float(loc['quality'][i]),
                hand_coverage=float(loc['coverage'][i]), observations=int(loc['observations'][i]),
                mask_targets={n: bool(loc['masks'][i][names.index(n)]) for n in targets},
                tcn=describe(calibrated_tcn[i], names + ['__background__'], targets),
                embedding_cosine=describe(cosine[i], names, targets),
                embedding_probability=describe(embedding[i], names, targets),
                fused=describe(fused[i], names + ['__background__'], targets),
                legacy_mixed_scale_at_same_weight=describe(np.concatenate([
                    (1-head.policy['embed_weight'])*tcn[i, :-1]+head.policy['embed_weight']*cosine[i],
                    (1-head.policy['embed_weight'])*tcn[i, -1:]]), names + ['__background__'], targets),
                s0_targets={n: float(loc['s0'][i, names.index(n)]) for n in targets},
                s1_targets={n: float(loc['s1'][i, names.index(n)]) for n in targets}))
        steps.append({**current, 'inference_ran': True, 'selected': int(loc['best']),
            'diagnostic': plain(head.last_diagnostics), 'windows': windows})

    previous_profile = sys.getprofile()
    try:
        sys.setprofile(profile)
        control = replay(session, rows)
    finally:
        sys.setprofile(previous_profile)
    if not control['passed']: raise RuntimeError('Observation hook changed replay: ' + json.dumps(control))
    if consumed_calls != len(tap.calls): raise RuntimeError('Missing observed fusion calls')
    return dict(purpose='development_component_inspection_only', policy_changed=False,
        accuracy_claim=False, replay_control=control,
        source_comparison=source_comparison(Path(__file__).with_name('model_runtime.py'), desktop_path),
        prepare_sequence_numerical_control=prepare_checks,
        identity=manifest, component_calls=consumed_calls,
        cautions=['Cosine and softmax values have different scales; compare ranks and calibrated distributions.',
                  'Component predictions are inspected on the window selected by the unchanged ensemble; no oracle window selection.',
                  'Exact gesture/video boundaries are not independently labeled.'], steps=steps)


def main():
    from .engine import Engine
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture', type=Path)
    p.add_argument('--model-dir', type=Path, required=True)
    p.add_argument('--desktop', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    capture_bytes = args.capture.read_bytes()
    capture = json.loads(capture_bytes)
    report = inspect(Engine(args.model_dir), capture, args.desktop)
    report['capture_sha256'] = hashlib.sha256(capture_bytes).hexdigest()
    report['observer_source_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plain(report), ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
    print(json.dumps(dict(replay_control=report['replay_control'], component_calls=report['component_calls'],
        source_comparison=report['source_comparison'], output=str(args.output.resolve())), indent=2))


if __name__ == '__main__': main()

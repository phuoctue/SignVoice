"""Opt-in in-memory worker journal and deterministic feature replay.

No camera pixels, tokens or disk writes. Export is initiated by the client.
This checks sequence recognition, not pixel extraction or webcam accuracy.
"""
import copy
import hashlib
import json
from pathlib import Path
import numpy as np

ATOL = 2e-5
RTOL = 5e-4


def plain(value):
    if isinstance(value, np.ndarray): return plain(value.tolist())
    if isinstance(value, np.generic): return plain(value.item())
    if isinstance(value, dict): return {str(k): plain(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)): return [plain(v) for v in value]
    if isinstance(value, float) and not np.isfinite(value): return None
    return value


def identity(engine, mode):
    files = ('model_runtime.py', 'recognition_worker.py', 'diagnostic_replay.py', 'engine.py')
    config = plain(engine.base.config)
    policy = plain(engine.base.word_head.policy)
    ensemble = None if engine.ensemble is None else plain(engine.ensemble.policy)
    return dict(mode=mode, manifest_sha256=engine.manifest_sha256,
        model_hashes=config['sha256'], policy=policy, ensemble=ensemble,
        config_sha256=hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
        code_sha256={f: hashlib.sha256(Path(__file__).with_name(f).read_bytes()).hexdigest() for f in files})


def decision_state(session):
    """Observe existing state; do not duplicate/replace the decision algorithm."""
    d = session.decision
    fields = ('candidate', 'since', 'confirmed', 'last_good', 'latch_until', 'last_time',
              'minimum', 'margin', 'dynamic_minimum', 'dynamic_margin', 'static_dwell', 'word_policy')
    result = {key: getattr(d, key) for key in fields if hasattr(d, key)}
    result['runtime_diagnostics'] = getattr(d, 'last_diagnostics', None)
    # This pinned runtime may not expose rejection reasons. Keep that explicit;
    # never fabricate a cause from an absent field or from a stale prediction.
    result['rejection_reason_available'] = bool(getattr(d, 'last_diagnostics', None))
    result['last_prediction'] = getattr(session, 'last_prediction', None)
    return result


class WorkerJournal:
    """Access only under the worker condition lock; stop at the bound, never slide."""
    def __init__(self, limit=600):
        self.limit = limit
        self.records = []
        self.cursor = 0
        self.truncated = False
        self.bytes = 0

    def add(self, session, batch, generation, mode, batch_ms, overruns, prediction_at=None):
        if len(self.records) >= self.limit:
            self.truncated = True
            return
        selected=len(batch)-1 if prediction_at is None else prediction_at
        record = plain(dict(index=len(self.records), generation=generation, mode=mode,
            inputs=[dict(pose=p, wrist=w, time=t, context=c, allow_prediction=i == selected)
                    for i, (p, w, t, c) in enumerate(batch)],
            output=session.output, scores=session.decision.smoothed,
            events=session.events, worker_batch_ms=batch_ms, observation_overruns=overruns,
            decision=decision_state(session),
            window=getattr(session.recognizer.word_head, 'last_diagnostics', {})))
        if prediction_at is not None:
            record['prediction_scheduler']='latest_observed_word_v1'
        size = len(json.dumps(record, allow_nan=False).encode())
        if self.bytes + size > 6000000:
            self.truncated = True
            return
        self.bytes += size
        self.records.append(record)

    def drain(self):
        rows = self.records[self.cursor:]
        self.cursor = len(self.records)
        return dict(records=rows, recorded_batches=len(self.records), truncated=self.truncated)


def replay(session, rows):
    failures = []
    generation = None
    for index, row in enumerate(rows):
        if row['index'] != index: raise ValueError('Missing/reordered worker batches; replay refused')
        if generation != row['generation']:
            session.recognizer.set_mode(row['mode'])
            session.reset()
            generation = row['generation']
        strategy=row.get('prediction_scheduler','latest_v1')
        if strategy=='latest_v1':selected=len(row['inputs'])-1
        elif strategy=='latest_observed_word_v1':
            from .recognition_worker import prediction_index
            batch=[(np.asarray(x['pose'],np.float32),None,x['time'],None) for x in row['inputs']]
            selected=prediction_index(batch,row['mode'])
        else:raise ValueError('Unknown prediction scheduler')
        for i, item in enumerate(row['inputs']):
            if not isinstance(item['allow_prediction'],bool) or item['allow_prediction'] != (i == selected):
                raise ValueError('Invalid prediction mask')
            session.update(np.asarray(item['pose'], np.float32), np.asarray(item['wrist'], np.float32),
                item['time'], allow_prediction=item['allow_prediction'], context=np.asarray(item['context'], np.float32))
        actual = plain(session.decision.smoothed)
        expected = row['scores']
        scores_equal = (actual is None and expected is None) or (actual is not None and expected is not None
            and np.shape(actual) == np.shape(expected) and np.allclose(actual, expected, rtol=RTOL, atol=ATOL))
        out, wanted = plain(session.output), row['output']
        # Label, confirmed flag and event frame/order must be exact; numeric evidence may vary within tolerance.
        output_equal = out is None and wanted is None
        if out is not None and wanted is not None:
            output_equal = (len(out) == len(wanted) and out[0] == wanted[0]
                and out[1] == wanted[1] and out[3] == wanted[3] and out[-1] == wanted[-1]
                and np.allclose(out[2], wanted[2], rtol=RTOL, atol=ATOL)
                and np.allclose(out[4], wanted[4], rtol=RTOL, atol=ATOL))
        events_equal = plain(session.events) == row['events']
        if not (scores_equal and output_equal and events_equal):
            failures.append(dict(batch=index, scores=scores_equal, decision=output_equal, events=events_equal))
    return dict(passed=not failures, batches=len(rows), failures=failures, atol=ATOL, rtol=RTOL,
        scope='worker_features_only', webcam_accuracy_measured=False)


def main():
    import argparse
    from .engine import Engine
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--model-dir', required=True, type=Path)
    args = parser.parse_args()
    capture = json.loads(args.recording.read_text(encoding='utf-8'))
    if capture.get('schema') != 'signvoice_camera_diagnostic_v1' or not isinstance(capture.get('worker_identity'), dict):
        raise ValueError('Missing diagnostic handshake; restart the updated service and record again')
    records = [r for m in capture['messages'] for r in m.get('worker_diagnostic', {}).get('records', [])]
    if not records: raise ValueError('No worker batches exported')
    if capture.get('truncated') or any(m.get('worker_diagnostic', {}).get('truncated') for m in capture['messages']):
        raise ValueError('Bound reached: use a shorter recording')
    engine = Engine(args.model_dir)
    manifest = capture['worker_identity']
    if identity(engine, manifest['mode']) != manifest: raise ValueError('Model/config/code identity mismatch')
    recognizer = copy.copy(engine.base)
    head = engine.base.word_head
    recognizer.word_head = engine.runtime.TemporalWordHead(list(head.labels), copy.deepcopy(head.config), head.infer,
        embed=head.embed, centers=head.centers, mean=head.mean, std=head.std, probability_fusion=head.probability_fusion)
    recognizer.set_mode(manifest['mode'])
    result = replay(engine.runtime.LiveSession(recognizer, False), records)
    print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
    if not result['passed']: raise SystemExit(1)


if __name__ == '__main__': main()

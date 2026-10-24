"""Sequence inference with coherent timing/evidence snapshots for the camera."""
from collections import deque
import threading
import time
import numpy as np


def prediction_index(batch, mode):
    """Use one fresh measured hand, even when a word batch ends with empty frames."""
    if not batch:
        return -1
    last = len(batch) - 1
    if mode != 'words' or np.any(batch[last][0]):
        return last
    for index in range(last - 1, -1, -1):
        if batch[last][2] - batch[index][2] > .25:
            break
        if np.any(batch[index][0]):
            return index
    return last


class RecognitionWorker:
    def __init__(self, session):
        self.session = session
        self.condition = threading.Condition()
        self.pending = deque(maxlen=180)
        self.generation = self.applied_generation = 0
        self.mode = session.recognizer.mode
        self.snapshot = (None, None, False, None, None)
        self.details = {}
        self.error = None
        self.stopped = False
        self.event_start = len(session.events)
        self.overruns = 0
        self.last_inference_ms = None
        self.on_update = None
        self.journal = None  # Explicit client opt-in; no inputs retained by default.
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def submit(self, pose, wrist, now, context=None):
        anchor = np.zeros(4, np.float32) if context is None else np.asarray(context, np.float32)
        with self.condition:
            if len(self.pending) == self.pending.maxlen:
                self.overruns += 1
            self.pending.append((pose.copy(), wrist.copy(), now, anchor.copy()))
            self.condition.notify_all()

    def reset(self, mode=None):
        with self.condition:
            if mode is not None:
                self.mode = mode
            self.generation += 1
            self.pending.clear()
            self.snapshot = (None, None, False, None, None)
            self.details = {}
            self.condition.notify_all()

    def poll_with_details(self):
        with self.condition:
            if self.error is not None:
                raise RuntimeError('Sequence recognition failed: ' + str(self.error))
            return self.snapshot, dict(self.details)

    def poll(self):
        return self.poll_with_details()[0]

    def enable_diagnostics(self):
        from .diagnostic_replay import WorkerJournal
        with self.condition:
            self.journal = WorkerJournal()

    def drain_diagnostics(self):
        with self.condition:
            return None if self.journal is None else self.journal.drain()

    def _run(self):
        try:
            while True:
                with self.condition:
                    self.condition.wait_for(lambda: self.pending or self.generation != self.applied_generation or self.stopped)
                    if self.stopped:
                        return
                    generation, mode = self.generation, self.mode
                    batch = list(self.pending)
                    self.pending.clear()
                if generation != self.applied_generation:
                    self.session.recognizer.set_mode(mode)
                    self.session.reset()
                    self.applied_generation = generation
                    self.event_start = len(self.session.events)
                    self.last_inference_ms = None
                started = time.perf_counter()
                before = self.session.last_prediction
                prediction_at = prediction_index(batch, mode)
                for i, (pose, wrist, now, anchor) in enumerate(batch):
                    self.session.update(pose, wrist, now, allow_prediction=i == prediction_at, context=anchor)
                output = self.session.output
                smoothed = self.session.decision.smoothed
                scores = None if smoothed is None else smoothed.copy()
                collision = None if scores is None else self.session.recognizer.domain_collision(scores)
                head = self.session.recognizer.word_head
                batch_ms = round(1000 * (time.perf_counter() - started), 1)
                prediction_ran = self.session.last_prediction != before
                if prediction_ran:
                    self.last_inference_ms = batch_ms
                details = dict(
                    inference_ms=self.last_inference_ms, worker_batch_ms=batch_ms,
                    prediction_timestamp_ms=(round(1000 * self.session.last_prediction)
                                             if np.isfinite(self.session.last_prediction) else None),
                    prediction_ran=prediction_ran,
                    observation_timestamp_ms=round(1000 * batch[-1][2]) if batch else None,
                    observations=len(batch), observation_overruns=self.overruns,
                    prediction_scheduler='latest_observed_word_v1',
                    word=dict(head.last_diagnostics) if head is not None else {})
                with self.condition:
                    if generation == self.generation:
                        if self.journal is not None and batch:
                            self.journal.add(self.session, batch, generation, mode, batch_ms, self.overruns,
                                             prediction_at=prediction_at)
                        completed = self.session.events[-1].copy() if len(self.session.events) > self.event_start else None
                        self.snapshot = (output, scores, self.session.hold.anchor is not None, collision, completed)
                        self.details = details
                        notify = self.on_update
                    else:
                        notify = None
                if notify is not None:
                    notify()
        except Exception as error:
            with self.condition:
                self.error = error
            if self.on_update is not None:
                self.on_update()

    def close(self):
        with self.condition:
            self.stopped = True
            self.condition.notify_all()
        self.thread.join(timeout=3.)

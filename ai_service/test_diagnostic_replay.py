import copy
import unittest
from types import SimpleNamespace
import numpy as np
from .diagnostic_replay import WorkerJournal, replay


class FakeSession:
    def __init__(self):
        self.recognizer = SimpleNamespace(set_mode=lambda mode: None, word_head=None)
        self.decision = SimpleNamespace(smoothed=None)
        self.events = []
        self.reset()

    def reset(self):
        self.total = 0
        self.output = None
        self.decision.smoothed = None

    def update(self, pose, wrist, now, allow_prediction=True, context=None):
        self.total += pose[0]
        if allow_prediction:
            self.decision.smoothed = np.array([self.total, now], dtype=np.float32)
            self.output = (0, [0, 1], .5, True, [.9, .1], True)
            self.events.append(dict(time=now, label='test'))


class ReplayTests(unittest.TestCase):
    def fixture(self):
        session = FakeSession()
        journal = WorkerJournal()
        batch = [(np.ones(126), np.zeros(8), float(i), np.zeros(4)) for i in (1, 2)]
        for i, (p, w, now, c) in enumerate(batch):
            session.update(p, w, now, allow_prediction=i == 1, context=c)
        journal.add(session, batch, 1, 'words', 2., 0)
        return journal

    def test_round_trip_preserves_batch_mask_and_events(self):
        journal = self.fixture()
        self.assertTrue(replay(FakeSession(), journal.records)['passed'])
        self.assertEqual([r['allow_prediction'] for r in journal.records[0]['inputs']], [False, True])
        self.assertEqual(len(journal.drain()['records']), 1)
        self.assertEqual(journal.drain()['records'], [])

    def test_wrong_scores_flags_or_duplicate_events_fail(self):
        for field, value in [('scores', [100, 200]), ('events', []),
                             ('output', [0, [0, 1], .5, False, [.9, .1], True])]:
            rows = copy.deepcopy(self.fixture().records)
            rows[0][field] = value
            self.assertFalse(replay(FakeSession(), rows)['passed'], field)

    def test_missing_batches_and_changed_masks_refused(self):
        rows = self.fixture().records
        rows[0]['index'] = 1
        with self.assertRaisesRegex(ValueError, 'Missing'): replay(FakeSession(), rows)
        rows[0]['index'] = 0
        rows[0]['inputs'][0]['allow_prediction'] = True
        with self.assertRaisesRegex(ValueError, 'mask'): replay(FakeSession(), rows)

    def test_bound_does_not_slide_or_retain_later_samples(self):
        journal = self.fixture()
        journal.limit = 1
        journal.add(FakeSession(), [], 1, 'words', 0., 0)
        self.assertTrue(journal.truncated)
        self.assertEqual(len(journal.records), 1)

    def test_word_tail_scheduler_is_recorded_and_replayed_exactly(self):
        session=FakeSession();journal=WorkerJournal()
        batch=[(np.full(126,p),np.zeros(8),t,np.zeros(4)) for t,p in [(1.,1),(1.1,1),(1.2,0)]]
        for i,(p,w,t,c) in enumerate(batch):session.update(p,w,t,allow_prediction=i==1,context=c)
        journal.add(session,batch,1,'words',0.,0.,prediction_at=1)
        self.assertEqual([r['allow_prediction'] for r in journal.records[0]['inputs']],[False,True,False])
        self.assertTrue(replay(FakeSession(),journal.records)['passed'])
        journal.records[0]['inputs'][0]['allow_prediction']=True
        with self.assertRaisesRegex(ValueError,'mask'):replay(FakeSession(),journal.records)

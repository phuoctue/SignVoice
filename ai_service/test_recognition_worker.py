from types import SimpleNamespace
import threading
import time
import unittest
import numpy as np
from .recognition_worker import RecognitionWorker


class WorkerTests(unittest.TestCase):
    def test_word_batch_does_not_lose_last_visible_hand_to_empty_tail(self):
        from .recognition_worker import prediction_index
        def batch(items):
            return [(np.full(126,p),np.zeros(8),t,np.zeros(4)) for t,p in items]
        self.assertEqual(prediction_index(batch([(1.,1),(1.1,1),(1.2,0)]),'words'),1)
        self.assertEqual(prediction_index(batch([(1.,1),(1.1,1),(1.2,0)]),'letters'),2)
        self.assertEqual(prediction_index(batch([(1.,1),(1.1,1),(1.2,0)]),'digits'),2)
        self.assertEqual(prediction_index(batch([(1.,1),(1.4,0)]),'words'),1)
        self.assertEqual(prediction_index(batch([(1.,0),(1.1,0)]),'words'),1)

    def test_real_worker_preserves_empty_tail_and_journals_its_prediction_mask(self):
        entered,release=threading.Event(),threading.Event()
        class Session:
            def __init__(self):
                self.recognizer=SimpleNamespace(mode='words',word_head=SimpleNamespace(last_diagnostics={}),domain_collision=lambda scores:None)
                self.events=[];self.decision=SimpleNamespace(smoothed=None);self.hold=SimpleNamespace(anchor=None)
                self.output=None;self.last_prediction=-np.inf;self.seen=[]
            def update(self,p,w,now,allow_prediction=True,context=None):
                if now==1.:entered.set();release.wait(1.)
                self.seen.append((now,allow_prediction))
                if allow_prediction and np.any(p):
                    self.last_prediction=now;self.decision.smoothed=np.array([.95])
                    self.output=(0,[0],.95,True,[1.],True);self.events.append(dict(label='word',time=now))
        session=Session();worker=RecognitionWorker(session);worker.enable_diagnostics()
        try:
            worker.submit(np.zeros(126),np.zeros(8),1.)
            self.assertTrue(entered.wait(1.))
            for now,p in [(2.,1),(2.1,1),(2.2,0)]:worker.submit(np.full(126,p),np.zeros(8),now)
            release.set();deadline=time.monotonic()+1.
            while time.monotonic()<deadline:
                _,details=worker.poll_with_details()
                if details.get('observation_timestamp_ms')==2200:break
                time.sleep(.005)
            self.assertEqual(session.seen,[(1.,True),(2.,False),(2.1,True),(2.2,False)])
            self.assertEqual(details['prediction_timestamp_ms'],2100)
            self.assertEqual(worker.poll()[4],{'label':'word','time':2.1})
            record=worker.drain_diagnostics()['records'][-1]
            self.assertEqual([x['allow_prediction'] for x in record['inputs']],[False,True,False])
        finally:release.set();worker.close()

    def test_preserves_observations_and_snapshots_prediction_evidence(self):
        entered, release = threading.Event(), threading.Event()
        class Recognizer:
            mode = 'words'
            word_head = SimpleNamespace(last_diagnostics={})
            def set_mode(self, mode): self.mode = mode
            def domain_collision(self, scores): return None
        class Session:
            def __init__(self):
                self.recognizer=Recognizer();self.events=[];self.decision=SimpleNamespace(smoothed=None)
                self.hold=SimpleNamespace(anchor=None);self.output=None;self.last_prediction=-np.inf;self.seen=[]
            def reset(self): pass
            def update(self,p,w,now,allow_prediction=True,context=None):
                if now==1:
                    entered.set();release.wait(1)
                self.seen.append((now,allow_prediction))
                if allow_prediction:
                    self.last_prediction=now;self.decision.smoothed=np.array([.9,.1])
                    self.output=('winner',)
                    self.recognizer.word_head.last_diagnostics={'inference_ran':True,'rejection_reasons':['score']}
        session=Session();worker=RecognitionWorker(session)
        try:
            worker.submit(np.zeros(126),np.zeros(8),1)
            self.assertTrue(entered.wait(1))
            worker.submit(np.zeros(126),np.zeros(8),2)
            worker.submit(np.ones(126),np.ones(8),3)
            release.set()
            deadline=time.monotonic()+1
            while time.monotonic()<deadline:
                snapshot,details=worker.poll_with_details()
                if details.get('prediction_timestamp_ms')==3000:break
                time.sleep(.005)
            self.assertEqual(session.seen,[(1,True),(2,False),(3,True)])
            self.assertEqual(snapshot[0],('winner',))
            self.assertEqual(details['word']['rejection_reasons'],['score'])
            self.assertEqual(details['observations'],2)
            self.assertEqual(details['observation_overruns'],0)
        finally:
            release.set();worker.close()

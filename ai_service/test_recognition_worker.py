from types import SimpleNamespace
import threading
import time
import unittest
import numpy as np
from .recognition_worker import RecognitionWorker


class WorkerTests(unittest.TestCase):
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

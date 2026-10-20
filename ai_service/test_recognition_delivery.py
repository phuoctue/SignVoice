"""Camera delivery must preserve the desktop's completed-sign semantics."""
import threading
import time
import unittest
from types import SimpleNamespace
import numpy as np
from .engine import VideoSession


class DeliveryTests(unittest.TestCase):
    def session(self, held=True, observed=4000):
        session=VideoSession.__new__(VideoSession)
        session.recognizer=SimpleNamespace(labels=['ô'])
        session.allowed={'ô'}
        session.worker=SimpleNamespace(poll_with_details=lambda: (
            ((0,.95,0.,True),np.array([.95]),held,None,{'label':'ô','time':1.}),
            {'prediction_timestamp_ms':1000,'observation_timestamp_ms':observed}))
        session.last_event_label=None;session.last_event_key=None
        session.event_index=0;session.last_observed=-1.
        from .session_trace import SessionTrace
        session.trace=SessionTrace(None,{})
        return session

    def test_completed_letter_stays_while_latest_pose_is_held(self):
        session=self.session()
        result=session._decision_fields(np.ones(126),[object()],4000)
        self.assertEqual(result['confirmed'],'ô')
        self.assertEqual(len(result['events']),1)
        self.assertEqual(session._decision_fields(np.ones(126),[object()],4000)['events'],[])

    def test_old_hold_cannot_confirm_an_unprocessed_or_missing_hand(self):
        for held,observed,pose in [(True,3000,np.ones(126)),(False,4000,np.ones(126)),
                                   (True,4000,np.zeros(126))]:
            session=self.session(held,observed)
            self.assertIsNone(session._decision_fields(pose,[],4000)['confirmed'])

    def test_completion_notifies_without_another_camera_frame(self):
        from .recognition_worker import RecognitionWorker
        done=threading.Event()
        class Session:
            recognizer=SimpleNamespace(mode='letters',word_head=None,domain_collision=lambda scores:None)
            events=[];decision=SimpleNamespace(smoothed=None)
            hold=SimpleNamespace(anchor=None);output=None;last_prediction=-np.inf
            def update(self,p,w,now,**kw):self.last_prediction=now
        worker=RecognitionWorker(Session())
        try:
            worker.on_update=done.set
            worker.submit(np.ones(126),np.ones(8),4.)
            self.assertTrue(done.wait(1))
            self.assertEqual(worker.poll_with_details()[1]['observation_timestamp_ms'],4000)
        finally:worker.close()

    def test_refresh_does_not_revive_stopped_camera_or_consume_queued_event(self):
        session=self.session(observed=3000)
        session.last_frame=(np.ones(126),[object()],4000,time.monotonic())
        session.last_result={'type':'result','sequence':7,'timestamp_ms':4000};session.publication=1
        self.assertIsNone(session.recognition_update())
        self.assertEqual(session.event_index,0)
        session.worker=self.session(observed=4000).worker
        result=session.recognition_update()
        self.assertEqual(result['confirmed'],'ô')
        self.assertEqual(result['publication'],2)
        self.assertEqual(result['sequence'],7)
        session.last_frame=(np.ones(126),[object()],4000,time.monotonic()-3.)
        self.assertIsNone(session.recognition_update())

    def test_websocket_pushes_completion_without_second_image(self):
        from unittest.mock import patch
        from fastapi.testclient import TestClient
        from .server import app
        class Session:
            worker=SimpleNamespace(on_update=None)
            timer=None
            def process(self,meta,frame):
                self.timer=threading.Timer(.03,lambda:self.worker.on_update())
                self.timer.start()
                return dict(type='result',sequence=0,publication=1,confirmed=None)
            def recognition_update(self):
                return dict(type='result',sequence=0,publication=2,confirmed='ă')
            def close(self):
                if self.timer:self.timer.join(1)
        session=Session()
        engine=SimpleNamespace(info=lambda:{'ready':True},session=lambda *a:session)
        with patch('ai_service.engine.Engine',return_value=engine),patch(
                'ai_service.model_selection.resolve_selection',return_value={'model_dir':'unused'}),patch(
                'ai_service.server.read_header',return_value=({'timestamp_ms':1000,'sequence':0},None)),patch(
                'ai_service.server.decode_frame',return_value=({},None)):
            with TestClient(app) as client:
                with client.websocket_connect('/v1/stream') as socket:
                    socket.send_json({'mode':'letters'})
                    self.assertEqual(socket.receive_json()['type'],'ready')
                    socket.send_bytes(b'one image only')
                    results=[]
                    while len(results)<2:
                        message=socket.receive_json()
                        if message['type']=='result':results.append(message)
                    self.assertIsNone(results[0]['confirmed'])
                    self.assertEqual(results[1]['confirmed'],'ă')

    def test_trace_attaches_delayed_result_without_duplicating_landmarks(self):
        from .session_trace import SessionTrace
        trace=SessionTrace('unused',{})
        frame=dict(sequence=1,timestamp_ms=4000,confirmed=None,events=[])
        trace.add(np.ones(126),np.ones(8),np.zeros(4),frame)
        trace.update_result({**frame,'confirmed':'ô','events':[{'id':1,'label':'ô'}]})
        trace.update_result({**frame,'confirmed':'ô'})
        self.assertEqual(len(trace.frames),1)
        self.assertEqual(trace.total,1)
        self.assertEqual(trace.frames[0][3]['confirmed'],'ô')
        self.assertEqual(trace.frames[0][3]['events'],[{'id':1,'label':'ô'}])

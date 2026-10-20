import copy
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import numpy as np
from .protocol import read_live_observation
from . import test_gpu_fast_path


class LiveObservationTests(unittest.TestCase):
    def test_words_websocket_accepts_dense_points_before_next_jpeg(self):
        from fastapi.testclient import TestClient
        from .server import app
        from unittest.mock import Mock
        engine=Mock();engine.info.return_value={'ready':True,'hand_model_sha256':'hash'}
        engine.session.return_value.observe.return_value=None
        with patch('ai_service.engine.Engine',return_value=engine),patch(
                'ai_service.model_selection.resolve_selection',return_value={'model_dir':'unused'}):
            with TestClient(app) as client:
                with client.websocket_connect('/v1/stream') as socket:
                    socket.send_json({'mode':'words'})
                    self.assertEqual(socket.receive_json()['type'],'ready')
                    socket.send_json(self.message())
                    self.assertEqual(socket.receive_json()['type'],'observation_received')
            engine.session.return_value.observe.assert_called_once()

    def test_websocket_accepts_xyz_before_any_jpeg(self):
        from fastapi.testclient import TestClient
        from .server import app
        from unittest.mock import Mock
        engine=Mock();engine.info.return_value={'ready':True,'hand_model_sha256':'hash'}
        engine.session.return_value.observe.return_value=None
        with patch('ai_service.engine.Engine',return_value=engine),patch(
                'ai_service.model_selection.resolve_selection',return_value={'model_dir':'unused'}):
            with TestClient(app) as client:
                with client.websocket_connect('/v1/stream') as socket:
                    socket.send_json({'mode':'letters'})
                    self.assertEqual(socket.receive_json()['type'],'ready')
                    socket.send_json(self.message())
                    self.assertEqual(socket.receive_json(),{'type':'observation_received','timestamp_ms':2000})
            engine.session.return_value.process.assert_not_called()
            engine.session.return_value.observe.assert_called_once()

    def message(self,stamp=2000):
        return dict(type='hand_observation',observation=dict(schema='mediapipe_hand_3d_v1',
            sdk='0.10.32',model_sha256='hash',width=32,height=24,timestamp_ms=stamp,
            landmarks=[],handedness=[]))

    def test_rejects_wrong_model_dimensions_and_nonfinite_xyz(self):
        self.assertEqual(read_live_observation(self.message(),'hash')['timestamp_ms'],2000)
        for changes in [dict(model_sha256='other'),dict(timestamp_ms=float('nan')),
                        dict(width=4000),dict(sdk='unknown')]:
            message=copy.deepcopy(self.message());message['observation'].update(changes)
            with self.assertRaises(ValueError):read_live_observation(message,'hash')

    def test_live_features_reach_worker_without_pixels_and_older_jpeg_cannot_reorder_them(self):
        v=test_gpu_fast_path.GpuFastPathTests().session();v.mode='letters'
        v.last_frame=None;v.last_result=None;v.publication=0
        v.last_observation_timestamp=-1
        seen=[]
        def features(found,*args,now,tracker=None,**kw):
            if tracker is v.tracker:seen.append(now)
            return np.ones(126),np.ones(8),[]
        v.tracker=object();v.engine.runtime.features_from_result=features
        self.assertEqual(v.observe(read_live_observation(self.message(),'hash'))['landmark_source'],'live_xyz')
        self.assertEqual(v.worker.submit.call_count,1)
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            v.process(dict(sequence=0,timestamp_ms=1000),np.zeros((24,32,3),np.uint8))
        self.assertEqual(v.worker.submit.call_count,1)
        self.assertEqual(v.last_frame[2],2000)
        self.assertEqual(seen,[2.])
        v.observe(read_live_observation(self.message(2100),'hash'))
        self.assertEqual(v.worker.submit.call_count,2)
        self.assertEqual(v.last_result['timestamp_ms'],2100)
        self.assertNotIn('foreground_context',v.last_result)
        self.assertIsNone(v.observe(read_live_observation(self.message(2050),'hash')))

    def test_word_observations_use_bounded_server_face_measurement(self):
        v=test_gpu_fast_path.GpuFastPathTests().session();v.mode='words'
        v.context.snapshot.return_value=(np.array([.4,.3,.2,1.],np.float32),1.7)
        v.context_aspect=32/24
        v.observe(read_live_observation(self.message(2000),'hash'))
        np.testing.assert_array_equal(v.worker.submit.call_args.args[3],np.array([.4,.3,.2,1.],np.float32))
        self.assertAlmostEqual(v.last_result['context_age_ms'],300.)
        v.context.snapshot.return_value=(np.zeros(4,np.float32),None)
        v.observe(read_live_observation(self.message(3300),'hash'))
        self.assertFalse(np.any(v.worker.submit.call_args.args[3]))
        self.assertIsNone(v.last_result['context_age_ms'])

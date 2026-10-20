"""Camera regressions independent of model weights and a physical webcam."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
import numpy as np
from .realtime_detector import ResilientHandLandmarker


class CameraModelTests(unittest.TestCase):
    def test_old_client_cannot_reenable_lm_review(self):
        from fastapi.testclient import TestClient
        from .server import app
        engine = Mock()
        engine.info.return_value = {'ready': True}
        with patch('ai_service.engine.Engine',return_value=engine), patch(
                'ai_service.model_selection.resolve_selection',return_value={'model_dir':'unused'}):
            with TestClient(app) as client:
                with client.websocket_connect('/v1/stream') as socket:
                    socket.send_json({'mode':'all','vision':True})
                    self.assertEqual(socket.receive_json()['type'],'ready')
            engine.session.assert_called_once_with('all',False)


class RecoveryBudgetTests(unittest.TestCase):
    def test_failed_recovery_does_not_run_on_every_slow_camera_frame(self):
        empty = SimpleNamespace(hand_landmarks=[], handedness=[], hand_world_landmarks=[])
        image = SimpleNamespace(numpy_view=lambda: np.zeros((48,64,3),np.uint8))
        detector = ResilientHandLandmarker('unused')
        detector.realtime_budget = True
        detector.search_regions = False
        detector.fallback = Mock()
        detector.fallback.detect.return_value = empty
        # A 300 ms primary inference previously caused a second full inference
        # every frame: 333 ms already exceeded the fixed 200 ms retry interval.
        for stamp in range(0,2000,333):
            detector._retry(image,empty,stamp)
        self.assertLessEqual(detector.fallback.detect.call_count,3)

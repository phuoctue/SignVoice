import unittest
from types import SimpleNamespace
import numpy as np
from .protocol import browser_hand_result
from .model_runtime import features_from_result, HandSlotTracker, foreground_hand_result


class BrowserLandmarkTests(unittest.TestCase):
    def test_foreground_filter_preserves_two_hands_spread_beside_face(self):
        meta=self.packet()
        points=meta['hand_observation']['landmarks'][0]
        meta['hand_observation']['landmarks'].append([[x+.52,y,z] for x,y,z in points])
        meta['hand_observation']['handedness'].append('Right')
        result=browser_hand_result(meta,'a'*64)
        filtered=foreground_hand_result(result,640,480,[.5,.2,.1,1])
        self.assertEqual(len(filtered.hand_landmarks),2)

    def test_folded_hand_survives_without_face_context(self):
        meta=self.packet()
        meta['hand_observation']['landmarks'][0]=[[.3+(x-.3)*.6,.4+(y-.4)*.6,z*.6]
            for x,y,z in meta['hand_observation']['landmarks'][0]]
        result=browser_hand_result(meta,'a'*64)
        filtered=foreground_hand_result(result,640,480,[0,0,0,0])
        self.assertEqual(len(filtered.hand_landmarks),1)

    def packet(self):
        points=[[.3+i*.002,.4+i*.003,-i*.001] for i in range(21)]
        return dict(width=640,height=480,timestamp_ms=125,
            hand_observation=dict(schema='mediapipe_hand_3d_v1',sdk='0.10.32',
                model_sha256='a'*64,timestamp_ms=125,width=640,height=480,
                landmarks=[points],handedness=['Left']))

    def test_browser_and_python_points_have_identical_feature_contract(self):
        meta=self.packet(); result=browser_hand_result(meta,'a'*64)
        native=SimpleNamespace(hand_landmarks=[[SimpleNamespace(x=x,y=y,z=z)
            for x,y,z in meta['hand_observation']['landmarks'][0]]],
            handedness=[[SimpleNamespace(category_name='Left')]],hand_world_landmarks=[])
        for a,b in zip(features_from_result(result,640,480,tracker=HandSlotTracker(),keep_both_hands=True)[:2],
                       features_from_result(native,640,480,tracker=HandSlotTracker(),keep_both_hands=True)[:2]):
            np.testing.assert_array_equal(a,b)

    def test_absent_or_different_model_uses_cpu_fallback(self):
        self.assertIsNone(browser_hand_result({},'a'*64))
        self.assertIsNone(browser_hand_result(self.packet(),'b'*64))

    def test_empty_detection_is_valid_not_a_missing_packet(self):
        meta=self.packet();meta['hand_observation'].update(landmarks=[],handedness=[])
        self.assertEqual(browser_hand_result(meta,'a'*64).hand_landmarks,[])

    def test_rejects_misaligned_nonfinite_or_incomplete_points(self):
        for change in ({'timestamp_ms':124},{'width':320},{'landmarks':[[[0,0,0]]]},
                       {'handedness':['unknown']},{'landmarks':[[[0,float('nan'),0]]*21]}):
            with self.subTest(change=change):
                meta=self.packet();meta['hand_observation'].update(change)
                with self.assertRaises(ValueError):browser_hand_result(meta,'a'*64)

    def test_android_upright_packet_uses_identical_feature_contract(self):
        meta=self.packet();meta['rotation']=0
        meta['hand_observation'].update(platform='android',delegate='gpu')
        result=browser_hand_result(meta,'a'*64)
        self.assertEqual(len(result.hand_landmarks[0]),21)
        meta['rotation']=90
        with self.assertRaises(ValueError):browser_hand_result(meta,'a'*64)

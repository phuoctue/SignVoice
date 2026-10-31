import copy
import unittest

import numpy as np

from .hand_transforms import mirror_observation, mirror_aligned_sequence
from .protocol import browser_hand_result
from . import model_runtime as runtime


class MirrorObservationTests(unittest.TestCase):
    def fixture(self):
        return dict(schema='mediapipe_hand_3d_v1',sdk='0.10.32',model_sha256='hash',
                    timestamp_ms=125,width=640,height=480,
                    landmarks=[[[.2+i*.007,.3+i*.008,-i*.002] for i in range(21)]],
                    handedness=['Left'])

    def test_mirrors_all_coordinates_handedness_and_valid_face_without_mutating_input(self):
        obs=self.fixture();before=copy.deepcopy(obs);face=[.4,.2,.18,1.]
        mirrored,anchor=mirror_observation(obs,face)
        self.assertEqual(obs,before)
        self.assertEqual(face,[.4,.2,.18,1.])
        np.testing.assert_allclose(np.asarray(mirrored['landmarks'])[...,0],1-np.asarray(obs['landmarks'])[...,0])
        np.testing.assert_array_equal(np.asarray(mirrored['landmarks'])[...,1:],np.asarray(obs['landmarks'])[...,1:])
        self.assertEqual(mirrored['handedness'],['Right'])
        self.assertEqual(anchor,[.6,.2,.18,1.])
        restored,restored_anchor=mirror_observation(mirrored,anchor)
        np.testing.assert_allclose(restored['landmarks'],obs['landmarks'],atol=1e-15)
        self.assertEqual(restored_anchor,face)
        self.assertEqual(restored['timestamp_ms'],125)

    def test_normalized_single_hand_shape_and_presence_remain_consistent(self):
        obs=self.fixture();mirrored,face=mirror_observation(obs,[0,0,0,0])
        self.assertEqual(face,[0,0,0,0])
        features=[]
        for data in (obs,mirrored):
            packet=dict(width=640,height=480,timestamp_ms=125,hand_observation=data)
            result=browser_hand_result(packet,'hash')
            features.append(runtime.features_from_result(result,640,480,False,allow_low_hands=True,keep_both_hands=True)[0])
        np.testing.assert_allclose(features[0],features[1],atol=2e-6)

    def test_two_hands_keep_slots_order_and_mirror_categories_not_swap_observations(self):
        obs=self.fixture();obs['landmarks'].append([[.8,.5,0.]]*21);obs['handedness'].append('Right')
        mirrored,_=mirror_observation(obs,[0,0,0,0])
        self.assertEqual(mirrored['handedness'],['Right','Left'])
        self.assertAlmostEqual(mirrored['landmarks'][0][0][0],.8)
        self.assertAlmostEqual(mirrored['landmarks'][1][0][0],.2)

    def test_empty_and_malformed_observations(self):
        obs=self.fixture();obs.update(landmarks=[],handedness=[])
        self.assertEqual(mirror_observation(obs,[0,0,0,0])[0],obs)
        for change in (dict(handedness=['Unknown']),dict(landmarks=[[[float('nan'),0,0]]*21]),dict(handedness=[])):
            data=self.fixture();data.update(change)
            with self.assertRaises(ValueError):mirror_observation(data,[0,0,0,0])

    def test_aligned_sequence_matches_raw_mirror_and_preserves_gaps_and_clock(self):
        features=[]
        for obs in [self.fixture(),mirror_observation(self.fixture(),[.4,.2,.18,1.])[0]]:
            result=browser_hand_result(dict(width=640,height=480,timestamp_ms=125,hand_observation=obs),'hash')
            features.append(runtime.features_from_result(result,640,480,False,allow_low_hands=True,keep_both_hands=True)[:2])
        p=np.stack([features[0][0],np.zeros(126),features[0][0]]).astype(np.float32)
        w=np.stack([features[0][1],np.zeros(8),features[0][1]]).astype(np.float32)
        c=np.array([[.4,.2,.18,1.],[0,0,0,0],[.4,.2,.18,1.]],np.float32);t=np.array([1.,1.1,1.4])
        pp,ww,cc,tt=mirror_aligned_sequence(p,w,c,t)
        np.testing.assert_allclose(pp[0],features[1][0],atol=2e-6)
        np.testing.assert_allclose(ww[0],features[1][1],atol=2e-6)
        np.testing.assert_array_equal(pp[1],0);np.testing.assert_array_equal(ww[1],0)
        np.testing.assert_array_equal(tt,t);self.assertAlmostEqual(float(cc[0,0]),.6,places=6)
        restored=mirror_aligned_sequence(pp,ww,cc,tt)
        for actual,expected in zip(restored,(p,w,c,t)):np.testing.assert_allclose(actual,expected,atol=2e-6)


if __name__=='__main__':unittest.main()

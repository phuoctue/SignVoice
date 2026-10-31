import base64
import copy
import unittest

import cv2
import numpy as np

from . import model_runtime as runtime
from .check_camera_input import decode_snapshot, feature_replay, match_hands
from .protocol import browser_hand_result


def observation(stamp=100, x=.3, category='Right'):
    return dict(schema='mediapipe_hand_3d_v1', sdk='0.10.32', model_sha256='testhash',
        width=640,height=480,timestamp_ms=stamp,handedness=[category],
        landmarks=[[[x+i*.005,.4+i*.007,-i*.001] for i in range(21)]])


class CameraInputTests(unittest.TestCase):
    def test_current_observation_send_log_replays_without_renaming_message_kind(self):
        capture,config=self.fixture()
        for row in capture['messages']:
            if row.get('kind')=='sent_observation':row['kind']='observation_send'
        report=feature_replay(capture,config)
        self.assertTrue(report['comparable'])
        self.assertTrue(report['passed'])
        self.assertEqual(report['checked'],4)

    def test_png_rejects_mismatched_timestamp_dimensions_and_preview_mirroring(self):
        _,png=cv2.imencode('.png',np.zeros((480,640,3),np.uint8))
        row=dict(format='png',width=640,height=480,timestamp_ms=100,rotation=0,
            mirrored=False,pixel_stage='resized_detector_input',hand_observation=observation(),
            png_base64=base64.b64encode(png).decode())
        image, digest=decode_snapshot(row)
        self.assertEqual(image.shape,(480,640,3));self.assertEqual(len(digest),64)
        for patch in (dict(timestamp_ms=101),dict(width=480),dict(mirrored=True),dict(png_base64='invalid')):
            with self.assertRaises(ValueError): decode_snapshot({**row,**patch})

    def test_matching_two_hands_ignores_detector_order(self):
        hands=observation()['landmarks']+observation(x=.6)['landmarks']
        result=match_hands(hands,hands[::-1],.75)
        self.assertEqual([(p['first'],p['second']) for p in result['pairs']],[(0,1),(1,0)])
        self.assertEqual(sum(p['median_xyz_width_units'] for p in result['pairs']),0.)
        self.assertEqual(match_hands([],hands,.75)['matched'],0)

    def fixture(self):
        config=dict(sha256={'hand_landmarker.task':'testhash'},feature_pipeline=runtime.EXTRACTOR_VERSION)
        tracker=runtime.HandSlotTracker(); messages=[];records=[]
        # One hand then two, reverse detector order and handedness flicker.
        for i in range(4):
            obs=observation(100+i*100)
            if i:
                obs['landmarks']+=observation(x=.6)['landmarks'];obs['handedness']+=['Left']
                if i%2:obs['landmarks'].reverse();obs['handedness'].reverse()
            messages.append(dict(kind='sent_observation',observation=obs))
            meta=dict(width=640,height=480,timestamp_ms=obs['timestamp_ms'],rotation=0,hand_observation=obs)
            found=browser_hand_result(meta,'testhash')
            found=runtime.foreground_hand_result(found,640,480,[.5,.3,.1,1])
            now=obs['timestamp_ms']/1000
            pose,wrist,_=runtime.features_from_result(found,640,480,False,allow_low_hands=True,
                tracker=tracker,now=now,keep_both_hands=True)
            records.append(dict(generation=1,inputs=[dict(time=now,pose=pose.tolist(),wrist=wrist.tolist(),context=[.5,.3,.1,1])]))
        messages.append(dict(worker_diagnostic=dict(records=records)))
        return dict(messages=messages),config

    def test_replay_checks_slots_and_canonicalization_and_catches_corruption(self):
        capture,config=self.fixture()
        report=feature_replay(capture,config)
        self.assertTrue(report['passed']);self.assertEqual(report['checked'],4)
        capture['messages'][-1]['worker_diagnostic']['records'][2]['inputs'][0]['wrist'][0]+=.1
        self.assertFalse(feature_replay(capture,config)['passed'])

    def test_missing_observations_and_overruns_cannot_claim_parity(self):
        capture,config=self.fixture()
        missing=copy.deepcopy(capture);missing['messages'].pop(0)
        self.assertFalse(feature_replay(missing,config)['comparable'])
        capture['messages'][-1]['worker_diagnostic']['records'][0]['observation_overruns']=1
        self.assertIsNone(feature_replay(capture,config)['passed'])

    def test_conflicting_capture_stamp_rejected(self):
        capture,config=self.fixture()
        capture['messages'].insert(0,dict(kind='sent_observation',observation=observation(x=.8)))
        with self.assertRaisesRegex(ValueError,'Conflicting'):feature_replay(capture,config)


if __name__=='__main__':unittest.main()

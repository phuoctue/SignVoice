import unittest
from types import SimpleNamespace
from unittest.mock import Mock,patch
from collections import deque
import numpy as np
from .engine import VideoSession
from .session_trace import SessionTrace

class GpuFastPathTests(unittest.TestCase):
    def session(self):
        v=VideoSession.__new__(VideoSession)
        runtime=SimpleNamespace(foreground_hand_result=lambda found,*a:found,
            features_from_result=lambda *a,**kw:(np.zeros(126),np.zeros(8),[]),TRACKED_PIPELINES={'tracked'})
        v.engine=SimpleNamespace(runtime=runtime)
        v.recognizer=SimpleNamespace(config={'sha256':{'hand_landmarker.task':'hash'},'feature_pipeline':'tracked'},labels=[])
        v.mp=SimpleNamespace(Image=lambda **kw:kw,ImageFormat=SimpleNamespace(SRGB=1))
        v.context=Mock();v.context.update.return_value=np.zeros(4)
        v.detector=Mock();v.detector.last_timing={};v.opencv=Mock();v.opencv.analyze.return_value={}
        v.worker=Mock();v.worker.poll_with_details.return_value=((None,None,None,None,None),{})
        v.last_timestamp=-1;v.last_sequence=-1;v.frame_times=deque(maxlen=24);v.tracker=None
        v.mode='words';v.allowed=frozenset();v.last_event_label=None;v.last_event_key=None;v.last_observed=-1;v.event_index=0
        v.last_observation_timestamp=-1.
        v.last_frame=None;v.last_result=None;v.publication=0
        v.trace=SessionTrace(None,{})
        return v
    def test_current_gpu_observation_avoids_duplicate_cpu_flow(self):
        v=self.session()
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            out=v.process({'timestamp_ms':100,'sequence':1},np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['landmark_source'],'browser_gpu')
        v.detector.motion.begin.assert_not_called();v.detector.motion.observe.assert_not_called()
        v.detector.detect_for_video.assert_not_called()
        self.assertIsNone(v.opencv.analyze.call_args.args[2])
    def test_cpu_fallback_retains_detector_and_flow_for_recovery(self):
        v=self.session()
        with patch('ai_service.engine.browser_hand_result',return_value=None):
            out=v.process({'timestamp_ms':100,'sequence':1},np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['landmark_source'],'cpu');v.detector.detect_for_video.assert_called_once()
        self.assertIs(v.opencv.analyze.call_args.args[2],v.detector.motion)

    def test_android_local_gpu_also_avoids_duplicate_detector(self):
        v=self.session()
        meta={'timestamp_ms':100,'sequence':1,'hand_observation':{'platform':'android','delegate':'gpu'}}
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['landmark_source'],'android_gpu')
        v.detector.detect_for_video.assert_not_called()

    def test_browser_local_cpu_skips_second_server_cpu_detection(self):
        v=self.session()
        meta={'timestamp_ms':100,'sequence':1,'hand_observation':{'platform':'web','delegate':'cpu'}}
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['landmark_source'],'browser_cpu')
        v.detector.detect_for_video.assert_not_called()

    def test_client_startup_diagnostics_are_bounded_and_separate_from_server_fps(self):
        v=self.session()
        meta={'timestamp_ms':100,'sequence':1,'hand_observation':{
            'init_ms':7300,'processing_ms':float('nan'),'fps':24,'recovery_enabled':False}}
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['client_detector'],{'init_ms':7300.,'fps':24.,'recovery_enabled':False})

    def test_cpu_fallback_reports_the_actual_failed_startup_stage(self):
        v=self.session()
        meta={'timestamp_ms':100,'sequence':1,'client_detector_startup':{
            'phase':'fallback','failed_phase':'primary_detector','reason':'detector_timeout','elapsed_ms':30000}}
        with patch('ai_service.engine.browser_hand_result',return_value=None):
            out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['client_detector']['startup']['failed_phase'],'primary_detector')
        self.assertEqual(out['client_detector']['startup']['elapsed_ms'],30000.)

    def test_resource_download_and_detector_startup_are_reported_separately(self):
        v=self.session()
        meta={'timestamp_ms':100,'sequence':1,'hand_observation':{
            'asset_load_ms':3400,'detector_init_ms':500,'raw_hands':2,'rejected_hands':0}}
        with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
            out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(out['client_detector'],{'asset_load_ms':3400.,'detector_init_ms':500.,'raw_hands':2.,'rejected_hands':0.})

    def test_letter_history_reaches_sequence_worker_once_in_capture_order(self):
        v=self.session();v.mode='letters';seen=[]
        def features(found,*args,now,**kwargs):
            seen.append(now);return np.ones(126),np.zeros(8),found.hand_landmarks
        v.engine.runtime.features_from_result=features
        observation=dict(schema='mediapipe_hand_3d_v1',sdk='0.10.32',model_sha256='hash',
                         width=32,height=24,timestamp_ms=1000,landmarks=[],handedness=[])
        rows=[dict(timestamp_ms=t,landmarks=[],handedness=[]) for t in (400,467,534,601,668,735)]
        meta=dict(timestamp_ms=1000,sequence=1,width=32,height=24,hand_observation=observation,hand_history=rows)
        out=v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(seen,[.4,.467,.534,.601,.668,.735,1.])
        self.assertEqual(out['client_detector']['history_observations'],6)
        meta['timestamp_ms']=1100;meta['sequence']=2;observation['timestamp_ms']=1100
        v.process(meta,np.zeros((24,32,3),np.uint8))
        self.assertEqual(seen,[.4,.467,.534,.601,.668,.735,1.,1.1])

    def test_a_new_verified_completion_can_emit_the_same_letter_again(self):
        v=self.session();v.recognizer.labels=['ă'];v.allowed={'ă'}
        v.engine.runtime.features_from_result=lambda *a,**kw:(np.ones(126),np.zeros(8),[[]])
        def process(stamp,completed):
            output=(0,np.array([0]),1.,True,None,True)
            v.worker.poll_with_details.return_value=((output,np.array([.9]),False,None,
                {'time':completed,'label':'ă'}),{'prediction_timestamp_ms':stamp})
            with patch('ai_service.engine.browser_hand_result',return_value=SimpleNamespace(hand_landmarks=[])):
                return v.process({'timestamp_ms':stamp,'sequence':stamp},np.zeros((24,32,3),np.uint8))
        self.assertEqual([e['id'] for e in process(1000,1.)['events']],[1])
        self.assertEqual(process(1100,1.)['events'],[])
        self.assertEqual([e['id'] for e in process(2000,2.)['events']],[2])

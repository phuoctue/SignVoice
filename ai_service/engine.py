import copy
import importlib.util
import hashlib
import os
import threading
import time
from collections import deque
from pathlib import Path
import cv2
import numpy as np
from .opencv_camera import OpenCVCameraAnalysis
from .realtime_detector import ResilientHandLandmarker
from .recognition_worker import RecognitionWorker
from .protocol import browser_hand_result, browser_hand_history
from .ensemble import load_ensemble, embedded_ensemble
from .session_trace import SessionTrace

class Engine:
    def __init__(self,model_dir):
        import tensorflow as tf
        # Small sequence models should not monopolize the CPU cores needed by
        # MediaPipe and OpenCV. Set this before TensorFlow creates its pools.
        self.compute_threads=int(os.getenv('AI_TF_THREADS','1'))
        if not 1<=self.compute_threads<=16:raise ValueError('AI_TF_THREADS must be 1..16')
        tf.config.threading.set_intra_op_parallelism_threads(self.compute_threads)
        tf.config.threading.set_inter_op_parallelism_threads(1)
        cv2.setNumThreads(1)
        self.adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        self.folder=Path(model_dir).resolve()
        self.manifest_sha256=hashlib.sha256((self.folder/'recognizer_config.json').read_bytes()).hexdigest()
        self.runtime_sha256=hashlib.sha256(Path(__file__).with_name('model_runtime.py').read_bytes()).hexdigest()
        spec=importlib.util.spec_from_file_location('signvoice_pinned_runtime',Path(__file__).with_name('model_runtime.py'))
        self.runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.runtime)
        self.base,self.legacy=self.runtime.load_bundle(self.folder)
        if self.legacy or self.base.word_head is None:raise ValueError('A complete Colab word model bundle is required')
        hashes={name:self.base.config['sha256'][name] for name in ('embedding_model_v2.keras','word_temporal.keras')}
        self.ensemble=load_ensemble(Path(__file__).resolve().parents[1]/'.runtime/word-ensemble.json',
            self.manifest_sha256,hashes,self.base.word_head.names)
        if self.ensemble is None:
            self.ensemble=embedded_ensemble(self.base.word_head.config,hashes)
        if self.ensemble is not None:
            head=self.base.word_head
            head.policy.update(self.ensemble.policy['decision_policy'])
            head.config={**head.config,'policy':dict(head.policy),'deployment_engine':'probability_ensemble'}
            head.probability_fusion=self.ensemble
        self.model_lock=threading.Lock()
        cv2.setNumThreads(1)
    def info(self):
        return dict(ready=True,word_classes=len(self.base.word_head.names),feature_pipeline=self.base.config.get('feature_pipeline'),
            runtime_source='colab_export_with_service_adapter',modes=['words','letters','digits','all'],lm_role='punctuation_only',confidence_calibrated=False,
            stream_protocol=2,detector='on_device_or_service_cpu',
            live_glyph_observations=True,
            live_word_observations=True,
            hand_model_sha256=self.base.config['sha256']['hand_landmarker.task'],
            model_manifest_sha256=self.manifest_sha256,word_model_sha256=self.base.config['sha256']['word_temporal.keras'],
            runtime_sha256=self.runtime_sha256,word_engine=self.base.word_head.config.get('deployment_engine','tcn'),
            word_policy=self.base.word_head.policy,
            ensemble_calibration=None if self.ensemble is None else self.ensemble.policy['calibration'],
            tf_threads=self.compute_threads,camera_runtime='camera_ensemble_v8',camera_adapter_sha256=self.adapter_sha256,
            regression_trace_enabled=bool(os.getenv('AI_TRACE_DIR')),
            opencv=dict(enabled=True,version=cv2.__version__,features=['pixel_conversion','rotation','resize','lk_hand_recovery','hand_roi_hull','lighting_blur_advice']))
    def session(self,mode,vision=False):return VideoSession(self,mode,vision)

class VideoSession:
    def __init__(self,engine,mode,vision=False):
        import mediapipe as mp
        self.mp=mp;self.engine=engine;r=engine.runtime
        self.recognizer=copy.copy(engine.base)
        head=engine.base.word_head
        self.recognizer.word_head=r.TemporalWordHead(list(head.labels),copy.deepcopy(head.config),head.infer,
            embed=head.embed,centers=head.centers,mean=head.mean,std=head.std,probability_fusion=head.probability_fusion)
        self.recognizer.set_mode(mode)
        self.session=r.LiveSession(self.recognizer,False)
        self.tracker=r.HandSlotTracker()
        self.context=r.SigningContextWorker(engine.folder/'face_detector.tflite')
        self.opencv=OpenCVCameraAnalysis()
        self.detector=ResilientHandLandmarker(engine.folder/'hand_landmarker.task',video=True,opencv_assist=True).__enter__()
        self.detector.realtime_budget=True
        self.detector.target_hands=2 if mode in ('words','all') else 1
        self.detector.search_regions=mode in ('words','all')
        self.last_timestamp=-1.;self.last_sequence=-1;self.event_index=0
        self.worker=RecognitionWorker(self.session)
        self.worker.reset(mode)
        self.mode=mode;self.allowed=frozenset(name for i,name in enumerate(self.recognizer.labels) if self.recognizer.active[i])
        self.trace=SessionTrace(os.getenv('AI_TRACE_DIR'),dict(mode=mode,
            manifest_sha256=engine.manifest_sha256,runtime_sha256=engine.runtime_sha256,
            word_policy=dict(self.recognizer.word_head.policy),feature_pipeline=self.recognizer.config.get('feature_pipeline')))
        self.last_event_label=None;self.last_event_key=None;self.last_observed=-1.
        self.last_observation_timestamp=-1.
        self.frame_times=deque(maxlen=24)
        self.last_frame=None;self.last_result=None;self.publication=0
        self.context_aspect=None
    def process(self,meta,frame):
        r=self.engine.runtime
        stamp=float(meta['timestamp_ms'])
        if stamp<=self.last_timestamp or int(meta['sequence'])<=self.last_sequence:raise ValueError('Frame timestamps and sequences must strictly increase')
        self.last_timestamp=stamp;self.last_sequence=int(meta['sequence'])
        now=stamp/1000.;started=time.perf_counter()
        self.frame_times.append(started)
        if frame.shape[1]>640:
            scale=640/frame.shape[1];frame=cv2.resize(frame,(640,round(frame.shape[0]*scale)))
        anchor=self.context.update(frame,now)
        self.context_aspect=frame.shape[1]/frame.shape[0]
        context_done=time.perf_counter()
        found=browser_hand_result(meta,self.recognizer.config['sha256']['hand_landmarker.task'])
        browser_observed=found is not None
        if browser_observed:
            # Current-frame GPU landmarks already exist. Running forward/backward
            # LK and corner detection again adds CPU work without another joint
            # measurement. OpenCV quality/hulls still run below; LK remains in
            # the CPU detector's recovery path when browser observations stop.
            camera_motion=None
        else:
            rgb=cv2.cvtColor(frame,cv2.COLOR_BGR2RGB)
            found=self.detector.detect_for_video(self.mp.Image(image_format=self.mp.ImageFormat.SRGB,data=rgb),int(stamp))
            camera_motion=self.detector.motion
        h,w=frame.shape[:2]
        history=browser_hand_history(meta,self.recognizer.config['sha256']['hand_landmarker.task']) if browser_observed and self.mode in ('letters','digits') else []
        history_count=0
        for historical_stamp,historical_found in history:
            if historical_stamp<=self.last_observation_timestamp or historical_stamp>=stamp:continue
            historical_found=r.foreground_hand_result(historical_found,w,h,None)
            hp,hw,hh=r.features_from_result(historical_found,w,h,False,allow_low_hands=True,
                tracker=self.tracker,now=historical_stamp/1000.,
                keep_both_hands=self.recognizer.config.get('feature_pipeline') in r.TRACKED_PIPELINES)
            # No historical pixels/face measurement exists. Keep context masked;
            # letter/digit temporal matching uses measured hand pose and wrist.
            hc=np.zeros(4,np.float32)
            self.worker.submit(hp,hw,historical_stamp/1000.,hc)
            self.last_observation_timestamp=historical_stamp;history_count+=1
            self.trace.add(hp,hw,hc,dict(sequence=meta['sequence'],timestamp_ms=historical_stamp,
                landmark_source='browser_history',hands=len(hh)))
        found=r.foreground_hand_result(found,w,h,anchor)
        detector_done=time.perf_counter()
        current_observation=stamp>self.last_observation_timestamp
        pose,wrist,hands=r.features_from_result(found,w,h,False,allow_low_hands=True,
            tracker=self.tracker if current_observation else None,now=now,
            keep_both_hands=self.recognizer.config.get('feature_pipeline') in r.TRACKED_PIPELINES)
        opencv=self.opencv.analyze(frame,hands,camera_motion,now)
        if current_observation:
            self.worker.submit(pose,wrist,now,anchor)
            self.last_observation_timestamp=stamp
            self.last_frame=(pose.copy(),hands,stamp,time.monotonic())
        dp,dh,ds,_=self.last_frame
        decision=self._decision_fields(dp,dh,ds)
        elapsed_ms=round((time.perf_counter()-started)*1000,1)
        fps=(len(self.frame_times)-1)/(self.frame_times[-1]-self.frame_times[0]) if len(self.frame_times)>1 else 0.
        client_detector={}
        if 'hand_history' in meta:client_detector['history_observations']=history_count
        if browser_observed:
            observation=meta.get('hand_observation',{})
            for key in ('init_ms','asset_load_ms','detector_init_ms','processing_ms','fps','raw_hands','rejected_hands'):
                value=observation.get(key)
                if isinstance(value,(int,float)) and not isinstance(value,bool) and np.isfinite(value) and 0<=value<=300000:
                    client_detector[key]=float(value)
            if isinstance(observation.get('recovery_enabled'),bool):
                client_detector['recovery_enabled']=observation['recovery_enabled']
        startup=meta.get('client_detector_startup')
        if not browser_observed and isinstance(startup,dict):
            diagnostic={}
            for key in ('phase','failed_phase','reason'):
                if isinstance(startup.get(key),str):diagnostic[key]=startup[key][:240]
            elapsed=startup.get('elapsed_ms')
            if isinstance(elapsed,(int,float)) and not isinstance(elapsed,bool) and np.isfinite(elapsed) and 0<=elapsed<=300000:
                diagnostic['elapsed_ms']=float(elapsed)
            if diagnostic:client_detector['startup']=diagnostic
        result=dict(type='result',sequence=meta['sequence'],timestamp_ms=stamp,hands=len(hands),
            foreground_context=[float(x) for x in anchor],
            landmarks=[[[round(float(p.x),5),round(float(p.y),5)] for p in hand] for hand in hands],
            mode=self.mode,opencv=opencv,processing_ms=elapsed_ms,
            detection_fps=round(fps,1),vision_enabled=False,
            timing=dict(context_ms=round(1000*(context_done-started),1),detector_ms=round(1000*(detector_done-context_done),1)),
            landmark_source=(('android_gpu' if meta['hand_observation'].get('delegate')=='gpu' else 'android_cpu')
                if browser_observed and meta.get('hand_observation',{}).get('platform')=='android'
                else ('browser_cpu' if meta.get('hand_observation',{}).get('delegate')=='cpu' else 'browser_gpu') if browser_observed else 'cpu'),
            client_detector=client_detector,detector_timing=({} if browser_observed else self.detector.last_timing),**decision,
            message='Đang theo dõi ký hiệu' if hands else 'Đưa một hoặc hai tay vào khung hình')
        self.last_result=result
        self.publication+=1;result['publication']=self.publication
        if current_observation:self.trace.add(pose,wrist,anchor,result)
        return result
    def observe(self,meta):
        stamp=float(meta['timestamp_ms'])
        if stamp<=self.last_observation_timestamp:return None
        r=self.engine.runtime
        found=browser_hand_result(meta,self.recognizer.config['sha256']['hand_landmarker.task'])
        if found is None:raise ValueError('Live observation requires matching measured XYZ')
        anchor=np.zeros(4,np.float32);face_stamp=None
        if self.mode in ('words','all') and self.context_aspect is not None:
            if abs(meta['width']/meta['height']-self.context_aspect)<.01:
                anchor,face_stamp=self.context.snapshot(stamp/1000.)
        found=r.foreground_hand_result(found,meta['width'],meta['height'],anchor)
        pose,wrist,hands=r.features_from_result(found,meta['width'],meta['height'],False,
            allow_low_hands=True,tracker=self.tracker,now=stamp/1000.,
            keep_both_hands=self.recognizer.config.get('feature_pipeline') in r.TRACKED_PIPELINES)
        # This is a bounded cache of an actual face measurement, exactly as the
        # desktop's asynchronous context worker; never synthesize a new face.
        self.worker.submit(pose,wrist,stamp/1000.,anchor)
        self.last_observation_timestamp=stamp
        self.last_frame=(pose.copy(),hands,stamp,time.monotonic())
        base=self.last_result or dict(type='result',sequence=-1,mode=self.mode,opencv={},
            processing_ms=0.,detection_fps=0.,vision_enabled=False)
        self.publication+=1
        result={**base,**self._decision_fields(pose,hands,stamp),
            'publication':self.publication,'timestamp_ms':stamp,'hands':len(hands),
            'landmark_source':'live_xyz',
            'context_age_ms':None if face_stamp is None else round(stamp-face_stamp*1000,1),
            'landmarks':[[[round(float(p.x),5),round(float(p.y),5)] for p in hand] for hand in hands],
            'message':'Đang theo dõi ký hiệu' if hands else 'Đưa một hoặc hai tay vào khung hình'}
        result.pop('foreground_context',None)
        self.last_result=result
        self.trace.add(pose,wrist,anchor,result)
        return result
    def _decision_fields(self,pose,hands,stamp):
        now=stamp/1000.
        (output,scores,held,collision,completed),inference=self.worker.poll_with_details()
        prediction_stamp=inference.get('prediction_timestamp_ms')
        prediction_age=None if prediction_stamp is None else max(0.,stamp-prediction_stamp)
        confirmed=None
        if output is not None and output[0] is not None and output[3] and np.any(pose):
            label=self.recognizer.labels[int(output[0])]
            observed_stamp=inference.get('observation_timestamp_ms')
            current_hold=held and observed_stamp is not None and observed_stamp>=stamp-1.
            if label in self.allowed and prediction_age is not None and (prediction_age<1500 or current_hold):confirmed=label
        # Only verified, current-mode events can leave the service. The desktop
        # worker's earlier tentative events are not blindly appended to text.
        events=[]
        if hands:self.last_observed=now
        elif now-self.last_observed>.65:
            self.last_event_label=None
        status='tracking';score=None
        if confirmed is not None and scores is not None:score=float(scores[self.recognizer.labels.index(confirmed)])
        if confirmed is not None:
            status='confirmed'
            event_key=None
            if isinstance(completed,dict) and completed.get('label')==confirmed:
                event_time=completed.get('time')
                if isinstance(event_time,(int,float)) and np.isfinite(event_time) and -.001<=now-event_time<1.5:
                    event_key=(confirmed,float(event_time))
            if self.last_event_label!=confirmed or (event_key is not None and event_key!=self.last_event_key):
                self.last_event_label=confirmed;self.event_index+=1
                self.last_event_key=event_key
                events=[dict(id=self.event_index,label=confirmed,timestamp_ms=stamp,verification='colab')]
        return dict(confirmed=confirmed,events=events,status=status,score=score,
            inference=inference,prediction_age_ms=prediction_age)

    def recognition_update(self):
        # Called on the same owner executor as process(). Never run MediaPipe
        # concurrently, and never revive an old result after camera delivery stops.
        if self.last_frame is None or self.last_result is None:return None
        pose,hands,stamp,received=self.last_frame
        if time.monotonic()-received>2.:return None
        # A batch may finish while newer observations are queued. Publish only
        # evidence that has caught up to the image currently displayed.
        observed=self.worker.poll_with_details()[1].get('observation_timestamp_ms')
        if observed is None or observed<stamp-1.:return None
        decision=self._decision_fields(pose,hands,stamp)
        self.publication+=1
        result={**self.last_result,**decision,'publication':self.publication,'timestamp_ms':stamp}
        if stamp!=self.last_result['timestamp_ms']:result.pop('foreground_context',None)
        self.last_result=result
        self.trace.update_result(result)
        return result

    def close(self):
        self.worker.close();self.detector.close();self.context.close()
        try:self.trace.save()
        except OSError:
            import logging
            logging.exception('Could not save local regression coordinates')

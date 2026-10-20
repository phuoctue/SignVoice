"""Camera detector from the desktop camera; classifier remains pinned."""
import time
import numpy as np
from .model_runtime import OpenCVHandMotion

class ResilientHandLandmarker:
    """Keep VIDEO observations; merge distinct IMAGE detections on loss of a hand."""
    def __init__(self,task,video=True,opencv_assist=False):
        self.task=str(task);self.video=video;self.detector=None;self.fallback=None
        self.last_retry=-100000;self.recovered=False;self.last_pair=None;self.pair_stamp=-100000;self.clahe=None
        self.target_hands=2;self.search_regions=True;self.retry_index=0
        self.motion=OpenCVHandMotion() if opencv_assist and video else None
        self.last_observed=None;self.observed_stamp=-100000
        # Offline/training extraction retains the original exhaustive search.
        self.realtime_budget=False;self.retry_failures=0
        self.last_timing={}
    def __enter__(self):
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision
        self.detector=vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=self.task),
            running_mode=vision.RunningMode.VIDEO if self.video else vision.RunningMode.IMAGE,
            num_hands=2,min_hand_detection_confidence=.15,min_hand_presence_confidence=.15,min_tracking_confidence=.22))
        return self
    def close(self):
        if self.detector:self.detector.close();self.detector=None
        if self.fallback:self.fallback.close();self.fallback=None
    def __exit__(self,*args):self.close()
    @staticmethod
    def points(hand):return np.array([[p.x,p.y] for p in hand],np.float32)
    @classmethod
    def duplicate(cls,a,b):
        a,b=cls.points(a),cls.points(b)
        radius=max(float(np.linalg.norm(a-a[0],axis=1).max()),float(np.linalg.norm(b-b[0],axis=1).max()),.025)
        palm=[0,5,9,13,17]
        lo_a,hi_a=a.min(axis=0),a.max(axis=0);lo_b,hi_b=b.min(axis=0),b.max(axis=0)
        inter=np.maximum(0.,np.minimum(hi_a,hi_b)-np.maximum(lo_a,lo_b))
        inter_area=float(inter[0]*inter[1])
        min_area=max(min(float(np.prod(hi_a-lo_a)),float(np.prod(hi_b-lo_b))),1e-6)
        return (inter_area/min_area>.55 and float(np.median(np.linalg.norm(a-b,axis=1)))<.55*radius) or (
                float(np.linalg.norm(a[0]-b[0]))<.52*radius and
                float(np.median(np.linalg.norm(a-b,axis=1)))<.38*radius) or (
                float(np.median(np.linalg.norm(a[palm]-b[palm],axis=1)))<.26*radius and
                float(np.median(np.linalg.norm(a-b,axis=1)))<.45*radius)
    @classmethod
    def deduplicate_primary(cls,result):
        if len(result.hand_landmarks or [])==2 and cls.duplicate(result.hand_landmarks[0],result.hand_landmarks[1]):
            from copy import deepcopy
            cleaned=deepcopy(result)
            cleaned.hand_landmarks=cleaned.hand_landmarks[:1]
            cleaned.handedness=cleaned.handedness[:1]
            cleaned.hand_world_landmarks=cleaned.hand_world_landmarks[:1]
            return cleaned
        return result
    @classmethod
    def merge(cls,primary,recovered):
        from copy import deepcopy
        merged=cls.deduplicate_primary(deepcopy(primary))
        for i,hand in enumerate(recovered.hand_landmarks or []):
            if len(merged.hand_landmarks)>=2:break
            if any(cls.duplicate(hand,old) for old in merged.hand_landmarks):continue
            merged.hand_landmarks.append(hand)
            merged.handedness.append(recovered.handedness[i])
            merged.hand_world_landmarks.append(recovered.hand_world_landmarks[i])
        return merged
    def _retry(self,image,result,stamp):
        self.recovered=False
        result=self.deduplicate_primary(result)
        count=len(result.hand_landmarks or [])
        recently_bimanual=self.last_pair is not None and stamp-self.pair_stamp<=900
        delay=200 if count==0 or recently_bimanual else 600
        if self.realtime_budget:
            # A slow frame already exceeds 200 ms. Repeating a failed IMAGE
            # search on every VIDEO frame halves the observation rate again.
            # Keep primary tracking on every frame; back off only failed retries.
            delay=min(2000,delay*(2**min(self.retry_failures,3)))
        if not self.realtime_budget and count==0 and 0<stamp-self.observed_stamp<=900:delay=70
        if count<self.target_hands and stamp-self.last_retry>=delay:
            self.last_retry=stamp
            import cv2,mediapipe as mp
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision
            if self.fallback is None:
                self.fallback=vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
                    base_options=python.BaseOptions(model_asset_path=self.task),running_mode=vision.RunningMode.IMAGE,
                    num_hands=2,min_hand_detection_confidence=.15,min_hand_presence_confidence=.15))
            rgb=image.numpy_view();height,width=rgb.shape[:2]
            self.retry_index+=1;attempt=self.retry_index%3;retry_image=image;bounds=None
            flow_bounds=self.motion.missing_bounds(result.hand_landmarks or []) if self.motion and self.search_regions else None
            if self.search_regions and count==1 and not recently_bimanual and attempt==0:
                # Search the other side at higher effective palm resolution.
                x=float(result.hand_landmarks[0][0].x)
                x0,x1=(int(.30*width),width) if x<.5 else (0,int(.70*width))
                crop=np.ascontiguousarray(rgb[:,x0:x1])
                retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,0,x1,height)
            if count<2 and recently_bimanual:
                # Search only the recently observed missing hand; never replay its old landmarks.
                missing=[h for h in self.last_pair if not any(self.duplicate(h,v) for v in result.hand_landmarks)]
                if missing:
                    pts=self.points(missing[0]);lo=pts.min(axis=0);hi=pts.max(axis=0)
                    pad=max(float((hi-lo).max())*.85,.10)
                    x0,y0=np.floor(np.maximum(lo-pad,0)*[width,height]).astype(int)
                    x1,y1=np.ceil(np.minimum(hi+pad,1)*[width,height]).astype(int)
                    if x1-x0>=32 and y1-y0>=32:
                        crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                        retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,y0,x1,y1)
            if flow_bounds is not None:
                x0,y0,x1,y1=flow_bounds
                crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=flow_bounds
            if not self.realtime_budget and self.search_regions and bounds is None and count==0 and self.last_observed is not None and 0<stamp-self.observed_stamp<=350:
                pts=np.concatenate([self.points(hand) for hand in self.last_observed])
                lo=pts.min(axis=0);hi=pts.max(axis=0);pad=max(float((hi-lo).max())*.5,.07)
                x0,y0=np.floor(np.maximum(lo-pad,0)*[width,height]).astype(int)
                x1,y1=np.ceil(np.minimum(hi+pad,1)*[width,height]).astype(int)
                if x1-x0>=48 and y1-y0>=48:
                    retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=np.ascontiguousarray(rgb[y0:y1,x0:x1]));bounds=(x0,y0,x1,y1)
            if bounds is None and attempt==1:
                lab=cv2.cvtColor(rgb,cv2.COLOR_RGB2LAB)
                if self.clahe is None:self.clahe=cv2.createCLAHE(clipLimit=2.,tileGridSize=(8,8))
                lab[:,:,0]=self.clahe.apply(lab[:,:,0])
                enhanced=np.ascontiguousarray(cv2.cvtColor(lab,cv2.COLOR_LAB2RGB))
                retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=enhanced)
            if flow_bounds is None and self.search_regions and count==1 and not recently_bimanual and attempt==2:
                # Search both around and below the visible hand (e.g., support hand holding forearm/elbow in 'cứu').
                points=self.points(result.hand_landmarks[0]) if result.hand_landmarks else None
                if points is not None:
                    lo=points.min(axis=0);hi=points.max(axis=0)
                    pad_x=max(float((hi-lo).max())*1.2,.18)
                    pad_top=max(float((hi-lo).max())*.5,.08)
                    x0=int(max(0,np.floor((lo[0]-pad_x)*width)))
                    y0=int(max(0,np.floor((lo[1]-pad_top)*height)))
                    x1=int(min(width,np.ceil((hi[0]+pad_x)*width)))
                    y1=height
                    if x1-x0>=48 and y1-y0>=48:
                        crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                        retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,y0,x1,y1)
            # On complete loss, a fast-moving hand may already be outside its
            # previous crop. A current full-frame search is preferable to two
            # successive inferences on that stale crop. Flow-guided crops remain valid.
            found=self.fallback.detect(retry_image)
            if not self.realtime_budget and not found.hand_landmarks and count==0 and self.last_observed is not None and 0<stamp-self.observed_stamp<=900:
                flipped=cv2.rotate(np.ascontiguousarray(retry_image.numpy_view()),cv2.ROTATE_180)
                found=self.fallback.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=np.ascontiguousarray(flipped)))
                for hand in found.hand_landmarks:
                    for lm in hand:lm.x=1.-lm.x;lm.y=1.-lm.y
            if bounds is not None:
                x0,y0,x1,y1=bounds
                for hand in found.hand_landmarks:
                    for lm in hand:
                        lm.x=(x0+lm.x*(x1-x0))/width;lm.y=(y0+lm.y*(y1-y0))/height;lm.z*=float(x1-x0)/width
            result=self.merge(result,found)
            self.recovered=len(result.hand_landmarks)>count
            self.retry_failures=0 if self.recovered else min(self.retry_failures+1,8)
        if count>=self.target_hands:self.retry_failures=0
        if len(result.hand_landmarks)==2:
            from copy import deepcopy
            self.last_pair=deepcopy(result.hand_landmarks);self.pair_stamp=stamp
        if result.hand_landmarks:
            from copy import deepcopy
            self.last_observed=deepcopy(result.hand_landmarks);self.observed_stamp=stamp
        return result
    def detect_for_video(self,image,timestamp_ms):
        started=time.perf_counter()
        if self.motion:self.motion.begin(image.numpy_view(),timestamp_ms)
        motion_done=time.perf_counter()
        result=self.detector.detect_for_video(image,timestamp_ms)
        primary_done=time.perf_counter()
        result=self._retry(image,result,timestamp_ms)
        if self.motion:self.motion.observe(result.hand_landmarks or [])
        self.last_timing={'flow_ms':1000*(motion_done-started),
                          'primary_ms':1000*(primary_done-motion_done),
                          'recovery_ms':1000*(time.perf_counter()-primary_done)}
        return result
    def detect(self,image):
        # Independent IMAGE inputs must not inherit another image's retry timer/ROI.
        self.last_retry=-100000;self.last_pair=None;self.pair_stamp=-100000
        self.last_observed=None;self.observed_stamp=-100000
        return self._retry(image,self.detector.detect(image),0)

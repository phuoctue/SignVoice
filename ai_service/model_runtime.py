"""SignVoice: shared train/live features, few-shot templates and stable live output.

Run normally for webcam; --check validates the bundle without opening a camera.
--image PATH / --video PATH run offline diagnosis. --record LABEL records a new
labelled training clip only when explicitly selected by the user.
"""
import os
import sys
# Keep Vietnamese diagnostics readable in Windows terminals and redirected logs.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
# Leave CPU capacity for MediaPipe and capture while TensorFlow matches sequences.
os.environ.setdefault("TF_NUM_INTRAOP_THREADS", "2")
os.environ.setdefault("TF_NUM_INTEROP_THREADS", "1")
import argparse
import json
import time
from pathlib import Path
from collections import deque
import numpy as np

# BEGIN SHARED SIGNVOICE CODE — same definitions as this notebook CELL 4.
SCHEMA = "signvoice_hybrid_v5"
DYNAMIC_LABELS = {"ă", "â", "ê", "ô", "ơ", "ư"}
SEQUENCE_STEPS = 24
DOMAIN_CONFUSIONS = [("1","d"),("2","v"),("4","b"),("6","y"),("7","l"),("8","l")]

EXTRACTOR_VERSION = "stable_two_hand_v6_camera640"
TRACKED_PIPELINES = {"stable_two_hand_v1","stable_two_hand_v2","stable_two_hand_v3","stable_two_hand_v4","stable_two_hand_v5",EXTRACTOR_VERSION,"stable_two_hand_v6_camera640"}
COMPOUND_LETTER_LABELS = {"ă","â","ê","ô","ơ","ư"}

class HandSlotTracker:
    """Associate observed hands using motion and shape, including crossed wrists."""
    def __init__(self,max_gap=.90):
        self.max_gap=max_gap;self.reset()
    def reset(self):self.previous={}
    def assign(self,found,now):
        from itertools import permutations
        self.previous={slot:info for slot,info in self.previous.items() if 0<=now-info['time']<=self.max_gap}
        if not found:return []
        found=found[:2]
        positions=[np.array([abs(item[2][0]),item[2][3]],np.float32) for item in found]
        if not self.previous:slots=[1] if len(found)==1 else [0,1]
        else:
            best=None
            for slots in permutations((0,1),len(found)):
                cost=0.
                for item,pos,slot in zip(found,positions,slots):
                    old=self.previous.get(slot)
                    if old is None:cost+=.45;continue
                    dt=min(max(now-old['time'],0.),.25)
                    step=old['velocity']*dt
                    step*=min(1.,.15/max(float(np.linalg.norm(step)),1e-6))
                    cost+=float(np.linalg.norm(pos-old['position']-step))
                    raw=item[1];flipped=raw.copy();flipped[:,0]*=-1
                    # Handedness can flicker during occlusion; it is weak evidence.
                    cost+=.12*min(float(np.linalg.norm(raw-old['pose'])),float(np.linalg.norm(flipped-old['pose'])))/np.sqrt(63)
                    if len(item)>4 and item[4] and old['category'] and item[4]!=old['category']:cost+=.06
                if best is None or cost<best[0]:best=(cost,slots)
            slots=best[1]
        assigned=[]
        for item,pos,slot in zip(found,positions,slots):
            old=self.previous.get(slot)
            category=(old['category'] if old and old['category'] else item[4] if len(item)>4 else '')
            detected=item[4] if len(item)>4 else ''
            if category and detected and category!=detected:
                local=item[1].copy();local[:,0]*=-1
                wrist=item[2].copy();wrist[0]*=-1
                item=(item[0],local,wrist,item[3],category)
            dt=now-old['time'] if old else 0.
            velocity=(.5*old['velocity']+.5*(pos-old['position'])/dt) if old and .01<=dt<=.35 else np.zeros(2,np.float32)
            self.previous[slot]={'position':pos,'velocity':velocity,'pose':item[1].copy(),'category':category,'time':now}
            assigned.append((slot,item))
        return assigned

def repair_short_hand_gaps(pose,wrist,times,max_gap=.20):
    """Interpolate only short, bracketed omissions of the same tracked hand."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3).copy()
    w=np.asarray(wrist,np.float32).reshape(-1,2,4).copy();times=np.asarray(times)
    for hand in range(2):
        valid=np.flatnonzero(np.any(p[:,hand]!=0,axis=(1,2)))
        for left,right in zip(valid[:-1],valid[1:]):
            elapsed=times[right]-times[left]
            if right-left<=1 or elapsed<=0 or elapsed>max_gap:continue
            for i in range(left+1,right):
                alpha=float((times[i]-times[left])/elapsed)
                p[i,hand]=(1-alpha)*p[left,hand]+alpha*p[right,hand]
                w[i,hand]=(1-alpha)*w[left,hand]+alpha*w[right,hand]
    return p.reshape(-1,126),w.reshape(-1,8)

class OpenCVHandMotion:
    """Track real hand texture between frames; hints guide re-detection only."""
    def __init__(self):self.reset()
    def reset(self):
        self.gray=None;self.stamp=None;self.tracks=[];self.arrows=[];self.motion_mask=None
    def begin(self,rgb,stamp):
        import cv2
        gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY);self.arrows=[]
        usable=(self.gray is not None and self.gray.shape==gray.shape and
                self.stamp is not None and 0<stamp-self.stamp<=350)
        self.motion_mask=np.zeros_like(gray)
        if usable:
            for track in self.tracks:
                points=track['points']
                if len(points)<6:continue
                moved,status,_=cv2.calcOpticalFlowPyrLK(self.gray,gray,points,None,
                    winSize=(21,21),maxLevel=3,criteria=(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,20,.03))
                if moved is None:continue
                back,back_status,_=cv2.calcOpticalFlowPyrLK(gray,self.gray,moved,None,
                    winSize=(21,21),maxLevel=3)
                if back is None:continue
                old=points.reshape(-1,2);new=moved.reshape(-1,2)
                good=(status.ravel()!=0)&(back_status.ravel()!=0)&(np.linalg.norm(back.reshape(-1,2)-old,axis=1)<1.5)
                good&=(new[:,0]>=0)&(new[:,0]<gray.shape[1])&(new[:,1]>=0)&(new[:,1]<gray.shape[0])
                delta=new-old;shift=np.median(delta[good],axis=0) if good.sum()>=6 else None
                if shift is None:track['points']=np.empty((0,1,2),np.float32);continue
                # Reject incoherent/background flow instead of inventing a hand.
                good&=np.linalg.norm(delta-shift,axis=1)<max(3.,float(np.linalg.norm(shift))*.6)
                if good.sum()<6:track['points']=np.empty((0,1,2),np.float32);continue
                shift=np.median(delta[good],axis=0);track['box']+=np.tile(shift,2)
                track['wrist']+=shift;track['points']=new[good].reshape(-1,1,2).astype(np.float32)
                for a,b in zip(old[good][::4],new[good][::4]):self.arrows.append((a.copy(),b.copy()))
                x0,y0,x1,y1=np.round(track['box']).astype(int)
                x0,x1=np.clip([x0,x1],0,gray.shape[1]);y0,y1=np.clip([y0,y1],0,gray.shape[0])
                if x1>x0 and y1>y0:
                    diff=cv2.absdiff(gray[y0:y1,x0:x1],self.gray[y0:y1,x0:x1])
                    self.motion_mask[y0:y1,x0:x1]=cv2.threshold(diff,18,255,cv2.THRESH_BINARY)[1]
            self.tracks=[t for t in self.tracks if len(t['points'])>=6 and stamp-t['observed']<=350]
        else:self.tracks=[]
        self.gray=gray;self.stamp=stamp
    def missing_bounds(self,hands):
        if self.gray is None:return None
        h,w=self.gray.shape
        visible=[np.array([hand[0].x*w,hand[0].y*h]) for hand in hands]
        for track in self.tracks:
            radius=max(float(np.max(track['box'][2:]-track['box'][:2])),24.)
            if any(np.linalg.norm(point-track['wrist'])<radius*.65 for point in visible):continue
            lo=track['box'][:2]-radius*.7;hi=track['box'][2:]+radius*.7
            x0,y0=np.floor(np.maximum(lo,0)).astype(int);x1,y1=np.ceil(np.minimum(hi,[w,h])).astype(int)
            if x1-x0>=32 and y1-y0>=32:return (x0,y0,x1,y1)
        return None
    def observe(self,hands):
        import cv2
        if self.gray is None:return
        h,w=self.gray.shape;fresh=[]
        for hand in hands:
            xy=np.array([[p.x*w,p.y*h] for p in hand],np.float32)
            mask=np.zeros_like(self.gray)
            cv2.fillConvexPoly(mask,cv2.convexHull(np.round(xy).astype(np.int32)),255)
            points=cv2.goodFeaturesToTrack(self.gray,maxCorners=32,qualityLevel=.03,minDistance=4,mask=mask)
            if points is not None and len(points)>=6:
                fresh.append(dict(points=points,box=np.r_[xy.min(axis=0),xy.max(axis=0)],wrist=xy[0].copy(),observed=self.stamp))
        # Keep a short texture track of an unobserved hand to search its new ROI.
        for track in self.tracks:
            radius=max(float(np.max(track['box'][2:]-track['box'][:2])),24.)
            if not any(np.linalg.norm(track['wrist']-np.array([hand[0].x*w,hand[0].y*h]))<radius*.65 for hand in hands):
                fresh.append(track)
        self.tracks=fresh[:2]

class ResilientHandLandmarker:
    """Keep VIDEO observations; merge distinct IMAGE detections on loss of a hand."""
    def __init__(self,task,video=True,opencv_assist=False):
        self.task=str(task);self.video=video;self.detector=None;self.fallback=None
        self.last_retry=-100000;self.recovered=False;self.last_pair=None;self.pair_stamp=-100000;self.clahe=None
        self.target_hands=2;self.search_regions=True;self.retry_index=0
        self.motion=OpenCVHandMotion() if opencv_assist and video else None
        self.last_observed=None;self.observed_stamp=-100000
    def __enter__(self):
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision
        self.detector=vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=self.task),
            running_mode=vision.RunningMode.VIDEO if self.video else vision.RunningMode.IMAGE,
            num_hands=2,min_hand_detection_confidence=.35,min_hand_presence_confidence=.35,min_tracking_confidence=.5))
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
        return (float(np.linalg.norm(a[0]-b[0]))<.40*radius and
                float(np.median(np.linalg.norm(a-b,axis=1)))<.28*radius) or (
                float(np.median(np.linalg.norm(a[palm]-b[palm],axis=1)))<.18*radius and
                float(np.median(np.linalg.norm(a-b,axis=1)))<.38*radius)
    @classmethod
    def merge(cls,primary,recovered):
        from copy import deepcopy
        merged=deepcopy(primary)
        for i,hand in enumerate(recovered.hand_landmarks or []):
            if len(merged.hand_landmarks)>=2:break
            if any(cls.duplicate(hand,old) for old in merged.hand_landmarks):continue
            merged.hand_landmarks.append(hand)
            merged.handedness.append(recovered.handedness[i])
            merged.hand_world_landmarks.append(recovered.hand_world_landmarks[i])
        return merged
    def _retry(self,image,result,stamp):
        self.recovered=False
        count=len(result.hand_landmarks or [])
        recently_bimanual=self.last_pair is not None and stamp-self.pair_stamp<=900
        delay=250 if count==0 or recently_bimanual else 750
        if count<self.target_hands and stamp-self.last_retry>=delay:
            self.last_retry=stamp
            import cv2,mediapipe as mp
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision
            if self.fallback is None:
                self.fallback=vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
                    base_options=python.BaseOptions(model_asset_path=self.task),running_mode=vision.RunningMode.IMAGE,
                    num_hands=2,min_hand_detection_confidence=.35,min_hand_presence_confidence=.35))
            rgb=image.numpy_view();height,width=rgb.shape[:2]
            self.retry_index+=1;attempt=self.retry_index%3;retry_image=image;bounds=None
            flow_bounds=self.motion.missing_bounds(result.hand_landmarks or []) if self.motion and self.search_regions else None
            if self.search_regions and count==1 and not recently_bimanual and attempt==0:
                # Search the other side at higher effective palm resolution.
                # This is enabled for the alphabet when a second visible hand
                # (e.g. touching the head) can hide the signing hand.
                x=float(result.hand_landmarks[0][0].x)
                x0,x1=(int(.40*width),width) if x<.5 else (0,int(.60*width))
                crop=np.ascontiguousarray(rgb[:,x0:x1])
                retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,0,x1,height)
            if count<2 and recently_bimanual:
                # Search only the recently observed missing hand; never replay its old landmarks.
                missing=[h for h in self.last_pair if not any(self.duplicate(h,v) for v in result.hand_landmarks)]
                if missing:
                    pts=self.points(missing[0]);lo=pts.min(axis=0);hi=pts.max(axis=0)
                    pad=max(float((hi-lo).max())*.80,.08)
                    x0,y0=np.floor(np.maximum(lo-pad,0)*[width,height]).astype(int)
                    x1,y1=np.ceil(np.minimum(hi+pad,1)*[width,height]).astype(int)
                    if x1-x0>=32 and y1-y0>=32:
                        crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                        retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,y0,x1,y1)
            if flow_bounds is not None:
                x0,y0,x1,y1=flow_bounds
                crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=flow_bounds
            if self.search_regions and bounds is None and count==0 and self.last_observed is not None and 0<stamp-self.observed_stamp<=350:
                # A temporarily lost single signing hand needs a search ROI too.
                # Previously only a last observed pair could guide re-acquisition.
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
                # Zoom the visible hand and its surrounding support-hand area.
                # This also initializes tracking when two palms overlap at entry.
                points=self.points(result.hand_landmarks[0]) if result.hand_landmarks else None
                if points is not None:
                    lo=points.min(axis=0);hi=points.max(axis=0)
                    pad=max(float((hi-lo).max())*.85,.12)
                    x0,y0=np.floor(np.maximum(lo-pad,0)*[width,height]).astype(int)
                    x1,y1=np.ceil(np.minimum(hi+pad,1)*[width,height]).astype(int)
                    if x1-x0>=48 and y1-y0>=48:
                        crop=np.ascontiguousarray(rgb[y0:y1,x0:x1])
                        retry_image=mp.Image(image_format=mp.ImageFormat.SRGB,data=crop);bounds=(x0,y0,x1,y1)
            # Bound recovery work to one extra inference per retry. Several full
            # IMAGE passes on every missing support hand starved camera sampling.
            found=self.fallback.detect(retry_image)
            if bounds is not None:
                x0,y0,x1,y1=bounds
                for hand in found.hand_landmarks:
                    for lm in hand:
                        lm.x=(x0+lm.x*(x1-x0))/width;lm.y=(y0+lm.y*(y1-y0))/height;lm.z*=float(x1-x0)/width
            result=self.merge(result,found)
            self.recovered=len(result.hand_landmarks)>count
        if len(result.hand_landmarks)==2:
            from copy import deepcopy
            self.last_pair=deepcopy(result.hand_landmarks);self.pair_stamp=stamp
        if result.hand_landmarks:
            from copy import deepcopy
            self.last_observed=deepcopy(result.hand_landmarks);self.observed_stamp=stamp
        return result
    def detect_for_video(self,image,timestamp_ms):
        if self.motion:self.motion.begin(image.numpy_view(),timestamp_ms)
        result=self.detector.detect_for_video(image,timestamp_ms)
        result=self._retry(image,result,timestamp_ms)
        if self.motion:self.motion.observe(result.hand_landmarks or [])
        return result
    def detect(self,image):
        # Independent IMAGE inputs must not inherit another image's retry timer/ROI.
        self.last_retry=-100000;self.last_pair=None;self.pair_stamp=-100000
        self.last_observed=None;self.observed_stamp=-100000
        return self._retry(image,self.detector.detect(image),0)

class SigningContextTracker:
    """A coarse eye/face anchor; no identity storage or extra model download."""
    def __init__(self,model_path=None):
        import cv2
        self.detector=None
        if model_path is not None:
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision
            self.detector=vision.FaceDetector.create_from_options(vision.FaceDetectorOptions(
                base_options=python.BaseOptions(model_asset_path=str(model_path)),min_detection_confidence=.5))
        self.eyes=cv2.CascadeClassifier(cv2.data.haarcascades+'haarcascade_eye_tree_eyeglasses.xml')
        self.anchor=np.zeros(4,np.float32);self.last_seen=-np.inf;self.next_check=-np.inf
        self.reference_scale=0.;self.reference_seen=-np.inf
    def update(self,frame,now):
        import cv2
        if now>=self.next_check:
            self.next_check=now+.40
            h,w=frame.shape[:2];factor=min(1.,640/w)
            gray=cv2.cvtColor(cv2.resize(frame,(round(w*factor),round(h*factor))),cv2.COLOR_BGR2GRAY)
            candidates=[]
            if self.detector is not None:
                import mediapipe as mp
                result=self.detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=cv2.cvtColor(frame,cv2.COLOR_BGR2RGB)))
                for detection in result.detections:
                    if len(detection.keypoints)<2:continue
                    eyes=np.array([[point.x,point.y*h/w] for point in detection.keypoints[:2]],np.float32)
                    scale=2.3*float(np.linalg.norm(eyes[1]-eyes[0]))
                    center=eyes.mean(axis=0)
                    if .035<scale<.9:candidates.append(np.array([center[0],center[1],scale,1.],np.float32))
            elif not self.eyes.empty():
                eyes=self.eyes.detectMultiScale(gray,1.05,4,minSize=(12,12))
                for i,(x,y,bw,bh) in enumerate(eyes):
                    a=np.array([x+bw/2,y+bh/2])
                    for xx,yy,ww,hh in eyes[i+1:]:
                        b=np.array([xx+ww/2,yy+hh/2]);distance=float(np.linalg.norm(a-b))
                        if abs(a[1]-b[1])>.30*distance or not 1.8<distance/max((bw+ww)/2,1)<3.8:continue
                        if max(bw,ww)/max(min(bw,ww),1)>1.8:continue
                        center=(a+b)/2;scale=2.3*distance/(w*factor)
                        if not .07<scale<.70:continue
                        candidates.append(np.array([center[0]/(w*factor),center[1]/(w*factor),scale,1.],np.float32))
            if candidates:
                best=max(candidates,key=lambda a:float(a[2]))
                # A masked eye must not be accepted as a whole face. Require a
                # plausible pair, and retain the foreground scale during brief
                # occlusion rather than switching to smaller background faces.
                scale_ok=now-self.reference_seen>10. or best[2]>=.70*self.reference_scale
                consistent=now-self.last_seen>1.2 or np.linalg.norm(best[:2]-self.anchor[:2])<1.5*self.anchor[2]
                if scale_ok and consistent:
                    self.anchor=best;self.last_seen=now
                    self.reference_scale=float(best[2]);self.reference_seen=now
        if now-self.last_seen>1.2:return np.zeros(4,np.float32)
        return self.anchor.copy()
    def close(self):
        if self.detector is not None:self.detector.close();self.detector=None

def foreground_hand_result(result,width,height,context=None,min_radius=.025):
    """Discard tiny background hands before they can change tracking slots."""
    from copy import deepcopy
    out=deepcopy(result);keep=[]
    anchor=np.asarray(context if context is not None else np.zeros(4),np.float32)
    # A folded supporting fist is smaller than an open palm. Do not remove it
    # merely because a large, nearby face supplied the scale reference.
    threshold=max(.012,.10*float(anchor[2])) if anchor[3]>0 else min_radius
    for i,hand in enumerate(result.hand_landmarks or []):
        points=np.array([[lm.x,lm.y*height/width,lm.z] for lm in hand],np.float32)
        radius=float(np.linalg.norm(points-points[:1],axis=1).max())
        if radius<threshold:continue
        if anchor[3]>0 and abs(float(points[0,0])-float(anchor[0]))>max(.35,4*float(anchor[2])):continue
        keep.append(i)
    out.hand_landmarks=[result.hand_landmarks[i] for i in keep]
    out.handedness=[result.handedness[i] for i in keep]
    out.hand_world_landmarks=[result.hand_world_landmarks[i] for i in keep]
    return out

def signing_location(pose,wrist,context):
    """Position relative to the signer's eye line, with explicit missing masks."""
    locations=np.zeros((3,2,2),np.float32);valid=np.zeros((3,2),bool)
    if context is None or len(context)!=len(pose):return locations.reshape(-1),valid.reshape(-1)
    p=np.asarray(pose).reshape(-1,2,21,3);w=np.asarray(wrist).reshape(-1,2,4);anchor=np.asarray(context,np.float32)
    present=np.any(p!=0,axis=(2,3));observed=(anchor[:,3]>0)&(anchor[:,2]>.02)
    for phase,ids in enumerate(np.array_split(np.arange(len(p)),3)):
        for hand in range(2):
            seen=ids[present[ids,hand]&observed[ids]]
            if len(seen)<2:continue
            xy=np.stack([np.sign(w[seen,hand,0])*(np.abs(w[seen,hand,0])-anchor[seen,0]),w[seen,hand,1]-anchor[seen,1]],axis=1)
            xy/=anchor[seen,2,None]
            locations[phase,hand]=np.median(np.clip(xy,-4,4),axis=0);valid[phase,hand]=True
    return locations.reshape(-1),valid.reshape(-1)

def location_penalties(pose,wrist,context,arrays):
    result=np.zeros(len(arrays['temporal']),np.float32)
    if 'template_location' not in arrays:return result
    location,valid=signing_location(pose,wrist,context)
    usable=arrays['template_location_valid'].astype(bool)&valid[None]
    distance=np.linalg.norm(arrays['template_location'].reshape(-1,6,2)-location.reshape(1,6,2),axis=2)
    count=usable.sum(axis=1);mean=np.sum(np.minimum(distance,4)*usable,axis=1)/np.maximum(count,1)
    result[count>=2]=np.maximum(mean[count>=2]-.30,0)
    return result

def unit(x):
    x = np.asarray(x, np.float32)
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-8)

def features_from_result(result, width, height, legacy=False, allow_low_hands=False, tracker=None, now=0., keep_both_hands=False):
    """126 pose coordinates + 8 wrist/scale values, same for train and camera.

    Single hand always occupies slot 1. For the new schema, canonicalize the
    detector's handedness so a mirrored one-hand image has the same pose.
    Display mirroring is independent of the image passed to MediaPipe.
    Live inference accepts low wrists; the default preserves existing TRAIN caches.
    """
    found = []
    for i, landmarks in enumerate(result.hand_landmarks or []):
        pts = np.asarray([[p.x*width, p.y*height, p.z*width] for p in landmarks], np.float32)
        wrist = pts[0].copy()
        local = pts - wrist
        radius = float(np.linalg.norm(local, axis=1).max())
        if radius <= 1e-6 or not np.isfinite(pts).all():
            continue
        if (not allow_low_hands and wrist[1]/height > .82) or radius/width < .012:
            continue  # TRAIN rest-hand filter; live never imposes an absolute wrist-height gate.
        local /= radius
        category = ""
        if getattr(result, "handedness", None) and i < len(result.handedness):
            category = result.handedness[i][0].category_name
        direction = -1.0 if not legacy and category == "Left" else 1.0
        local[:,0] *= direction
        found.append((float(wrist[0]), local,
                      np.array([direction*wrist[0]/width, wrist[1]/width, radius/width, wrist[1]/height], np.float32), landmarks, category))
    found.sort(key=lambda item: item[0])
    pose, wrist = np.zeros((2,21,3), np.float32), np.zeros((2,4), np.float32)
    # A hanging second hand in a full-body video must not change the signing hand's slot.
    if len(found)==2 and not keep_both_hands:
        higher,lower=sorted(found,key=lambda item:item[2][1])
        if (lower[2][3]>.55 and lower[2][1]-higher[2][1]>2.5*max(higher[2][2],lower[2][2])
                and np.mean(lower[1][[8,12,16,20],1])>.25):
            found=[higher]
    selected = found[:2]
    slots = [1] if len(selected) == 1 else list(range(len(selected)))
    assigned=tracker.assign(selected,now) if tracker is not None else zip(slots,selected)
    for slot, item in assigned:
        pose[slot], wrist[slot] = item[1], item[2]
    return pose.reshape(126), wrist.reshape(8), [item[3] for item in selected]

def prepare_sign_sequence(pose,wrist,observed=None):
    """Remove only clearly stationary, downward rest hands; preserve supporting hands."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3).copy()
    w=np.asarray(wrist,np.float32).reshape(-1,2,4).copy()
    measured=None if observed is None else np.asarray(observed,bool).reshape(-1,2).copy()
    if measured is not None and len(measured)!=len(p):raise ValueError('Observation mask length differs from pose')
    present=np.any(p!=0,axis=(2,3));n=len(p)
    if n>=6:
        for hand in range(2):
            other=1-hand;ids=np.flatnonzero(present[:,hand]);other_ids=np.flatnonzero(present[:,other])
            if len(ids)<6 or len(other_ids)<6:continue
            radius=max(float(np.median(w[ids,hand,2])),.015)
            xy=w[ids,hand,:2].copy();xy[:,0]=np.abs(xy[:,0])
            span=float(np.linalg.norm(np.quantile(xy,.9,axis=0)-np.quantile(xy,.1,axis=0)))/radius
            other_xy=w[other_ids,other,:2].copy();other_xy[:,0]=np.abs(other_xy[:,0])
            other_span=float(np.linalg.norm(np.quantile(other_xy,.9,axis=0)-np.quantile(other_xy,.1,axis=0)))/max(float(np.median(w[other_ids,other,2])),.015)
            low=float(np.median(w[ids,hand,3]))
            downward=float(np.median(p[ids,hand][:,[8,12,16,20],1]))>.20
            resting=(low>.78 and low-float(np.quantile(w[other_ids,other,3],.2))>.18
                     and span<.45 and float(p[ids,hand].std(axis=0).mean())<.045
                     and downward and other_span>.75)
            if resting:
                p[:,hand]=0;w[:,hand]=0;present[:,hand]=False
                if measured is not None:measured[:,hand]=False
    # A one-hand sign may switch slots after a detector reset. Canonicalize only
    # sequences without sustained simultaneous evidence; do not flatten real bimanual signs.
    if int(np.all(present,axis=1).sum())<3:
        single=present.sum(axis=1)==1;from_zero=single & present[:,0]
        p[from_zero,1]=p[from_zero,0];w[from_zero,1]=w[from_zero,0]
        p[from_zero,0]=0;w[from_zero,0]=0
        if measured is not None:
            measured[from_zero,1]=measured[from_zero,0];measured[from_zero,0]=False
    if measured is not None:
        measured &= np.any(p!=0,axis=(2,3))
        return p.reshape(-1,126),w.reshape(-1,8),measured
    return p.reshape(-1,126),w.reshape(-1,8)

def resample(seq, length=40):
    seq=np.asarray(seq,np.float32)
    if not len(seq):raise ValueError('Empty sign sequence')
    t=np.linspace(0,len(seq)-1,length)
    left=np.floor(t).astype(int);right=np.minimum(left+1,len(seq)-1)
    alpha=(t-left).reshape((-1,)+(1,)*(seq.ndim-1))
    return ((1-alpha)*seq[left]+alpha*seq[right]).astype(np.float32)

def gesture_interval(pose,wrist,context=None):
    """Trim observable rest only at the two boundaries, never between sign steps."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3);w=np.asarray(wrist,np.float32).reshape(-1,2,4)
    present=np.any(p!=0,axis=(2,3));ids=np.flatnonzero(present.any(axis=1))
    if len(ids)<3:raise ValueError('Fewer than 3 usable hand frames')
    first,last=int(ids[0]),int(ids[-1]+1)
    elevation=np.min(np.where(present,w[:,:,3],np.inf),axis=1)
    low,high=np.quantile(elevation[ids],[.1,.9])
    downward=np.all(~present | (np.mean(p[:,:,[8,12,16,20],1],axis=2)>.12),axis=1)
    rest=np.zeros(len(p),bool)
    if high-low>.12:rest=downward & (elevation>low+.65*(high-low))
    if context is not None and len(context)==len(p):
        anchor=np.asarray(context,np.float32);valid=anchor[:,3]>0
        relative=(w[:,:,1]-anchor[:,1,None])/np.maximum(anchor[:,2,None],.02)
        below=np.all(~present | (relative>3.),axis=1)
        rest|=valid & downward & below
    active=ids[~rest[ids]]
    if len(active)>=6:
        if rest[ids[:3]].all():first=int(active[0])
        if rest[ids[-3:]].all():last=int(active[-1]+1)
    return first,last

def trim_gesture(pose, wrist, dynamic=False, keep_full_motion=False,context=None):
    """Use the clip's elevation range; keep the full interval between sign phases."""
    pose,wrist=np.asarray(pose,np.float32),np.asarray(wrist,np.float32)
    ids=np.flatnonzero(np.any(pose!=0,axis=1))
    if len(ids)<3:raise ValueError('Fewer than 3 usable hand frames')
    if keep_full_motion:
        first,last=gesture_interval(pose,wrist,context)
        return pose[first:last].copy(),wrist[first:last].copy()
    y=wrist.reshape(-1,2,4)[:,:,3].copy()
    present=np.any(pose.reshape(-1,2,21,3)!=0,axis=(2,3));y[~present]=np.inf
    elevation=y.min(axis=1);low,high=np.quantile(elevation[ids],[.10,.90])
    if high-low>.06:
        margin=float(np.clip(.40*(high-low),.05,.12 if dynamic else .09))
        raised=ids[elevation[ids]<=min(.82,low+margin)]
        if len(raised)>=3:
            # Two frames of context retain the first/last movement without long rest tails.
            padding=2 if dynamic else 0
            ids=ids[(ids>=raised[0]-padding)&(ids<=raised[-1]+padding)]
    return pose[ids].copy(),wrist[ids].copy()

def shape_descriptor(pose):
    """Balance image orientation, palm-local pose, finger bends and thumb contacts."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    present=np.any(p!=0,axis=(2,3));n=len(p)
    palm=p[:,:,[5,9,13,17]].mean(axis=2)-p[:,:,0]
    axis_y=unit(palm)
    across=p[:,:,5]-p[:,:,17]
    axis_x=unit(across-np.sum(across*axis_y,axis=-1,keepdims=True)*axis_y)
    axis_z=unit(np.cross(axis_x,axis_y))
    basis=np.stack([axis_x,axis_y,axis_z],axis=-1)
    local=np.einsum('nhjc,nhck->nhjk',p,basis)
    scale=np.maximum(np.median(np.linalg.norm(p[:,:,[5,9,13,17]]-p[:,:,:1],axis=-1),axis=-1),.10)
    bends,extensions=[],[]
    for base in (1,5,9,13,17):
        joints=[0,base,base+1,base+2,base+3]
        for j in (1,2,3):
            a,b,c=(p[:,:,joints[k]] for k in (j-1,j,j+1))
            angle=np.arccos(np.clip(np.sum(unit(a-b)*unit(c-b),axis=-1),-1,1))/np.pi
            bends.append(np.where(present,angle,0))
        bones=np.linalg.norm(np.diff(p[:,:,base:base+4],axis=2),axis=-1).sum(axis=-1)
        extension=np.linalg.norm(p[:,:,base+3]-p[:,:,base],axis=-1)/np.maximum(bones,1e-5)
        extensions.append(np.where(present,np.clip(extension,0,1),0))
    distances=[];tips=[4,8,12,16,20]
    pairs=[(t,0) for t in tips]+[(t,m) for t in tips for m in [1,5,9,13,17]]
    pairs += [(a,b) for i,a in enumerate(tips) for b in tips[i+1:]]
    for a,b in pairs:
        d=np.linalg.norm(p[:,:,a]-p[:,:,b],axis=-1)/scale
        distances.append(np.where(present,np.clip(d,0,4)/4,0))
    blocks=[unit(p.reshape(n,-1))*.40,unit(local.reshape(n,-1))*.40,
            unit(np.stack(bends,axis=-1).reshape(n,-1))*.70,
            unit(np.stack(distances,axis=-1).reshape(n,-1))*.70,
            unit(np.stack(extensions,axis=-1).reshape(n,-1))*.70,
            present.astype(np.float32)*.10]
    return unit(np.concatenate(blocks,axis=1))

def representative_frames(pose, wrist, count=3):
    """Medoid of stable elevated poses, not the last frame or lowest-motion rest."""
    pose,wrist = trim_gesture(pose,wrist,False)
    if len(pose) > 60:
        ids = np.linspace(0,len(pose)-1,60,dtype=int)
        pose,wrist = pose[ids],wrist[ids]
    d = shape_descriptor(pose)
    speed = np.linalg.norm(np.diff(pose,axis=0,prepend=pose[:1]),axis=1)
    stable = np.flatnonzero(speed <= np.quantile(speed,.60))
    if len(stable) < 3:
        stable = np.arange(len(pose))
    sim = d[stable] @ d[stable].T
    central = stable[np.argmax(np.median(sim,axis=1))]
    close = np.argsort(-(d @ d[central]))[:max(count,len(d)//3)]
    close = close[np.argsort(speed[close],kind="stable")]
    ids = np.unique(np.r_[central, close[:max(0,count-1)]])
    return pose[ids]

def metric_descriptor(descriptor,metric):
    if metric is None:
        return descriptor
    return unit((descriptor-metric['metric_mean'])/metric['metric_std'])

def phase_resample(pose,wrist,length=40):
    """Give both ordered phases equal duration when a clear change point exists."""
    pose,wrist=np.asarray(pose,np.float32),np.asarray(wrist,np.float32)
    n=len(pose)
    if n<6:return resample(pose,length),resample(wrist,length)
    shape=shape_descriptor(pose)
    raw=wrist.reshape(n,2,4);path=np.zeros((n,2,2),np.float32)
    present=np.any(pose.reshape(n,2,21,3)!=0,axis=(2,3))
    for hand in range(2):
        ids=np.flatnonzero(present[:,hand])
        if len(ids):
            scale=max(float(np.median(raw[ids,hand,2])),.015)
            path[ids,hand]=np.clip((raw[ids,hand,:2]-raw[ids[0],hand,:2])/scale,-5,5)*.06
    features=np.concatenate([shape,path.reshape(n,4)],axis=1).astype(np.float64)
    sums=np.cumsum(features,axis=0);square=np.cumsum(np.sum(features*features,axis=1))
    minimum=max(3,int(n*.15));candidates=np.arange(minimum,n-minimum+1)
    left=square[candidates-1]-np.sum(sums[candidates-1]**2,axis=1)/candidates
    right=(square[-1]-square[candidates-1])-np.sum((sums[-1]-sums[candidates-1])**2,axis=1)/(n-candidates)
    best=int(candidates[np.argmin(left+right)])
    total=float(square[-1]-np.sum(sums[-1]**2)/n)
    cost=float(np.min(left+right))
    first=sums[best-1]/best;second=(sums[-1]-sums[best-1])/(n-best)
    separated=np.linalg.norm(first[:-4]-second[:-4])>.12 or np.linalg.norm(first[-4:]-second[-4:])>.025
    if total>1e-6 and cost<.80*total and separated:
        half=length//2
        return (np.concatenate([resample(pose[:best],half),resample(pose[best:],length-half)]),
                np.concatenate([resample(wrist[:best],half),resample(wrist[best:],length-half)]))
    return resample(pose,length),resample(wrist,length)

def resample_hand_sequence(pose,wrist,length):
    """Do not linearly invent a hand between a missing and an observed frame."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    w=np.asarray(wrist,np.float32).reshape(-1,2,4)
    out_p=resample(p,length);out_w=resample(w,length)
    t=np.linspace(0,len(p)-1,length);left=np.floor(t).astype(int);right=np.ceil(t).astype(int)
    valid=np.any(p!=0,axis=(2,3));nearest=np.rint(t).astype(int)
    for hand in range(2):
        mixed=valid[left,hand]!=valid[right,hand]
        out_p[mixed,hand]=p[nearest[mixed],hand];out_w[mixed,hand]=w[nearest[mixed],hand]
    return out_p.reshape(length,126),out_w.reshape(length,8)

def motion_evidence(pose,wrist):
    """Measure movement only within observations of each real hand, never from zeros."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    w=np.asarray(wrist,np.float32).reshape(-1,2,4)
    present=np.any(p!=0,axis=(2,3));shape=0.;path=0.
    for hand in range(2):
        ids=np.flatnonzero(present[:,hand])
        if len(ids)<3:continue
        shape=max(shape,float(np.linalg.norm(p[ids,hand]-p[ids[0],hand],axis=(1,2)).max()/np.sqrt(63)))
        xy=w[ids,hand,:2].copy();xy[:,0]=np.abs(xy[:,0])
        scale=max(float(np.median(w[ids,hand,2])),.015)
        travel=8*np.tanh(((xy-xy[:1])/scale)/8)*.10
        path=max(path,float(np.linalg.norm(travel,axis=1).max()))
    return shape,path

def sequence_descriptor(pose,wrist,length=SEQUENCE_STEPS,metric=None):
    version=int(np.asarray((metric or {}).get("sequence_version",1)).item())
    pose,wrist=resample_hand_sequence(pose,wrist,length) if version>=3 else (resample(pose,length),resample(wrist,length))
    shape=metric_descriptor(shape_descriptor(pose),metric)
    p=pose.reshape(length,2,21,3);w=wrist.reshape(length,2,4)
    present=np.any(p!=0,axis=(2,3));path=np.zeros((length,2,2),np.float32)
    version=int(np.asarray((metric or {}).get('sequence_version',1)).item())
    global_xy=w[:,:,:2].copy()
    if version>=2:global_xy[:,:,0]=np.abs(global_xy[:,:,0])
    for hand in range(2):
        ids=np.flatnonzero(present[:,hand])
        if not len(ids):continue
        scale=max(float(np.median(w[ids,hand,2])),.015)
        motion=(global_xy[ids,hand]-global_xy[ids[0],hand])/scale
        path[ids,hand]=(8*np.tanh(motion/8)*.10 if version>=2 else np.clip(motion,-5,5)*.06)
    if version<2:return np.concatenate([shape,path.reshape(length,4)],axis=1).astype(np.float32)
    # Inter-hand spacing separates coordinated two-hand gestures with similar shapes.
    geometry=np.zeros((length,4),np.float32);both=present.all(axis=1)
    scale=np.maximum(np.mean(w[:,:,2],axis=1),.015)
    delta=(global_xy[:,1]-global_xy[:,0])/scale[:,None]
    geometry[both,:2]=8*np.tanh(delta[both]/8)*.10
    geometry[both,2]=np.clip(np.log(np.maximum(w[both,1,2],1e-5)/np.maximum(w[both,0,2],1e-5)),-2,2)*.10
    geometry[:,3]=both.astype(np.float32)*.25
    return np.concatenate([shape,path.reshape(length,4),geometry],axis=1).astype(np.float32)

def dtw_distances(query, templates, band=5, template_norms=None):
    """Batched banded DTW: all templates in one NumPy dynamic program."""
    q,t = np.asarray(query,np.float32),np.asarray(templates,np.float32)
    norms=np.sum(t*t,axis=2) if template_norms is None else template_norms
    costs = np.maximum(norms[:,:,None]+np.sum(q*q,axis=1)[None,None,:]
                       -2*np.einsum('mid,jd->mij',t,q,optimize=True),0)
    n,m = t.shape[1],len(q)
    previous = np.full((len(t),m+1),np.inf,np.float32);previous[:,0]=0
    for i in range(1,n+1):
        current = np.full_like(previous,np.inf)
        for j in range(max(1,i-band),min(m,i+band)+1):
            current[:,j] = costs[:,i-1,j-1] + np.minimum(np.minimum(previous[:,j],current[:,j-1]),previous[:,j-1])
        previous = current
    # A fixed divisor keeps distances comparable across equal-length windows.
    # Mean endpoint phases are less sensitive to a single noisy boundary frame.
    start=np.sum((t[:,:3].mean(axis=1)-q[:3].mean(axis=0))**2,axis=1)
    finish=np.sum((t[:,-3:].mean(axis=1)-q[-3:].mean(axis=0))**2,axis=1)
    endpoint=start+finish
    return previous[:,m]/max(n,m)+.10*endpoint

def word_hand_sequence(pose,wrist,metric,length=SEQUENCE_STEPS):
    """Represent each observed hand independently; missing palms have no pose."""
    pose,wrist=resample_hand_sequence(pose,wrist,length)
    p=pose.reshape(length,2,21,3);w=wrist.reshape(length,2,4)
    present=np.any(p!=0,axis=(2,3));dim=len(metric['metric_mean']);features=[]
    for hand in range(2):
        one_p=np.zeros_like(p);one_w=np.zeros_like(w)
        one_p[:,1]=p[:,hand];one_w[:,1]=w[:,hand]
        desc=sequence_descriptor(one_p.reshape(length,126),one_w.reshape(length,8),length,metric)
        feature=np.concatenate([desc[:,:dim],desc[:,dim+2:dim+4]],axis=1)
        feature[~present[:,hand]]=0;features.append(feature)
    geometry=sequence_descriptor(pose,wrist,length,metric)[:,-4:]
    return np.stack(features,axis=1).astype(np.float32),present,geometry

def word_dtw_distances(query,features,present,geometry,band=5):
    """Masked DTW over real shared observations, including support-hand dropouts."""
    q,qp,qg=query;t=np.asarray(features,np.float32);tp=np.asarray(present,bool)
    dot=np.stack([(t[:,:,hand,:].reshape(-1,t.shape[-1])@q[:,hand,:].T).reshape(len(t),t.shape[1],len(q)) for hand in range(2)],axis=-1)
    distance=np.maximum(np.sum(t*t,axis=-1)[:,:,None,:]+np.sum(q*q,axis=-1)[None,None,:,:]-2*dot,0)
    common=tp[:,:,None,:]&qp[None,None,:,:];counts=common.sum(axis=-1)
    cost=np.sum(distance*common,axis=-1)/np.maximum(counts,1)
    cost[counts==0]=2.
    # Missing observations reduce evidence without inventing a supporting hand.
    cost+=.05*np.sum(tp[:,:,None,:]!=qp[None,None,:,:],axis=-1)
    both=tp.all(axis=-1)[:,:,None]&qp.all(axis=-1)[None,None,:]
    cost+=np.sum((np.asarray(geometry)[:,:,None,:]-qg[None,None,:,:])**2,axis=-1)*both
    n,m=t.shape[1],len(q);previous=np.full((len(t),m+1),np.inf,np.float32);previous[:,0]=0
    for i in range(1,n+1):
        current=np.full_like(previous,np.inf)
        for j in range(max(1,i-band),min(m,i+band)+1):
            current[:,j]=cost[:,i-1,j-1]+np.minimum(np.minimum(previous[:,j],current[:,j-1]),previous[:,j-1])
        previous=current
    return previous[:,m]/max(n,m)

def class_max(values, template_labels, classes):
    result=np.full(classes,-np.inf,np.float32)
    np.maximum.at(result,template_labels,values)
    result[np.bincount(template_labels,minlength=classes)==0]=-1.
    return result

def relative_probabilities(scores, temperature=.08):
    logits = (np.asarray(scores,np.float32)-np.max(scores))/max(float(temperature),.01)
    exp = np.exp(np.clip(logits,-80,0))
    return exp/max(float(exp.sum()),1e-8)

def normalize_pose(pose, mean, std):
    pad = np.all(pose==0,axis=-1,keepdims=True)
    return np.where(pad,0,(pose-mean)/std).astype(np.float32)

def keras_custom_objects(tf):
    @tf.keras.utils.register_keras_serializable(package="SignVoice")
    class L2Normalize(tf.keras.layers.Layer):
        def call(self,inputs):
            return tf.math.l2_normalize(inputs,axis=-1)
    @tf.keras.utils.register_keras_serializable(package="SignVoice")
    class TemporalAttention(tf.keras.layers.Layer):
        def __init__(self,**kwargs):
            super().__init__(**kwargs);self.supports_masking=True
        def build(self,input_shape):
            self.w=self.add_weight(name="att_w",shape=(input_shape[-1],1),initializer="glorot_uniform",trainable=True)
            self.b=self.add_weight(name="att_b",shape=(1,),initializer="zeros",trainable=True)
        def call(self,inputs,mask=None):
            score=tf.squeeze(tf.matmul(inputs,self.w)+self.b,-1)
            if mask is not None:
                score=tf.where(mask,score,tf.cast(-1e9,score.dtype))
            return tf.reduce_sum(inputs*tf.nn.softmax(score,axis=1)[...,None],axis=1)
        def compute_output_shape(self,input_shape):
            return (input_shape[0],input_shape[-1])
        def compute_mask(self,inputs,mask=None):
            return None
    @tf.keras.utils.register_keras_serializable(package="SignVoice")
    class CosineClassifier(tf.keras.layers.Layer):
        def __init__(self,num_classes,scale=24.,**kwargs):
            super().__init__(**kwargs);self.num_classes=num_classes;self.scale=scale
        def build(self,input_shape):
            self.kernel=self.add_weight(shape=(int(input_shape[-1]),self.num_classes),initializer="glorot_uniform",trainable=True)
        def call(self,inputs):
            return tf.matmul(tf.math.l2_normalize(inputs,-1),tf.math.l2_normalize(self.kernel,0))*self.scale
        def get_config(self):
            return {**super().get_config(),"num_classes":self.num_classes,"scale":self.scale}
    return {"L2Normalize":L2Normalize,"L2NormalizationLayer":L2Normalize,
            "TemporalAttention":TemporalAttention,"CosineClassifier":CosineClassifier}

class StableDecision:
    """Time-based EMA, margin rejection, dwell and a short dynamic latch."""
    def __init__(self, labels, margin=.025, minimum=.55,dynamic_margin=.035,dynamic_minimum=.45,dynamic_labels=None,word_labels=None,static_dwell=.25):
        self.static_dwell=static_dwell
        self.word_labels=set(word_labels or [])
        self.dynamic_labels=set(DYNAMIC_LABELS if dynamic_labels is None else dynamic_labels)
        self.labels=list(labels);self.margin=margin;self.minimum=minimum
        self.dynamic_margin=dynamic_margin;self.dynamic_minimum=dynamic_minimum;self.word_policy={};self.reset()
    def reset(self):
        self.smoothed=None;self.last_time=None;self.candidate=None;self.since=0.
        self.confirmed=None;self.last_good=0.;self.latch_until=0.
    def update(self,scores,now,dynamic_ready=False):
        scores=np.asarray(scores,np.float32)
        readiness=np.asarray(dynamic_ready,bool)
        if readiness.ndim and readiness.shape!=scores.shape:raise ValueError('Readiness phải khớp số nhãn.')
        def ready_for(index):return bool(readiness) if readiness.ndim==0 else bool(readiness[index])
        raw_order=np.argsort(-scores);raw_top=int(raw_order[0])
        raw_gap=float(scores[raw_top]-scores[raw_order[1]]) if len(raw_order)>1 else 1.
        raw_word=self.labels[raw_top] in self.word_labels
        raw_minimum=float(self.word_policy.get('min_dynamic_score',self.dynamic_minimum)) if raw_word else self.dynamic_minimum
        raw_margin=float(self.word_policy.get('min_dynamic_margin',self.dynamic_margin)) if raw_word else self.dynamic_margin
        completed=(ready_for(raw_top) and self.labels[raw_top] in self.dynamic_labels
                   and scores[raw_top]>=raw_minimum and raw_gap>=raw_margin)
        if self.smoothed is None or completed:
            self.smoothed=scores.copy()
        else:
            alpha=1-np.exp(-max(now-self.last_time,0)/.16)
            self.smoothed += alpha*(scores-self.smoothed)
        self.last_time=now
        ranked=np.argsort(-self.smoothed)
        top=int(ranked[0]);gap=float(self.smoothed[top]-self.smoothed[ranked[1]]) if len(ranked)>1 else 1.
        dynamic=self.labels[top] in self.dynamic_labels
        minimum=self.dynamic_minimum if dynamic else self.minimum
        margin=self.dynamic_margin if dynamic else self.margin
        if self.labels[top] in self.word_labels:
            minimum=float(self.word_policy.get('min_dynamic_score' if dynamic else 'min_score',minimum))
            margin=float(self.word_policy.get('min_dynamic_margin' if dynamic else 'min_margin',margin))
        needs_sequence=dynamic or self.labels[top] in self.word_labels
        reliable=float(self.smoothed[top])>=minimum and gap>=margin and (not needs_sequence or ready_for(top))
        if reliable:
            if top != self.candidate:
                self.candidate=top;self.since=now
            dwell=(float(self.word_policy.get('word_dwell',.15)) if self.labels[top] in self.word_labels else 0. if dynamic else self.static_dwell)
            if not dynamic and self.labels[top] not in self.word_labels and gap>=max(.04,2*margin) and self.smoothed[top]>=.80:
                dwell=min(dwell,.10)
            if now-self.since+1e-6 >= dwell:
                locked=(self.confirmed is not None and self.labels[self.confirmed] in self.dynamic_labels
                        and now<self.latch_until and not dynamic)
                if not locked:
                    self.confirmed=top;self.last_good=now
                    if dynamic:self.latch_until=now+.35
        else:
            self.candidate=None
        if self.confirmed is not None and now>self.latch_until and now-self.last_good>.30:
            self.confirmed=None
        return self.confirmed,ranked,gap,reliable

class CompletedSignHold:
    """Keep a completed compound sign while its final pose is held."""
    def __init__(self):self.clear()
    def clear(self):self.anchor=None;self.last_hand=None;self.wrist=None;self.present=None
    def capture(self,pose,now,wrist=None):
        self.anchor=shape_descriptor(np.asarray(pose)[None])[0];self.last_hand=now
        self.wrist=None if wrist is None else np.asarray(wrist).reshape(2,4).copy()
        self.present=np.any(np.asarray(pose).reshape(2,21,3)!=0,axis=(1,2))
    def update(self,pose,now,wrist=None):
        if self.anchor is None:return False
        if not np.any(pose):
            if now-self.last_hand>.60:self.clear();return False
            return True
        desc=shape_descriptor(np.asarray(pose)[None])[0]
        if float(desc@self.anchor)<.97:self.clear();return False
        if self.wrist is not None and wrist is not None:
            current=np.asarray(wrist).reshape(2,4)
            common=self.present & np.any(np.asarray(pose).reshape(2,21,3)!=0,axis=(1,2))
            xy=np.stack([np.abs(current[:,0]),current[:,1]],axis=1)
            anchor_xy=np.stack([np.abs(self.wrist[:,0]),self.wrist[:,1]],axis=1)
            moved=np.linalg.norm(xy-anchor_xy,axis=1)>np.maximum(.04,.8*self.wrist[:,2])
            if np.any(common & moved):self.clear();return False
        self.last_hand=now;return True

class GestureBuffer:
    def __init__(self,max_seconds=6.,sample_hz=15,gap_seconds=.60,repair_gaps=False):
        self.gap_seconds=gap_seconds;self.repair_gaps=repair_gaps
        self.max_seconds=max_seconds;self.period=1/sample_hz;self.frames=deque();self.last_hand=None;self.next_sample=None
    def clear(self):
        self.frames.clear();self.last_hand=None;self.next_sample=None
    def add(self,pose,wrist,now,context=None):
        has_hand=bool(np.any(pose))
        if not has_hand and (self.last_hand is None or now-self.last_hand>self.gap_seconds):
            self.clear();return False
        if self.last_hand is not None and now-self.last_hand>self.gap_seconds:
            self.clear()
        if has_hand:self.last_hand=now
        if self.next_sample is not None and now<self.next_sample-.001:
            return False
        self.next_sample=now+self.period if self.next_sample is None else max(self.next_sample+self.period,now)
        anchor=np.zeros(4,np.float32) if context is None else np.asarray(context,np.float32)
        self.frames.append((now,np.asarray(pose,np.float32).copy(),np.asarray(wrist,np.float32).copy(),anchor.copy()))
        while self.frames and now-self.frames[0][0]>self.max_seconds:
            self.frames.popleft()
        return True  # Deliberately never clear because motion is large.
    def windows(self):
        if not self.frames:
            return []
        end=self.frames[-1][0];result=[];seen=set()
        for seconds in (.8,1.3,2.,3.,4.5,6.):
            selected=[f for f in self.frames if end-f[0]<=seconds]
            if sum(np.any(f[1]) for f in selected)>=6 and selected[-1][0]-selected[0][0]>=.35 and len(selected) not in seen:
                seen.add(len(selected))
                p=np.array([f[1] for f in selected]);w=np.array([f[2] for f in selected])
                observed=np.any(p.reshape(-1,2,21,3)!=0,axis=(2,3))
                if self.repair_gaps:p,w=repair_short_hand_gaps(p,w,[f[0] for f in selected])
                result.append((p,w,np.array([f[3] for f in selected]),np.array([f[0] for f in selected]),observed))
        return result

def build_template_arrays(clips, labels):
    static,static_y,temporal,temporal_y=[],[],[],[]
    prepared=[];contexts=[]
    for c in clips:
        p,w=prepare_sign_sequence(c['pose'],c['wrist'])
        if len(c['label'])==1 and c['label'] not in DYNAMIC_LABELS:p,w=single_hand_sequence(p,w)
        ids=np.flatnonzero(np.any(p!=0,axis=1))
        if len(ids)<3:raise ValueError('TRAIN clip has fewer than 3 observable hand frames: '+str(c.get('video_id',c['label'])))
        context=c.get('context')
        first,last=gesture_interval(p,w,context)
        cropped_context=context[first:last] if context is not None and len(context)==len(p) else None
        prepared.append(trim_gesture(p,w,True,keep_full_motion=True,context=context));contexts.append(cropped_context)
    # Each class contributes equal mass; long clips/large classes cannot dominate the metric.
    grouped=[np.concatenate([shape_descriptor(resample(p,SEQUENCE_STEPS))
             for c,(p,w) in zip(clips,prepared) if c['label']==label]) for label in labels]
    mean=np.mean([g.mean(axis=0) for g in grouped],axis=0)
    second=np.mean([(g*g).mean(axis=0) for g in grouped],axis=0)
    metric={'sequence_version':np.array(3,np.int64),'metric_mean':mean.astype(np.float32),
            'metric_std':np.maximum(np.sqrt(np.maximum(second-mean*mean,0)),.025).astype(np.float32)}
    for clip,(p,w) in zip(clips,prepared):
        label=str(clip['label']);c=labels.index(label)
        if label not in DYNAMIC_LABELS:
            views=representative_frames(p,w)
            static.extend(metric_descriptor(shape_descriptor(views),metric));static_y.extend([c]*len(views))
            # A static letter's preparation movement is not a legitimate two-step template.
            p=np.tile(views[0],(SEQUENCE_STEPS,1))
            w=np.tile(np.median(w,axis=0),(SEQUENCE_STEPS,1))
        temporal.append(sequence_descriptor(p,w,metric=metric));temporal_y.append(c)
    dim=shape_descriptor(np.zeros((1,126),np.float32)).shape[-1]
    location=[signing_location(p,w,context) for (p,w),context in zip(prepared,contexts)]
    hand_sequences=[word_hand_sequence(p,w,metric) for p,w in prepared]
    return {**metric,'static':np.asarray(static,np.float32).reshape(-1,dim),'static_y':np.asarray(static_y,np.int64),
            'temporal':np.asarray(temporal,np.float32),'temporal_y':np.asarray(temporal_y,np.int64),
            'template_location':np.array([row[0] for row in location],np.float32),
            'template_location_valid':np.array([row[1] for row in location],bool),
            'word_hand_features':np.array([row[0] for row in hand_sequences],np.float32),
            'word_hand_present':np.array([row[1] for row in hand_sequences],bool),
            'word_hand_geometry':np.array([row[2] for row in hand_sequences],np.float32),
            'template_hand_presence':np.array([np.all(np.any(p.reshape(-1,2,21,3)!=0,axis=(2,3)),axis=1).mean() for p,w in prepared],np.float32),
            'template_motion_evidence':np.array([motion_evidence(p,w) for p,w in prepared],np.float32)}

def finger_spread_features(pose):
    """Rotation/scale-invariant index-middle separation; no label assumptions."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    present=np.any(p!=0,axis=(2,3));hand=np.argmax(present,axis=1)
    p=p[np.arange(len(p)),hand]
    a=p[:,8]-p[:,5];b=p[:,12]-p[:,9]
    angle=np.arccos(np.clip(np.sum(unit(a)*unit(b),axis=1),-1.,1.))/np.pi
    palm_width=np.linalg.norm(p[:,5]-p[:,17],axis=1)
    gap=np.linalg.norm(p[:,8]-p[:,12],axis=1)/np.maximum(palm_width,1e-6)
    result=np.stack([angle,gap],axis=1).astype(np.float32)
    result[present.sum(axis=1)!=1]=np.nan
    result[palm_width<1e-4]=np.nan
    return result

def fit_finger_spread_refiner(train_clips,labels):
    """One vote per TRAIN video; validation/test never define the geometry."""
    groups=[]
    for name in ('u','v'):
        values=[]
        for clip in train_clips:
            if clip['label']!=name:continue
            value=finger_spread_features(representative_frames(clip['pose'],clip['wrist']))
            value=value[np.isfinite(value).all(axis=1)]
            if len(value):values.append(np.median(value,axis=0))
        groups.append(np.asarray(values,np.float32).reshape(-1,2))
    counts=[len(g) for g in groups]
    result={'revision':'finger_spread_v1','labels':['u','v'],'enabled':False,
            'train_videos':counts,'penalty_per_distance':.10,'max_penalty':.20,
            'max_distance':3.,'candidate_gap':.12,'minimum_score':.55}
    if not all(name in labels for name in ('u','v')) or min(counts)<2:
        result['reason']='Cần ít nhất hai video train hợp lệ cho mỗi nhãn U/V.';return result
    centers=np.array([np.median(g,axis=0) for g in groups],np.float32)
    residual=np.concatenate([g-center for g,center in zip(groups,centers)])
    scale=np.maximum(np.sqrt(np.mean(residual*residual,axis=0)),[.025,.12]).astype(np.float32)
    separation=float(np.linalg.norm((centers[0]-centers[1])/scale))
    result.update(centers=centers.tolist(),scale=scale.tolist(),separation=separation,
                  open_label=('u','v')[int(np.argmax(centers[:,1]))])
    # Overlapping/inconsistent train groups cannot justify a forced U/V rule.
    correct=[np.argmin(np.linalg.norm((g[:,None]-centers[None])/scale,axis=2),axis=1)==i
             for i,g in enumerate(groups)]
    result['train_consistency']=float(np.mean([c.mean() for c in correct]))
    result['enabled']=bool(separation>=2. and all(c.all() for c in correct))
    result['reason']='TRAIN geometry separates U/V.' if result['enabled'] else 'Mẫu train U/V chồng lấn; không ép nhãn.'
    return result

def refine_finger_spread(scores,current,labels,config,active):
    """Only lower contradicted U/V scores; never inflate confidence."""
    rule=config.get('finger_spread_refiner',{})
    if not rule.get('enabled',False):return scores
    indices=[labels.index(name) for name in rule['labels']]
    if not np.all(active[indices]):return scores
    current_scores=np.asarray(scores,np.float32)
    candidate=float(current_scores[indices].max())
    if candidate<float(rule['minimum_score']) or candidate<current_scores[active].max()-float(rule['candidate_gap']):return scores
    feature=finger_spread_features(np.asarray(current)[None])[0]
    if not np.isfinite(feature).all():return scores
    centers=np.asarray(rule['centers'],np.float32);scale=np.asarray(rule['scale'],np.float32)
    distances=np.linalg.norm((feature-centers)/scale,axis=1)
    if distances.min()>float(rule['max_distance']):return scores
    penalty=np.minimum(float(rule['max_penalty']),float(rule['penalty_per_distance'])*(distances-distances.min()))
    result=current_scores.copy();result[indices]-=penalty
    return result


def finger_context_features(pose):
    """Spread, absolute finger direction and four finger extension ratios."""
    raw=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    present=np.any(raw!=0,axis=(2,3));p=raw[np.arange(len(raw)),np.argmax(present,axis=1)]
    direction=np.concatenate([unit(p[:,8]-p[:,5]),unit(p[:,12]-p[:,9])],axis=1)
    extension=[]
    for base in (5,9,13,17):
        length=np.linalg.norm(np.diff(p[:,base:base+4],axis=1),axis=2).sum(axis=1)
        extension.append(np.linalg.norm(p[:,base+3]-p[:,base],axis=1)/np.maximum(length,1e-6))
    return np.concatenate([finger_spread_features(pose),direction,np.stack(extension,axis=1)],axis=1)

def recover_template_poses(descriptor,arrays):
    """Invert TRAIN whitening on the unit sphere; raw coordinate block keeps geometry."""
    v=np.asarray(descriptor,np.float64)*np.asarray(arrays['metric_std'],np.float64)
    mean=np.asarray(arrays['metric_mean'],np.float64)
    a=np.sum(v*v,axis=1);b=2*np.sum(v*mean,axis=1);c=float(np.sum(mean*mean)-1.)
    scale=(-b+np.sqrt(np.maximum(b*b-4*a*c,0)))/(2*np.maximum(a,1e-12))
    recovered=(v*scale[:,None]+mean)[:,:126].astype(np.float32)
    hands=recovered.reshape(-1,2,21,3)
    hands[np.linalg.norm(hands.reshape(-1,2,63),axis=2)<1e-5]=0
    return recovered

def single_hand_sequence(pose,wrist):
    """Use the nearer/larger observed hand for a one-hand alphabet or digit."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    w=np.asarray(wrist,np.float32).reshape(-1,2,4)
    valid=np.any(p!=0,axis=(2,3));choice=np.argmax(np.where(valid,w[:,:,2],-1.),axis=1)
    out=np.zeros_like(p);out_w=np.zeros_like(w);ids=np.arange(len(p))
    out[:,1]=p[ids,choice];out_w[:,1]=w[ids,choice]
    return out.reshape(-1,126),out_w.reshape(-1,8)

def finger_anatomy_features(pose):
    """Five fingers: joint bends, extension, reach and pairwise tip gaps."""
    p=np.asarray(pose,np.float32).reshape(-1,2,21,3)
    valid=np.any(p!=0,axis=(2,3));p=p[np.arange(len(p)),np.argmax(valid,axis=1)]
    palm=np.maximum(np.median(np.linalg.norm(p[:,[5,9,13,17]]-p[:,:1],axis=-1),axis=1),1e-6)
    angles=[];extension=[];reach=[];gaps=[]
    for base in (1,5,9,13,17):
        joint=[0,base,base+1,base+2,base+3]
        for j in (1,2,3):
            a,b,c=(p[:,joint[k]] for k in (j-1,j,j+1))
            angles.append(np.arccos(np.clip(np.sum(unit(a-b)*unit(c-b),axis=-1),-1.,1.))/np.pi)
        bones=np.linalg.norm(np.diff(p[:,base:base+4],axis=1),axis=-1).sum(axis=1)
        extension.append(np.linalg.norm(p[:,base+3]-p[:,base],axis=-1)/np.maximum(bones,1e-6))
        reach.append(np.linalg.norm(p[:,base+3]-p[:,0],axis=-1)/palm)
    tips=(4,8,12,16,20)
    for i,a in enumerate(tips):
        for b in tips[i+1:]:gaps.append(np.linalg.norm(p[:,a]-p[:,b],axis=-1)/palm)
    result=np.stack(angles+extension+reach+gaps,axis=1).astype(np.float32)
    result[valid.sum(axis=1)!=1]=np.nan
    return result

def fit_digit_anatomy(arrays,labels):
    """Derive all references from stored TRAIN templates, including singletons."""
    if 'static' not in arrays:return {'enabled':False}
    poses=recover_template_poses(arrays['static'],arrays)
    f=finger_anatomy_features(poses);y=arrays['static_y']
    valid=np.isfinite(f).all(axis=1)&np.isin(y,[i for i,name in enumerate(labels) if name.isdigit()])
    f,y=f[valid],y[valid]
    ids=np.unique(y)
    if len(ids)<2:return {'enabled':False}
    residual=np.concatenate([f[y==i]-np.median(f[y==i],axis=0) for i in ids])
    floor=np.array([.07]*15+[.08]*5+[.18]*5+[.18]*10,np.float32)
    scale=np.maximum(np.sqrt(np.mean(residual*residual,axis=0)),floor)
    return dict(enabled=True,revision='five_fingers_v1',features=f.tolist(),feature_y=y.tolist(),scale=scale.tolist(),
                penalty=.16,max_penalty=.30,max_distance=2.5)

def refine_digit_anatomy(scores,current,labels,rule,active):
    if not rule.get('enabled'):return scores
    feature=finger_anatomy_features(np.asarray(current)[None])[0]
    if not np.isfinite(feature).all():return scores
    f=np.asarray(rule['features'],np.float32);y=np.asarray(rule['feature_y'],np.int64)
    distance=np.sqrt(np.mean(((f-feature)/np.asarray(rule['scale'],np.float32))**2,axis=1))
    by_class=class_max(-distance,y,len(labels));valid=np.isin(np.arange(len(labels)),y)&active
    if not valid.any():return scores
    nearest=float((-by_class)[valid].min())
    if nearest>float(rule['max_distance']):return scores
    result=np.asarray(scores,np.float32).copy()
    result[valid]-=np.minimum(float(rule['max_penalty']),float(rule['penalty'])*np.maximum(-by_class[valid]-nearest,0))
    return result

def fit_finger_context_refiner(arrays,labels):
    names=[name for name in ('u','v','h','r','2') if name in labels]
    if not all(name in names for name in ('u','v')):return {'enabled':False}
    pose=recover_template_poses(arrays['static'],arrays)
    features=finger_context_features(pose);indices=arrays['static_y']
    valid=np.isfinite(features).all(axis=1)&np.isin(indices,[labels.index(name) for name in names])
    features=features[valid];indices=indices[valid]
    groups=[features[indices==labels.index(name)] for name in names]
    if any(len(g)==0 for g in groups):return {'enabled':False}
    residual=[g-np.median(g,axis=0) for g in groups]
    second=np.mean([np.mean(r*r,axis=0) for r in residual],axis=0)
    scale=np.maximum(np.sqrt(second),[.025,.12]+[.15]*6+[.07]*4).astype(np.float32)
    start_pose=recover_template_poses(arrays['temporal'][:,0,:len(arrays['metric_mean'])],arrays)
    start=finger_context_features(start_pose);start_valid=np.isfinite(start).all(axis=1)
    endpoint_pose=recover_template_poses(arrays['temporal'][:,-1,:len(arrays['metric_mean'])],arrays)
    endpoint=finger_context_features(endpoint_pose);endpoint_valid=np.isfinite(endpoint).all(axis=1)
    return {'enabled':True,'revision':'uv_context_v1','labels':names,
            'features':features.tolist(),'feature_labels':[labels[int(i)] for i in indices],
            'scale':scale.tolist(),'start_features':np.nan_to_num(start).tolist(),
            'start_valid':start_valid.tolist(),'endpoint_features':np.nan_to_num(endpoint).tolist(),
            'endpoint_valid':endpoint_valid.tolist(),'max_distance':4.,
            'static_penalty':.10,'max_static_penalty':.20,
            'endpoint_penalty':.10,'max_endpoint_penalty':.35,'start_tolerance':4.,'endpoint_tolerance':3.}

def static_anatomy_features(pose):
    """Finger bends, thumb contacts and spread; independent of the class name."""
    return np.concatenate([finger_anatomy_features(pose),finger_spread_features(pose)],axis=1)

def fit_static_anatomy(arrays,labels):
    if 'static' not in arrays:return {'enabled':False}
    poses=recover_template_poses(arrays['static'],arrays)
    features=static_anatomy_features(poses);y=arrays['static_y']
    valid=np.isfinite(features).all(axis=1)&np.array([len(labels[i])==1 and labels[i] not in COMPOUND_LETTER_LABELS for i in y])
    f,y=features[valid],y[valid];ids=np.unique(y)
    if len(ids)<2:return {'enabled':False}
    variance=np.mean([np.mean((f[y==i]-np.median(f[y==i],axis=0))**2,axis=0) for i in ids],axis=0)
    scale=np.maximum(np.sqrt(variance),[.07]*15+[.08]*5+[.18]*5+[.18]*10+[.025,.12])
    return dict(enabled=True,revision='all_static_anatomy_v1',features=f.tolist(),feature_y=y.tolist(),scale=scale.tolist(),
                penalty=.22,tolerance=.20,max_penalty=.50,max_distance=2.5)

def refine_static_anatomy(scores,current,rule,active):
    if not rule.get('enabled'):return scores
    feature=static_anatomy_features(np.asarray(current)[None])[0]
    if not np.isfinite(feature).all():return scores
    y=np.asarray(rule['feature_y'],np.int64)
    distance=np.sqrt(np.mean(((np.asarray(rule['features'],np.float32)-feature)/np.asarray(rule['scale'],np.float32))**2,axis=1))
    by_class=-class_max(-distance,y,len(scores));available=np.isin(np.arange(len(scores)),y);valid=available&active
    if not valid.any():return scores
    nearest=float(by_class[available].min())
    if nearest>float(rule['max_distance']):return scores
    result=np.asarray(scores,np.float32).copy()
    result[valid]-=np.minimum(float(rule['max_penalty']),float(rule['penalty'])*np.maximum(by_class[valid]-nearest-float(rule['tolerance']),0))
    return result

def finger_context_distances(current,config):
    rule=config.get('finger_context_refiner',{})
    if not rule.get('enabled',False):return None
    feature=finger_context_features(np.asarray(current)[None])[0]
    if not np.isfinite(feature).all():return None
    scale=np.asarray(rule['scale'],np.float32)
    distances=np.linalg.norm((np.asarray(rule['features'],np.float32)-feature)/scale,axis=1)
    by_class={name:float(distances[np.asarray(rule['feature_labels'])==name].min()) for name in rule['labels']}
    return rule,feature,by_class

def refine_finger_context_static(scores,current,labels,config,active):
    info=finger_context_distances(current,config)
    if info is None:return scores
    rule,feature,distances=info
    if not all(active[labels.index(name)] for name in ('u','v')):return scores
    candidate=max(float(scores[labels.index(name)]) for name in ('u','v'))
    if candidate<.55 or candidate<float(np.max(scores[active]))-.12:return scores
    distances={name:distance for name,distance in distances.items() if active[labels.index(name)]}
    nearest=min(distances.values())
    if nearest>float(rule['max_distance']):return scores
    result=np.asarray(scores,np.float32).copy()
    for name,distance in distances.items():
        result[labels.index(name)]-=min(float(rule['max_static_penalty']),float(rule['static_penalty'])*max(0.,distance-nearest))
    return result

def refine_finger_context_endpoints(similarity,current,shape,labels,arrays,config,start_pose,active):
    """Reject compound endpoints anatomically inconsistent with a clear U/V pose."""
    info=finger_context_distances(current,config)
    if info is None:return similarity
    rule,feature,distances=info
    winner=labels[int(np.argmax(np.where(active,shape,-1.)))]
    if winner not in ('u','v') or shape[labels.index(winner)]<.75:return similarity
    nearest=min(distances['u'],distances['v'])
    if nearest>float(rule['max_distance']):return similarity
    endpoints=np.asarray(rule['endpoint_features'],np.float32)
    gap=np.linalg.norm((endpoints-feature)/np.asarray(rule['scale'],np.float32),axis=1)-nearest
    dynamic=np.isin(np.asarray(labels)[arrays['temporal_y']],list(config.get('compound_letter_labels',COMPOUND_LETTER_LABELS)))
    valid=np.asarray(rule['endpoint_valid'],bool)&dynamic
    consistent=np.asarray(rule['endpoint_valid'],bool)&(gap<=float(rule['endpoint_tolerance']))
    mismatch=np.maximum(gap,0)
    start=finger_context_features(np.asarray(start_pose)[None])[0]
    if np.isfinite(start).all():
        start_distance=np.linalg.norm((np.asarray(rule['start_features'],np.float32)-start)/np.asarray(rule['scale'],np.float32),axis=1)
        usable=np.asarray(rule['start_valid'],bool)
        mismatch[usable]+=np.maximum(start_distance[usable]-float(rule['start_tolerance']),0)
        consistent &= usable&(start_distance<=float(rule['start_tolerance']))
    result=np.asarray(similarity,np.float32).copy()
    result[valid]-=np.minimum(float(rule['max_endpoint_penalty']),float(rule['endpoint_penalty'])*mismatch[valid])
    result[dynamic&~consistent]=-1.
    return result


WORD_TEMPORAL_VERSION='word_shape_motion_tcn_v1'
WORD_TEMPORAL_STEPS=48

def word_temporal_features(pose,wrist,context=None,times=None,length=WORD_TEMPORAL_STEPS):
    """Hand shape + real wrist translation/speed + face-relative position/masks."""
    pose=np.asarray(pose,np.float32);wrist=np.asarray(wrist,np.float32);n=len(pose)
    if n<2:raise ValueError('Word sequence needs at least two frames.')
    t=np.arange(n,dtype=np.float64)/15 if times is None else np.asarray(times,np.float64)
    if t.shape!=(n,) or not np.isfinite(t).all() or np.any(np.diff(t)<=0):raise ValueError('Invalid word timestamps.')
    anchor=np.zeros((n,4),np.float32) if context is None else np.asarray(context,np.float32)
    if anchor.shape!=(n,4):raise ValueError('Word context must align with hand frames.')
    p,w=prepare_sign_sequence(pose,wrist)
    p,w=resample_hand_sequence(p,w,length)
    w=w.reshape(length,2,4);present=np.any(p.reshape(length,2,21,3)!=0,axis=(2,3))
    grid=np.linspace(0,n-1,length);nearest=np.rint(grid).astype(int)
    c=resample(anchor,length);valid=(anchor[nearest,3]>0)&(c[:,2]>.02)
    clock=np.interp(grid,np.arange(n),t);dt=np.maximum(np.diff(clock,prepend=clock[0]),1e-3)
    xy=w[:,:,:2].copy();xy[:,:,0]=np.abs(xy[:,:,0])
    location=np.zeros((length,2,3),np.float32);speed=np.zeros_like(location)
    for hand in range(2):
        ids=np.flatnonzero(present[:,hand]);scale=max(float(np.median(w[ids,hand,2])) if len(ids) else .015,.015)
        good=valid&present[:,hand]
        location[good,hand,:2]=np.clip((xy[good,hand]-c[good,:2])/c[good,2,None],-6,6)/6
        location[good,hand,2]=np.clip(w[good,hand,2]/c[good,2],0,6)/6
        pairs=present[1:,hand]&present[:-1,hand]
        velocity=np.diff(xy[:,hand],axis=0)/scale/dt[1:,None]
        radial=np.diff(np.log(np.maximum(w[:,hand,2],.015)))/dt[1:]
        speed[1:,hand,:2]=np.where(pairs[:,None],np.clip(velocity,-8,8)/8,0)
        speed[1:,hand,2]=np.where(pairs,np.clip(radial,-4,4)/4,0)
    geometry=np.zeros((length,3),np.float32);both=present.all(axis=1)
    scale=np.maximum(w[:,:,2].mean(axis=1),.015)
    geometry[both,:2]=np.clip((xy[both,1]-xy[both,0])/scale[both,None],-6,6)/6
    geometry[both,2]=np.clip(np.log(np.maximum(w[both,1,2],.015)/np.maximum(w[both,0,2],.015)),-2,2)/2
    duration=np.full((length,1),np.clip(np.log1p(t[-1]-t[0])/np.log(7),0,1),np.float32)
    motion=np.concatenate([location.reshape(length,6),speed.reshape(length,6),present.astype(np.float32),valid[:,None].astype(np.float32),geometry,duration],axis=1)
    if not np.isfinite(p).all() or not np.isfinite(motion).all():raise ValueError('Nonfinite temporal word features.')
    return p.astype(np.float32),motion.astype(np.float32)

def build_word_temporal_model(tf,classes):
    """Upgraded two-stream TCN + GRU (64 filters, 96 GRU, 128 Dense) for higher word capacity."""
    layers=tf.keras.layers
    shape=layers.Input((WORD_TEMPORAL_STEPS,126),name='hand_shape')
    motion=layers.Input((WORD_TEMPORAL_STEPS,19),name='motion_context')
    streams=[]
    for source,name in ((shape,'shape'),(motion,'motion')):
        x=layers.Conv1D(64,1,activation='relu',name=name+'_projection')(source)
        for dilation in (1,2,4):
            residual=x
            x=layers.Conv1D(64,3,padding='causal',dilation_rate=dilation,activation='relu',kernel_regularizer=tf.keras.regularizers.l2(1e-4))(x)
            x=layers.LayerNormalization()(x);x=layers.Dropout(.12)(x)
            x=layers.Add()([x,residual])
        streams.append(x)
    x=layers.Concatenate()(streams)
    x=layers.GRU(96,dropout=.12,recurrent_dropout=0,use_cudnn=False)(x)
    x=layers.Dense(128,activation='relu',kernel_regularizer=tf.keras.regularizers.l2(1e-4))(x)
    x=layers.Dropout(.15)(x)
    return tf.keras.Model([shape,motion],layers.Dense(classes,activation='softmax',name='word_or_background')(x),name='word_shape_motion_tcn')

WORD_RUNTIME_VERSION='word_windows_evidence_v3'

class TemporalWordHead:
    def __init__(self,labels,config,infer=None,embed=None,centers=None,mean=None,std=None,probability_fusion=None):
        self.config=config;self.infer=infer;self.labels=list(labels)
        self.probability_fusion=probability_fusion
        self.embed=embed;self.centers=centers;self.mean=mean;self.std=std
        if config.get('version')!=WORD_TEMPORAL_VERSION:raise ValueError('Unknown word temporal feature version.')
        self.names=config['labels'];self.indices=np.array([self.labels.index(name) for name in self.names],int)
        self.word_centers=None if centers is None else np.asarray(centers,np.float32)[self.indices]
        self.pair_required=np.array([bool(config.get('requires_pair',{}).get(name,False)) for name in self.names])
        self.dynamic=np.isin(self.names,config.get('dynamic_labels',self.names))
        self.policy={'min_score':.8,'min_dynamic_score':.8,'min_margin':.2,'min_dynamic_margin':.2,'word_dwell':.3,'embed_weight':0.}
        self.policy.update(config.get('policy',{}))
        weight=float(self.policy.get('embed_weight',0.))
        if not np.isfinite(weight) or not 0.<=weight<=1.:raise ValueError('embed_weight must be in [0,1]')
        if weight>0 and (embed is None or self.word_centers is None or mean is None or std is None):
            raise ValueError('Embedding comparison requires the matching encoder, prototypes and normalizers')
        if weight<1 and infer is None:raise ValueError('TCN/fusion requires a verified word model')
        if self.word_centers is not None and not np.isfinite(self.word_centers).all():raise ValueError('Invalid word prototypes')
        self.inference_coverage=float(config.get('inference_min_observed_coverage',.35))
        self.confirmation_coverage=float(config.get('confirmation_min_observed_coverage',.65))
        self.last_diagnostics={}
    def predict(self,candidates):
        size=len(self.labels);scores=np.full(size,-1.,np.float32);ready=np.zeros(size,bool)
        batches=[];embed_batches=[];masks=[];variants=[];coverage=[];observations=[];seen={}
        diagnostic=dict(windows=len(candidates),short_windows=0,low_observation_windows=0,inference_ran=False)
        self.last_diagnostics=diagnostic
        for candidate in candidates:
            p,w=candidate[:2];context=candidate[2] if len(candidate)>2 else None
            clock=candidate[3] if len(candidate)>3 else np.arange(len(p))/15
            observed=candidate[4] if len(candidate)>4 else np.any(np.asarray(p).reshape(-1,2,21,3)!=0,axis=(2,3))
            # Training uses the active interval. Apply the same boundary trimming
            # before coverage, duration and physical-speed features at inference.
            # Preserve all internal phases and the original observation mask.
            try:
                fixed_p,fixed_w,observed=prepare_sign_sequence(p,w,observed)
                first,last=gesture_interval(fixed_p,fixed_w,context)
            except ValueError:
                continue
            p,w=fixed_p[first:last],fixed_w[first:last]
            context=None if context is None else np.asarray(context)[first:last]
            clock=np.asarray(clock)[first:last]
            observed=np.asarray(observed,bool)[first:last].copy()
            observed &= np.any(p.reshape(-1,2,21,3)!=0,axis=(2,3))
            if len(p)<6 or clock[-1]-clock[0]<.35:
                diagnostic['short_windows']+=1;continue
            measured=float(observed.any(axis=1).mean())
            if measured<self.inference_coverage:
                diagnostic['low_observation_windows']+=1;continue
            features=word_temporal_features(p,w,context,clock)
            pose40=resample(p)
            pair=observed.all(axis=1)
            # A support hand can disappear in the final phase of a two-hand sign.
            # Require measured pair evidence in the sign, not only its last second.
            has_pair=pair.sum()>=3 and pair.mean()>=.1
            shape_motion,path_motion=motion_evidence(p,w)
            has_motion=shape_motion>=.04 or path_motion>=.025
            mask=(~self.pair_required|has_pair)&(~self.dynamic|has_motion)
            # Suffix windows often trim to the identical active interval. Run that
            # input only once; retain different measured masks as distinct evidence.
            key=(features[0].tobytes(),features[1].tobytes(),mask.tobytes(),observed.tobytes())
            if key in seen:
                variants[seen[key]]=0
                continue
            seen[key]=len(batches);batches.append(features);embed_batches.append(pose40);masks.append(mask);variants.append(0);coverage.append(measured);observations.append(int(observed.any(axis=1).sum()))
            if has_pair:
                # Slot identities are tracker bookkeeping. Compare the same
                # measured two-hand sign with the two slots exchanged, keeping
                # positions, velocity and relative geometry consistent.
                swapped_p=features[0].reshape(-1,2,63)[:,::-1].reshape(-1,126).copy()
                swapped_pose40=pose40.reshape(-1,2,63)[:,::-1].reshape(-1,126).copy()
                swapped_m=features[1].copy()
                swapped_m[:,:6]=features[1][:,:6].reshape(-1,2,3)[:,::-1].reshape(-1,6)
                swapped_m[:,6:12]=features[1][:,6:12].reshape(-1,2,3)[:,::-1].reshape(-1,6)
                swapped_m[:,12:14]=features[1][:,12:14][:,::-1]
                swapped_m[:,15:18]*=-1
                swap_key=(swapped_p.tobytes(),swapped_m.tobytes(),mask.tobytes(),observed[:,::-1].tobytes())
                if swap_key not in seen:
                    seen[swap_key]=len(batches);batches.append((swapped_p,swapped_m));embed_batches.append(swapped_pose40);masks.append(mask);variants.append(1);coverage.append(measured);observations.append(int(observed.any(axis=1).sum()))
        if not batches:return scores,ready
        has_embed=(self.embed is not None and self.word_centers is not None and self.mean is not None and self.std is not None)
        embed_weight=float(self.policy.get('embed_weight',0.)) if has_embed else 0.
        background_rejected=np.zeros(len(batches),bool)
        if self.infer is not None and embed_weight<1.:
            probabilities=np.asarray(self.infer([np.stack([x[0] for x in batches]),np.stack([x[1] for x in batches])]),np.float32)
            if probabilities.shape!=(len(batches),len(self.names)+1) or not np.isfinite(probabilities).all():raise ValueError('Word model output has invalid shape/values.')
            if np.any(probabilities<0) or np.any(probabilities>1) or not np.allclose(probabilities.sum(axis=1),1.,atol=1e-3):
                raise ValueError('TCN must return a softmax distribution')
            # A trained background winner cannot be overwritten by prototype similarity.
            background_rejected=probabilities[:,-1]>=probabilities[:,:-1].max(axis=1)
        else:
            probabilities=np.zeros((len(batches),len(self.names)+1),np.float32)
            embed_weight=1. if has_embed else 0.
        if embed_weight>0.:
            eb=np.stack(embed_batches)
            eb_swap=eb.reshape(len(eb),40,2,63)[:,:,::-1].reshape(len(eb),40,126)
            both_vecs=unit(self.embed(normalize_pose(np.concatenate([eb,eb_swap],axis=0),self.mean,self.std)))
            if both_vecs.shape!=(2*len(eb),self.word_centers.shape[1]) or not np.isfinite(both_vecs).all():
                raise ValueError('Invalid embedding output')
            s0=np.clip(both_vecs[:len(eb)]@self.word_centers.T,0.,1.).astype(np.float32)
            s1=np.clip(both_vecs[len(eb):]@self.word_centers.T,0.,1.).astype(np.float32)
            embed_scores=np.maximum(s0,s1)
            if self.probability_fusion is not None:
                probabilities=self.probability_fusion(probabilities,embed_scores)
                background_rejected=probabilities[:,-1]>=probabilities[:,:-1].max(axis=1)
            else:
                word_probs=(1.-embed_weight)*probabilities[:,:-1]+embed_weight*embed_scores
                bg_probs=probabilities[:,-1:].copy()  # Keep the full trained rejection evidence.
                probabilities=np.concatenate([word_probs,bg_probs],axis=1)
        diagnostic.update(inference_ran=True,inference_windows=len(batches),embed_weight=embed_weight,
            score_kind='probability_ensemble' if self.probability_fusion is not None else ('softmax' if embed_weight==0 else 'uncalibrated_cosine_fusion'),
            background_detector_used=embed_weight<1.,tcn_background_veto_windows=int(background_rejected.sum()))
        # Keep the original model winner and competitors for rejection. Masking
        # an unsupported class must never promote a lower-probability word.
        raw_order=np.argsort(-probabilities,axis=1)
        raw_top=raw_order[:,0]
        raw_margin=probabilities[np.arange(len(batches)),raw_top]-probabilities[np.arange(len(batches)),raw_order[:,1]]
        raw_word=raw_top<len(self.names)
        raw_supported=raw_word & ~background_rejected & np.asarray(masks)[np.arange(len(batches)),np.minimum(raw_top,len(self.names)-1)]
        # Background is a trained rejection class, never a displayed word.
        words=probabilities[:,:-1].copy();words[~np.asarray(masks)]=-1.
        words[background_rejected]=-1.
        words[probabilities[:,-1]>=probabilities[:,:-1].max(axis=1)]=-1.
        # Choose one coherent window; do not mix unrelated per-class window peaks.
        order=np.argsort(-words,axis=1)
        second=words[np.arange(len(words)),order[:,1]] if words.shape[1]>1 else probabilities[:,-1]
        # A masked class has score -1, not probability -1. Background remains a
        # real competing class when computing the window's margin.
        second=np.maximum(second,probabilities[:,-1])
        gap=words[np.arange(len(words)),order[:,0]]-second
        quality=words.max(axis=1)+.25*gap
        row_dynamic=self.dynamic[np.minimum(raw_top,len(self.names)-1)]
        required_score=np.where(row_dynamic,self.policy['min_dynamic_score'],self.policy['min_score'])
        required_margin=np.where(row_dynamic,self.policy['min_dynamic_margin'],self.policy['min_margin'])
        eligible=(words.max(axis=1)>=required_score)&(gap>=required_margin)
        eligible &= raw_supported & (raw_margin>=required_margin) & (np.asarray(coverage)>=self.confirmation_coverage) & (np.asarray(observations)>=6)
        primary_eligible=eligible&(np.asarray(variants)==0)
        if primary_eligible.any():eligible=primary_eligible
        # A below-threshold window must not hide another window satisfying both
        # existing score/margin thresholds. Final time-based dwell is unchanged.
        best=int(np.argmax(np.where(eligible,quality,-np.inf))) if eligible.any() else int(np.argmax(quality))
        scores[self.indices]=words[best]
        # Only a fully supported current winner can confirm. The display may
        # still show other scores as tentative evidence when confidence is low.
        winner=int(raw_top[best]);reasons=[]
        if background_rejected[best] or not raw_word[best]:reasons.append('background')
        elif not raw_supported[best]:reasons.append('pair_or_motion')
        if coverage[best]<self.confirmation_coverage:reasons.append('hand_coverage')
        if observations[best]<6:reasons.append('too_few_observations')
        if probabilities[best,winner]<required_score[best]:reasons.append('score')
        if raw_margin[best]<required_margin[best]:reasons.append('margin_with_background')
        if not reasons and winner<len(self.names):ready[self.indices[winner]]=True
        diagnostic.update(selected_word=self.names[winner] if winner<len(self.names) else '__background__',
            score=float(probabilities[best,winner]),background=float(probabilities[best,-1]),
            margin_with_background=float(raw_margin[best]),measured_hand_coverage=float(coverage[best]),
            measured_hand_frames=int(observations[best]),
            swapped=bool(variants[best]),confirmation_ready=not reasons,rejection_reasons=reasons)
        return scores,ready

class HybridRecognizer:
    def __init__(self,labels,arrays,config,embed=None,centers=None,mean=None,std=None):
        self.labels=list(labels);self.arrays=arrays;self.config=config;self.embed=embed
        self.centers=centers;self.mean=mean;self.std=std
        self.word_head=None
        self.dynamic_labels=set(config.get('dynamic_labels',DYNAMIC_LABELS))
        self.dynamic=np.isin(self.labels,list(self.dynamic_labels));self.set_mode('all')
        self.digit_anatomy=config.get('digit_anatomy_refiner') or fit_digit_anatomy(arrays,self.labels)
        self.static_anatomy=config.get('static_anatomy_refiner') or fit_static_anatomy(arrays,self.labels)
        self.shape_dim=len(arrays.get('metric_mean',[]));self.motion_v2=int(np.asarray(arrays.get('sequence_version',1)).item())>=2
        self.two_hand_templates=np.array([],np.int64)
        if arrays.get('temporal') is not None:
            template=arrays['temporal']
            self.required_shape_motion=np.linalg.norm(template[:,:,:self.shape_dim]-template[:,:1,:self.shape_dim],axis=2).max(axis=1)
            self.required_path_motion=np.linalg.norm(template[:,:,self.shape_dim:self.shape_dim+4],axis=2).max(axis=1)
            if config.get('retain_both_hands'):
                recovered=recover_template_poses(template[:,:,:self.shape_dim].reshape(-1,self.shape_dim),arrays)
                presence=np.any(recovered.reshape(len(template),SEQUENCE_STEPS,2,21,3)!=0,axis=(3,4))
                self.two_hand_templates=np.flatnonzero(np.all(presence,axis=2).sum(axis=1)>=max(3,int(.15*SEQUENCE_STEPS)))

    def set_mode(self,mode):
        if mode not in ('all','letters','digits','words'):raise ValueError('Sai chế độ nhận diện.')
        self.mode=mode
        self._dtw_banks={}
        self.active=np.array([mode=='all' or (name.isdigit() if mode=='digits' else (len(name)==1 and not name.isdigit()) if mode=='letters' else len(name)>1) for name in self.labels])
        if not self.active.any():raise ValueError('Bộ model không có nhãn cho chế độ '+mode)
    def _dtw_bank(self,ids):
        # Templates never change during a session. Reuse the contiguous bank
        # and squared norms across suffix windows instead of copying it each time.
        key=ids.tobytes()
        if key not in self._dtw_banks:
            source=self.arrays['temporal']
            bank=source if np.array_equal(ids,np.arange(len(source))) else source[ids]
            self._dtw_banks[key]=(bank,np.sum(bank*bank,axis=2))
        return self._dtw_banks[key]
    def setting(self,key,default):
        # Use the word-specific policy; config reports whether independent
        # validation was available or conservative defaults were retained.
        if self.mode=='words':policy={'prediction_interval':.25,**self.config.get('word_policy',{})}
        elif self.mode=='digits':policy={'neural_weight':0.,'prediction_interval':.08,'static_dwell':.15,**self.config.get('digit_policy',{})}
        else:policy={'prediction_interval':.10 if self.mode=='letters' else .25}
        return policy.get(key,self.config.get(key,default))
    def domain_collision(self,scores):
        if self.mode!='all':return None
        top=int(np.argmax(scores))
        if self.dynamic[top] or len(self.labels[top])!=1:return None
        digits=np.array([i for i,name in enumerate(self.labels) if len(name)==1 and name.isdigit()],int)
        letters=np.array([i for i,name in enumerate(self.labels) if len(name)==1 and not name.isdigit() and not self.dynamic[i]],int)
        if not len(digits) or not len(letters):return None
        number=int(digits[np.argmax(scores[digits])]);letter=int(letters[np.argmax(scores[letters])])
        minimum=float(self.setting('min_score',.55))
        # Only known near-overlaps can be ambiguous. Two high cosine scores do
        # not establish identical anatomy (e.g. 3/B, 5/E, 2/H, 7/S or 9/X).
        pair=(self.labels[number],self.labels[letter])
        near_overlaps={('1','d'),('2','v'),('6','y'),('7','l')}
        if pair in near_overlaps and min(float(scores[number]),float(scores[letter]))>=minimum and abs(float(scores[number]-scores[letter]))<.06:
            return self.labels[number].upper()+'/'+self.labels[letter].upper()
        return None
    def components(self,pose,wrist,windows=None,static_pose=None,context=None):
        pose,wrist=np.asarray(pose,np.float32),np.asarray(wrist,np.float32)
        if len(pose)==0:
            raise ValueError("No hand frames")
        if self.motion_v2:pose,wrist=prepare_sign_sequence(pose,wrist)
        # Median of recent poses reduces detector jitter without averaging a whole sign.
        current=np.median(pose[-min(3,len(pose)):],axis=0) if static_pose is None else np.asarray(static_pose,np.float32)
        full_current=current.copy()
        if self.mode in ('letters','digits','all'):
            current=single_hand_sequence(current[None],np.median(wrist[-min(3,len(wrist)):],axis=0)[None])[0][0]
        desc=metric_descriptor(shape_descriptor(current[None]),self.arrays)[0]
        shape=class_max(self.arrays['static']@desc,self.arrays['static_y'],len(self.labels))
        digit_mask=np.array([len(name)==1 and name.isdigit() for name in self.labels])
        letter_mask=np.array([len(name)==1 and not name.isdigit() for name in self.labels])
        raw_shape=shape.copy();letter_active=self.active & letter_mask if self.mode=='all' else self.active
        shape=refine_finger_spread(shape,current,self.labels,self.config,letter_active)
        shape=refine_finger_context_static(shape,current,self.labels,self.config,letter_active)
        if self.mode in ('digits','all'):
            digit_shape=refine_digit_anatomy(raw_shape,current,self.labels,self.digit_anatomy,self.active & digit_mask)
            shape[digit_mask]=digit_shape[digit_mask]
        shape=refine_static_anatomy(shape,current,self.static_anatomy,self.active & (digit_mask | letter_mask))
        word_mask=np.isin(self.labels,self.config.get('word_labels',[]))
        if self.mode=='all' and np.any(word_mask & ~self.dynamic):
            full_desc=metric_descriptor(shape_descriptor(full_current[None]),self.arrays)[0]
            full_shape=class_max(self.arrays['static']@full_desc,self.arrays['static_y'],len(self.labels))
            shape[word_mask]=full_shape[word_mask]
        if 'word_hand_features' in self.arrays and np.any(word_mask & ~self.dynamic & self.active):
            templates=np.flatnonzero((word_mask & ~self.dynamic & self.active)[self.arrays['temporal_y']])
            tail=min(9,len(pose));query=word_hand_sequence(pose[-tail:],wrist[-tail:],self.arrays)
            similarity=1-.5*word_dtw_distances(query,self.arrays['word_hand_features'][templates],self.arrays['word_hand_present'][templates],self.arrays['word_hand_geometry'][templates])
            observed_pair_count=np.all(np.any(pose[-tail:].reshape(-1,2,21,3)!=0,axis=(2,3)),axis=1).sum()
            similarity[(self.arrays['template_hand_presence'][templates]>=.4)&(observed_pair_count<3)]=-1.
            static_scores=class_max(similarity,self.arrays['temporal_y'][templates],len(self.labels))
            shape[word_mask & ~self.dynamic]=static_scores[word_mask & ~self.dynamic]
        if context is not None and np.any(word_mask & ~self.dynamic):
            tail=min(9,len(pose));anchors=np.asarray(context)[-tail:]
            penalty=location_penalties(pose[-tail:],wrist[-tail:],anchors,self.arrays)
            for index in np.flatnonzero(word_mask & ~self.dynamic & self.active):
                templates=self.arrays['temporal_y']==index
                if templates.any():shape[index]-=float(self.setting('location_weight',.08))*min(float(penalty[templates].min()),2.)
        temporal=np.full(len(self.labels),-1.,np.float32)
        dynamic_ready=np.zeros(len(self.labels),bool)
        ending=shape_descriptor(pose[-min(4,len(pose)):])
        endpoint_stable=(len(pose)>=4 and float(np.linalg.norm(ending-ending[-1],axis=1).max())
                         <=float(self.config.get('endpoint_stability',.10)))
        word_mask=np.isin(self.labels,self.config.get('word_labels',[]))
        event_scores=None;event_quality=-np.inf;neural_pose=pose;neural_wrist=wrist
        candidates=[(pose,wrist,context)] if windows is None else windows
        # The same readiness gate below rejects every moving letter endpoint.
        # Avoid expensive DTW until at least one active dynamic class can pass;
        # words retain their original movement/coverage checks.
        if not np.any(self.dynamic & self.active & (word_mask | endpoint_stable)):candidates=[]
        for candidate in candidates:
            p,w=candidate[:2];anchor=candidate[2] if len(candidate)>2 else None
            if self.motion_v2:p,w=prepare_sign_sequence(p,w)
            if len(p)<6:
                continue
            before=len(p)
            observed_both=np.all(np.any(pose[-before:].reshape(-1,2,21,3)!=0,axis=(2,3)),axis=1)
            try:
                first,last=gesture_interval(p,w,anchor)
                p,w=trim_gesture(p,w,True,keep_full_motion=self.config.get('feature_pipeline') in TRACKED_PIPELINES,context=anchor)
            except ValueError:continue
            if anchor is not None:anchor=anchor[first:last] if len(anchor)==before else None
            if len(p)<6:continue
            observed_pair_count=int(observed_both[first:last].sum()) if len(observed_both)==before else 0
            if float(np.any(p!=0,axis=1).mean())<.65:continue
            shape_motion,wrist_motion=motion_evidence(p,w)
            trajectory=sequence_descriptor(p,w,metric=self.arrays)
            if shape_motion<.025 and wrist_motion<.04:
                continue
            ids=np.flatnonzero(self.active[self.arrays['temporal_y']])
            similarity=np.full(len(self.arrays['temporal']),-1.,np.float32)
            location_weight=float(self.config.get('word_policy',{}).get('location_weight',self.setting('location_weight',.08)))
            word_templates=np.isin(np.asarray(self.labels)[self.arrays['temporal_y']],self.config.get('word_labels',[]))
            legacy_ids=ids[~word_templates[ids]] if 'word_hand_features' in self.arrays else ids
            if len(legacy_ids):
                bank,norms=self._dtw_bank(legacy_ids)
                similarity[legacy_ids]=1-.5*dtw_distances(trajectory,bank,template_norms=norms)
            if 'word_hand_features' in self.arrays:
                word_ids=ids[word_templates[ids]]
                if len(word_ids):
                    query=word_hand_sequence(p,w,self.arrays)
                    similarity[word_ids]=1-.5*word_dtw_distances(query,self.arrays['word_hand_features'][word_ids],self.arrays['word_hand_present'][word_ids],self.arrays['word_hand_geometry'][word_ids])
            similarity[ids]-=location_weight*np.minimum(location_penalties(p,w,anchor,self.arrays)[ids],2.)*word_templates[ids]
            matching_pose,matching_wrist=p,w
            both=np.all(np.any(p.reshape(-1,2,21,3)!=0,axis=(2,3)),axis=1)
            if len(self.two_hand_templates) and both.sum()>=3:
                swapped_pose=p.reshape(-1,2,21,3)[:,::-1].reshape(-1,126)
                swapped_wrist=w.reshape(-1,2,4)[:,::-1].reshape(-1,8)
                swapped=sequence_descriptor(swapped_pose,swapped_wrist,metric=self.arrays)
                ids=self.two_hand_templates[self.active[self.arrays['temporal_y'][self.two_hand_templates]]]
                alternate=np.full(len(ids),-1.,np.float32)
                legacy_ids=np.flatnonzero(~word_templates[ids]) if 'word_hand_features' in self.arrays else np.arange(len(ids))
                if len(legacy_ids):
                    bank,norms=self._dtw_bank(ids[legacy_ids])
                    alternate[legacy_ids]=1-.5*dtw_distances(swapped,bank,template_norms=norms)
                if 'word_hand_features' in self.arrays:
                    word_ids=np.flatnonzero(word_templates[ids])
                    if len(word_ids):
                        template_ids=ids[word_ids];query=word_hand_sequence(swapped_pose,swapped_wrist,self.arrays)
                        alternate[word_ids]=1-.5*word_dtw_distances(query,self.arrays['word_hand_features'][template_ids],self.arrays['word_hand_present'][template_ids],self.arrays['word_hand_geometry'][template_ids])
                alternate-=location_weight*np.minimum(location_penalties(swapped_pose,swapped_wrist,anchor,self.arrays)[ids],2.)*word_templates[ids]
                combined=similarity.copy();combined[ids]=np.maximum(similarity[ids],alternate)
                winner=int(np.argmax(combined))
                if combined[winner]>similarity[winner]:matching_pose,matching_wrist=swapped_pose,swapped_wrist
                similarity=combined
            if self.motion_v2:
                required_both=self.arrays['template_hand_presence']
                # One visible hand cannot validate a template requiring sustained two-hand evidence.
                insufficient=(required_both>=.40) & ((both.mean()<np.maximum(.20,.50*required_both)) | (both.sum()<3))
                if 'word_hand_features' in self.arrays:
                    insufficient[word_templates]=(required_both[word_templates]>=.40)&(observed_pair_count<3)
                similarity[insufficient]=-1.

            similarity=refine_finger_context_endpoints(similarity,current,shape,self.labels,self.arrays,self.config,p[0],self.active)
            # A held single pose must not masquerade as a full two-step template.
            templates=self.arrays['temporal']
            required_shape=self.required_shape_motion
            required_path=self.required_path_motion
            observed_shape=float(np.linalg.norm(trajectory[:,:self.shape_dim]-trajectory[:1,:self.shape_dim],axis=1).max())
            # A zero-motion template channel carries no evidence of a second step.
            # Require an informative channel and enough observed motion in that channel.
            if 'template_motion_evidence' in self.arrays:
                evidence=self.arrays['template_motion_evidence'];required_shape=evidence[:,0];required_path=evidence[:,1]
                shape_steps=(required_shape>.025) & (shape_motion>=np.maximum(.35*required_shape,.025))
            else:
                shape_steps=(required_shape>.05) & (observed_shape>=np.maximum(.35*required_shape,.05))
            path_steps=(required_path>.02) & (wrist_motion>=np.maximum(.35*required_path,.02))
            has_steps=shape_steps | path_steps
            # Word motion amplitude is not comparable to the preparation/lowering
            # amplitude in dictionary videos. Retain relative gating for accents.
            has_steps[word_templates]=(shape_motion>=.04 or wrist_motion>=.025)
            dynamic_templates=self.dynamic[self.arrays['temporal_y']]
            similarity[dynamic_templates & ~has_steps]=-1.
            window_scores=class_max(similarity,self.arrays['temporal_y'],len(self.labels))
            window_scores[~self.active]=-1.
            eligible=self.dynamic & self.active & (window_scores>0) & (word_mask | endpoint_stable)
            dynamic_ready |= eligible
            window_scores[self.dynamic & ~eligible]=-1.
            temporal=np.maximum(temporal,window_scores)
            order=np.argsort(-window_scores)
            gap=float(window_scores[order[0]]-window_scores[order[1]]) if len(order)>1 else 1.
            if self.dynamic[order[0]] and gap>=float(self.setting('dynamic_margin',.015)):
                # A complete sign in a longer window must not be hidden by a
                # perfectly static suffix winning a shorter window.
                quality=float(window_scores[order[0]])+.25*gap
                if quality>event_quality:
                    event_scores=window_scores;event_quality=quality;neural_pose=matching_pose;neural_wrist=matching_wrist
        if event_scores is not None:temporal=event_scores
        neural_static=np.full(len(self.labels),-1.,np.float32)
        neural_sequence=neural_static.copy()
        word_neural_weight=float(self.config.get('word_policy',{}).get('neural_weight',0.)) if self.mode=='all' else 0.
        if self.embed is not None and self.centers is not None and (max(float(self.setting('neural_weight',0.)),word_neural_weight)>0 or self.config.get('evaluate_neural_components',False)):
            has_dynamic=bool(np.any(self.dynamic & self.active))
            batch=np.stack([np.tile(current,(40,1)),resample(neural_pose)]) if has_dynamic else np.tile(current,(1,40,1))
            vectors=unit(self.embed(normalize_pose(batch,self.mean,self.std)))
            neural_static=vectors[0]@self.centers.T
            if has_dynamic:neural_sequence=vectors[1]@self.centers.T
            if self.mode=='all' and np.any(word_mask & ~self.dynamic):
                full_vector=unit(self.embed(normalize_pose(np.tile(full_current,(1,40,1)),self.mean,self.std)))
                neural_static[word_mask]=(full_vector[0]@self.centers.T)[word_mask]
        return shape,temporal,neural_static,neural_sequence,dynamic_ready
    def combine(self,parts):
        shape,temporal,neural_static,neural_sequence,ready=parts
        weight=float(self.setting('neural_weight',.20)) if self.embed is not None else 0.
        scores=(1-weight)*shape+weight*neural_static
        if self.mode=='all':
            digit_mask=np.array([len(name)==1 and name.isdigit() for name in self.labels])
            scores[digit_mask]=shape[digit_mask]  # Exactly the same digit branch as mode N.
        scores[self.dynamic | ~self.active]=-1.
        # Compare complete sequences against complete sequences. Do not require
        # DTW to beat a cosine measured on just the best static frame.
        ready_mask=np.full(len(self.labels),bool(ready),bool) if np.ndim(ready)==0 else np.asarray(ready,bool)
        if self.mode=='all' and ready_mask.any():
            # A complete word competes within the word vocabulary first. A
            # transient letter pose is not evidence against a complete gesture.
            word_mask=np.isin(self.labels,self.config.get('word_labels',[])) & self.active
            policy=self.config.get('word_policy',{})
            word_weight=float(policy.get('neural_weight',weight)) if self.embed is not None else 0.
            word_scores=(1-word_weight)*temporal+word_weight*neural_sequence
            word_scores[~word_mask | (self.dynamic & ~ready_mask)]=-1.
            ids=np.flatnonzero(word_mask);order=ids[np.argsort(-word_scores[ids])]
            if len(order):
                top=int(order[0]);gap=float(word_scores[top]-word_scores[order[1]]) if len(order)>1 else 1.
                minimum=float(policy.get('min_dynamic_score',.65));margin=float(policy.get('min_dynamic_margin',.07))
                if self.dynamic[top] and ready_mask[top] and word_scores[top]>=minimum and gap>=margin:
                    return word_scores
        if ready_mask.any():
            sequence_scores=(1-weight)*temporal+weight*neural_sequence
            sequence_scores[self.dynamic]-=float(self.setting('dynamic_penalty',.0))
            sequence_scores[~self.active | (self.dynamic & ~ready_mask)]=-1.
            order=np.argsort(-sequence_scores);winner=int(order[0])
            gap=float(sequence_scores[order[0]]-sequence_scores[order[1]]) if len(order)>1 else 1.
            if self.dynamic[winner] and gap>=float(self.setting('dynamic_margin',.015)):
                scores=sequence_scores
        return scores
    def predict(self,pose,wrist,windows=None,context=None,return_ready_mask=False):
        if self.word_head is not None and self.mode in ('words','all'):
            candidates=[(pose,wrist,context)] if windows is None else windows
            word_scores,word_ready=self.word_head.predict(candidates)
            order=np.argsort(-word_scores);top=int(order[0]);gap=float(word_scores[top]-word_scores[order[1]])
            if self.mode=='words' or (word_scores[top]>=self.word_head.policy['min_score'] and gap>=self.word_head.policy['min_margin'] and word_ready[top]):
                return word_scores,word_ready if return_ready_mask else bool(word_ready[top])
            # The new word head owns words; do not silently reintroduce old DTW guesses.
            original_active=self.active.copy();self.active[self.word_head.indices]=False
            try:parts=self.components(pose,wrist,windows,context=context)
            finally:self.active=original_active
        else:parts=self.components(pose,wrist,windows,context=context)
        scores=self.combine(parts);ready=parts[-1]
        if self.word_head is not None and self.mode=='all':
            scores[self.word_head.indices]=-1.;ready=np.asarray(ready,bool).copy();ready[self.word_head.indices]=False
        if return_ready_mask:return scores,ready
        return scores,(bool(ready) if np.ndim(ready)==0 else bool(ready[int(np.argmax(scores))]))
class LiveSession:
    """Exactly the same causal decision loop for webcam and notebook evaluation."""
    def __init__(self,recognizer,legacy=False):
        self.recognizer=recognizer;self.legacy=legacy;self.events=[]
        self.last_output=None;self.last_scores=None
        self.buffer=GestureBuffer(max_seconds=float(recognizer.config.get('buffer_seconds',6.)),sample_hz=float(recognizer.config.get('sample_hz',15)),
                                  gap_seconds=float(recognizer.config.get('tracking_gap_seconds',.60)),
                                  repair_gaps=recognizer.config.get('feature_pipeline') in TRACKED_PIPELINES)
        self.decision=StableDecision(recognizer.labels,float(recognizer.config.get('min_margin',.025)),float(recognizer.config.get('min_score',.55)),
                                     float(recognizer.config.get('min_dynamic_margin',.035)),float(recognizer.config.get('min_dynamic_score',.45)),recognizer.dynamic_labels,recognizer.config.get('word_labels',[]))
        self.hold=CompletedSignHold();self.reset()
    def reset(self):
        # Mode switches must refresh the decision thresholds as well as scores.
        self.decision.margin=float(self.recognizer.setting('min_margin',.025))
        self.decision.minimum=float(self.recognizer.setting('min_score',.55))
        self.decision.dynamic_margin=float(self.recognizer.setting('min_dynamic_margin',.035))
        self.decision.dynamic_minimum=float(self.recognizer.setting('min_dynamic_score',.45))
        self.decision.static_dwell=float(self.recognizer.setting('static_dwell',.25))
        self.decision.word_policy=dict(self.recognizer.config.get('word_policy',{}))
        if self.recognizer.word_head is not None:self.decision.word_policy.update(self.recognizer.word_head.policy)
        self.buffer.clear();self.decision.reset();self.hold.clear();self.output=None
        self.last_prediction=-np.inf;self.last_active=None;self.last_emitted=None
    def update(self,pose,wrist,now,allow_prediction=True,context=None):
        was_held=self.hold.anchor is not None;keep_held=self.hold.update(pose,now,wrist)
        if was_held and not keep_held:
            self.decision.reset();self.buffer.clear();self.output=None;self.last_emitted=None
        self.buffer.add(pose,wrist,now,context)
        if np.any(pose):self.last_active=now
        elif self.last_active is None or now-self.last_active>float(self.recognizer.config.get('tracking_gap_seconds',.60)):
            self.decision.reset();self.hold.clear();self.output=None;self.last_emitted=None
        if not allow_prediction or not np.any(pose) or keep_held or not self.buffer.frames or now-self.last_prediction<float(self.recognizer.setting('prediction_interval',.15)):
            return self.output
        self.last_prediction=now
        recent=list(self.buffer.frames)
        p=np.array([item[1] for item in recent]);w=np.array([item[2] for item in recent])
        anchor=np.array([item[3] for item in recent])
        scores,ready=legacy_scores(self.recognizer,p) if self.legacy else self.recognizer.predict(p,w,self.buffer.windows(),context=anchor,return_ready_mask=True)
        collision=self.recognizer.domain_collision(scores)
        confirmed,ranked,gap,reliable=self.decision.update(scores if collision is None else np.full_like(scores,-1.),now,ready)
        if collision is not None:
            ranked=np.argsort(-scores);gap=float(scores[ranked[0]]-scores[ranked[1]])
            self.decision.smoothed=scores.copy();self.decision.confirmed=None;confirmed=None
        probabilities=relative_probabilities(self.decision.smoothed,self.recognizer.config.get('temperature',.08))
        # A remembered word is not a current reliable result when the new ranking
        # disagrees or falls below the rejection thresholds.
        if confirmed is not None and self.recognizer.labels[confirmed] in self.recognizer.config.get('word_labels',[]):
            if not reliable or confirmed!=int(ranked[0]):confirmed=None
        shown_ready=bool(ready) if np.ndim(ready)==0 else bool(ready[int(ranked[0])])
        self.output=(confirmed,ranked,gap,reliable,probabilities,shown_ready)
        self.last_output=self.output;self.last_scores=self.decision.smoothed.copy()
        if self.recognizer.mode in ('letters','digits') and confirmed is None and self.decision.confirmed is None:self.last_emitted=None
        if confirmed is not None and confirmed!=self.last_emitted:
            self.events.append({'time':round(now,3),'label':self.recognizer.labels[confirmed]})
            self.last_emitted=confirmed
            if self.recognizer.dynamic[confirmed] and self.recognizer.labels[confirmed] not in self.recognizer.config.get('word_labels',[]):
                self.hold.capture(np.median(p[-3:],axis=0),now,np.median(w[-3:],axis=0));self.buffer.clear()
        return self.output
# END SHARED SIGNVOICE CODE

def validate_runtime(config,folder):
    """Check the feature extractor before loading TensorFlow or opening a camera."""
    import sys
    import importlib.metadata as metadata
    trained=config.get('versions',{})
    mismatches=[]
    for package in ('mediapipe','opencv-contrib-python'):
        expected=trained.get(package)
        if not expected:
            continue
        try:
            actual=metadata.version(package)
        except metadata.PackageNotFoundError:
            actual='chưa cài'
        if actual!=expected:
            mismatches.append(f'{package}: máy={actual}, train={expected}')
    if mismatches:
        executable="'"+sys.executable.replace("'","''")+"'"
        specs=' '.join(f'"{package}=={trained[package]}"' for package in ('mediapipe','opencv-contrib-python') if trained.get(package))
        install=f'& {executable} -m pip install --upgrade {specs}'
        script="'"+str(Path(__file__).resolve()).replace("'","''")+"'"
        model_dir="'"+str(Path(folder).resolve()).replace("'","''")+"'"
        raise RuntimeError('Thư viện trích xuất landmark không khớp bộ model:\n  '+
                           '\n  '.join(mismatches)+'\nĐóng chương trình rồi chạy trong PowerShell:\n'+
                           install+f'\n& {executable} {script} --model-dir {model_dir} --check'+
                           '\nKhông cần train lại chỉ vì lỗi phiên bản thư viện. '
                           'Cảnh báo TensorFlow về GPU Windows/placeholder không phải nguyên nhân dừng này.')

def load_bundle(folder):
    folder=Path(folder)
    required=['embedding_model_v2.keras','prototypes_v2.json','train_mean.npy','train_std.npy']
    missing=[name for name in required if not (folder/name).is_file()]
    if missing:
        raise FileNotFoundError('Thiếu file: '+', '.join(missing)+'. Tải lại ZIP từ cell 9.')
    config_path=folder/'recognizer_config.json'
    if config_path.is_file():
        preview=json.loads(config_path.read_text(encoding='utf-8'))
        if preview.get('schema')!=SCHEMA:
            raise ValueError('Bộ model cũ khác schema V5. Chạy lại cell 1–9 trên Colab, giải nén đủ các file model từ ZIP mới và dùng test_camera.py đã cập nhật riêng.')
        validate_runtime(preview,folder)
    import tensorflow as tf
    custom=keras_custom_objects(tf)
    model=tf.keras.models.load_model(folder/required[0],custom_objects=custom,compile=False)
    if model.input_shape!=(None,40,126):
        raise ValueError(f'Sai input model: {model.input_shape}; cần (None,40,126).')
    mean=np.load(folder/'train_mean.npy',allow_pickle=False).astype(np.float32)
    std=np.load(folder/'train_std.npy',allow_pickle=False).astype(np.float32)
    if mean.shape!=(126,) or std.shape!=(126,) or not np.isfinite(mean).all() or not np.isfinite(std).all() or np.any(std<=0):
        raise ValueError('Normalizer không hợp lệ; không trộn file từ hai lần train.')
    prototypes=json.loads((folder/'prototypes_v2.json').read_text(encoding='utf-8'))
    labels=list(prototypes);centers=unit(np.asarray(list(prototypes.values()),np.float32))
    if len(labels)<1 or centers.shape!=(len(labels),model.output_shape[-1]) or not np.isfinite(centers).all():
        raise ValueError('Prototype không khớp model.')
    @tf.function(input_signature=[tf.TensorSpec((None,40,126),tf.float32)])
    def inference(batch):
        return model(batch,training=False)
    def embed(batch):
        return inference(tf.convert_to_tensor(batch,tf.float32)).numpy()
    embed(np.zeros((2,40,126),np.float32))
    config_path=folder/'recognizer_config.json';arrays_path=folder/'recognizer_v5.npz'
    if config_path.is_file()!=arrays_path.is_file():
        raise ValueError('Thiếu một trong hai file hybrid. Giải nén đầy đủ ZIP mới.')
    if config_path.is_file():
        config=json.loads(config_path.read_text(encoding='utf-8'))
        if config.get('schema')!=SCHEMA or config.get('labels')!=labels:
            raise ValueError('Schema/danh sách nhãn không khớp bộ model.')
        import hashlib
        expected_hashes=set(required+['recognizer_v5.npz','hand_landmarker.task'])
        if config.get('feature_pipeline') in ('stable_two_hand_v5',EXTRACTOR_VERSION):expected_hashes.add('face_detector.tflite')
        if config.get('word_temporal'):expected_hashes.update({'word_temporal.keras','word_temporal_config.json'})
        if set(config.get('sha256',{}))!=expected_hashes:
            raise ValueError('Manifest thiếu checksum. Tải lại ZIP từ cell 9.')
        for name,digest in config.get('sha256',{}).items():
            path=folder/name
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
                raise ValueError(f'{name} khác lần train trong manifest. Tải lại cả ZIP.')
        with np.load(arrays_path,allow_pickle=False) as data:
            arrays={key:data[key] for key in data.files}
        sequence_version=int(np.asarray(arrays.get('sequence_version',1)).item())
        if 'sequence_version' in config and int(config['sequence_version'])!=sequence_version:
            raise ValueError('Phiên bản chuỗi trong config khác template. Thay đủ các file từ cùng ZIP cell 9.')
        if config.get('feature_pipeline') in ('stable_two_hand_v5',EXTRACTOR_VERSION):
            if sequence_version!=3 or not {'template_hand_presence','template_motion_evidence','template_location','template_location_valid','word_hand_features','word_hand_present','word_hand_geometry'}.issubset(arrays):
                raise ValueError('Model thiếu thông tin chuỗi/tay của pipeline hiện tại. Chạy lại cell 4–9.')
        if any(not np.isfinite(v).all() for v in arrays.values()):
            raise ValueError('Template chứa NaN/Inf.')
        if arrays['temporal'].ndim!=3 or len(arrays['temporal'])!=len(arrays['temporal_y']):
            raise ValueError('Template sequence sai kích thước.')
        if 'template_location' in arrays:
            if arrays['template_location'].shape!=(len(arrays['temporal']),12) or arrays.get('template_location_valid',np.zeros(0)).shape!=(len(arrays['temporal']),6):
                raise ValueError('Template vị trí ký hiệu sai kích thước; tải đủ ZIP mới.')
        if 'word_hand_features' in arrays:
            count=len(arrays['temporal']);dim=len(arrays['metric_mean'])+2
            if arrays['word_hand_features'].shape!=(count,SEQUENCE_STEPS,2,dim) or arrays.get('word_hand_present',np.zeros(0)).shape!=(count,SEQUENCE_STEPS,2) or arrays.get('word_hand_geometry',np.zeros(0)).shape!=(count,SEQUENCE_STEPS,4):
                raise ValueError('Template quan sát từng tay sai kích thước; tải cả ZIP mới.')
        dim=shape_descriptor(np.zeros((1,126),np.float32)).shape[1]
        if (arrays['static'].shape!=(len(arrays['static_y']),dim) or
            arrays['temporal'].shape[1:]!=(SEQUENCE_STEPS,dim+(8 if int(np.asarray(arrays.get('sequence_version',1)).item())>=2 else 4)) or
            arrays['metric_mean'].shape!=(dim,) or arrays['metric_std'].shape!=(dim,) or
            np.any(arrays['metric_std']<=0)):
            raise ValueError('Template/metric không khớp schema V5.')
        for key in ('static_y','temporal_y'):
            if arrays[key].ndim!=1 or np.any(arrays[key]<0) or np.any(arrays[key]>=len(labels)):
                raise ValueError('Template chứa class index không hợp lệ.')
        # Validation deliberately collects neural components for weight search.
        # Runtime must not execute a neural branch whose selected weight is zero.
        config=dict(config);config['evaluate_neural_components']=False
        recognizer=HybridRecognizer(labels,arrays,config,embed,centers,mean,std)
        if config.get('word_temporal'):
            word_config=json.loads((folder/'word_temporal_config.json').read_text(encoding='utf-8'))
            if word_config.get('version')!=WORD_TEMPORAL_VERSION or word_config.get('steps')!=WORD_TEMPORAL_STEPS or set(word_config.get('labels',[]))!=set(config.get('word_labels',[])) or len(word_config['labels'])!=len(set(word_config['labels'])):
                raise ValueError('Word model/config không khớp bộ model. Giải nén đủ ZIP mới.')
            word_model=tf.keras.models.load_model(folder/'word_temporal.keras',compile=False)
            if word_model.input_shape!=[(None,WORD_TEMPORAL_STEPS,126),(None,WORD_TEMPORAL_STEPS,19)] or word_model.output_shape!=(None,len(word_config['labels'])+1):
                raise ValueError('Sai input/output của model từ sinh hoạt.')
            @tf.function(input_signature=[tf.TensorSpec((None,WORD_TEMPORAL_STEPS,126),tf.float32),tf.TensorSpec((None,WORD_TEMPORAL_STEPS,19),tf.float32)])
            def word_graph(shape,motion):return word_model([shape,motion],training=False)
            def word_infer(inputs):return word_graph(tf.convert_to_tensor(inputs[0]),tf.convert_to_tensor(inputs[1])).numpy()
            word_infer([np.zeros((1,WORD_TEMPORAL_STEPS,126),np.float32),np.zeros((1,WORD_TEMPORAL_STEPS,19),np.float32)])
            recognizer.word_head=TemporalWordHead(labels,word_config,word_infer,embed=embed,centers=centers,mean=mean,std=std)
        return recognizer,False
    print('Đang dùng model cũ: đã sửa buffer/ổn định hiển thị; cần train và tải ZIP mới để dùng hybrid.')
    return HybridRecognizer(labels,{},dict(neural_weight=1.,temperature=.08,min_score=.55,min_margin=.025),embed,centers,mean,std),True

def legacy_scores(recognizer,pose):
    batch=np.stack([np.tile(np.median(pose[-3:],axis=0),(40,1)),resample(pose)])
    vectors=unit(recognizer.embed(normalize_pose(batch,recognizer.mean,recognizer.std)))
    scores=vectors@recognizer.centers.T
    movement=np.max(np.linalg.norm(pose-pose[0],axis=1))/np.sqrt(126) if len(pose)>5 else 0.
    ready=bool(len(pose)>=6 and movement>.025)
    result=scores[0].copy()
    result[recognizer.dynamic]=scores[1,recognizer.dynamic]-.04 if ready else -1.
    return result,ready

def create_landmarker(folder,video=True,opencv_assist=False):
    task=Path(folder)/'hand_landmarker.task'
    if not task.is_file():raise FileNotFoundError('Thiếu hand_landmarker.task; giải nén ZIP từ cell 9.')
    return ResilientHandLandmarker(task,video,opencv_assist)

def opencv_demo_panel(frame,hands=(),motion=None,mirror=True):
    """Display image evidence used for recovery, with the webcam's orientation."""
    import cv2
    h,w=frame.shape[:2];tile=cv2.resize(frame,(480,round(h*480/w)))
    gray=cv2.cvtColor(tile,cv2.COLOR_BGR2GRAY)
    lab=cv2.cvtColor(tile,cv2.COLOR_BGR2LAB)
    lab[:,:,0]=cv2.createCLAHE(clipLimit=2.,tileGridSize=(8,8)).apply(lab[:,:,0])
    enhanced=cv2.cvtColor(lab,cv2.COLOR_LAB2BGR)
    marked=tile.copy();height,width=marked.shape[:2]
    links=[(0,1),(1,2),(2,3),(3,4),(0,5),(5,6),(6,7),(7,8),(5,9),(9,10),(10,11),(11,12),(9,13),(13,14),(14,15),(15,16),(13,17),(0,17),(17,18),(18,19),(19,20)]
    for hand in hands:
        points=[(int(p.x*width),int(p.y*height)) for p in hand]
        for a,b in links:cv2.line(marked,points[a],points[b],(0,220,0),2)
        for p in points:cv2.circle(marked,p,3,(0,255,255),-1)
        xy=np.asarray(points);lo=xy.min(axis=0);hi=xy.max(axis=0)
        cv2.rectangle(marked,tuple(lo),tuple(hi),(255,180,0),2)
    flow=tile.copy();mask=np.zeros(gray.shape,np.uint8)
    if motion is not None:
        for a,b in motion.arrows:
            a=tuple(np.round(a*[width/w,height/h]).astype(int));b=tuple(np.round(b*[width/w,height/h]).astype(int))
            cv2.arrowedLine(flow,a,b,(0,255,255),2,tipLength=.35)
        if motion.motion_mask is not None:mask=cv2.resize(motion.motion_mask,(width,height),interpolation=cv2.INTER_NEAREST)
    tiles=[marked,enhanced,flow,cv2.cvtColor(mask,cv2.COLOR_GRAY2BGR)]
    if mirror:tiles=[cv2.flip(im,1) for im in tiles]
    for im,title in zip(tiles,['Hand ROI: actual detections','CLAHE: contrast for fallback','LK optical flow: image motion','Motion inside tracked hand regions']):
        cv2.rectangle(im,(0,0),(im.shape[1],28),(20,20,20),-1);cv2.putText(im,title,(8,19),cv2.FONT_HERSHEY_SIMPLEX,.45,(255,255,255),1)
    return np.concatenate([np.concatenate(tiles[:2],axis=1),np.concatenate(tiles[2:],axis=1)],axis=0)

def camera_region_from_recording(frame):
    """Remove the SignVoice title/status panel, undo display mirroring, and inpaint baked-in green dots."""
    import cv2
    rows=np.flatnonzero(np.mean(frame.mean(axis=2)<40,axis=1)>.96)
    rows=rows[rows>max(136,int(frame.shape[0]*.15))]
    if not len(rows):raise ValueError('--screen-recording: không tìm thấy ranh giới camera/panel SignVoice; dùng video camera gốc nếu không phải bản ghi cửa sổ.')
    end=int(rows[0]);top=36
    if end-top<100:raise ValueError('Vùng camera trong bản ghi quá nhỏ.')
    cam=cv2.flip(frame[top:end,2:-2],1)
    b,g,r=cam[:,:,0],cam[:,:,1],cam[:,:,2]
    green_mask=((g>200)&(r<80)&(b<80)).astype(np.uint8)*255
    if np.any(green_mask):
        green_mask=cv2.dilate(green_mask,np.ones((5,5),np.uint8))
        cam=cv2.inpaint(cam,green_mask,3,cv2.INPAINT_TELEA)
    return cam

def display_text(frame,lines,below=False,refresh_hz=0.):
    import cv2
    top=0
    if below:
        # Render only the status panel; never cache camera pixels or spend PIL
        # layout time on every captured frame. Critical mode changes invalidate it.
        height=40+max(16,len(lines))*30
        key=(frame.shape[1],height,tuple((line,tuple(color)) for line,color in lines))
        cache=getattr(display_text,'panel_cache',None);now=time.monotonic()
        mode_line=next((line for line,_ in lines if line.startswith('Chế độ:')),None)
        reuse=cache is not None and cache['key'][:2]==key[:2] and cache['mode']==mode_line
        reuse=reuse and (cache['key']==key or (refresh_hz>0 and now-cache['stamp']<1/refresh_hz))
        if not reuse:
            panel=np.full((height,frame.shape[1],3),25,np.uint8)
            panel=display_text(panel,lines)
            cache={'key':key,'panel':panel,'stamp':now,'mode':mode_line}
            display_text.panel_cache=cache
        return np.concatenate((frame,cache['panel']),axis=0)
    else:
        cv2.rectangle(frame,(8,8),(min(frame.shape[1]-8,650),min(frame.shape[0]-8,40+len(lines)*30)),(25,25,25),-1)
    try:
        from PIL import Image,ImageDraw,ImageFont
        font_paths=['C:/Windows/Fonts/arial.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']
        if not hasattr(display_text,'font'):display_text.font=next(ImageFont.truetype(p,22) for p in font_paths if Path(p).is_file())
        font=display_text.font
        image=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));draw=ImageDraw.Draw(image)
        for i,(line,color) in enumerate(lines):
            draw.text((18,top+16+i*30),line,font=font,fill=color)
        return cv2.cvtColor(np.asarray(image),cv2.COLOR_RGB2BGR)
    except (ImportError,StopIteration,OSError):
        import unicodedata
        translations={'ă':'a(','â':'a^','ê':'e^','ô':'o^','ơ':'o+','ư':'u+','đ':'d-'}
        for i,(line,color) in enumerate(lines):
            for key,value in translations.items():line=line.replace(key,value).replace(key.upper(),value.upper())
            line=unicodedata.normalize('NFKD',line).encode('ascii','ignore').decode()
            cv2.putText(frame,line,(18,top+38+i*30),cv2.FONT_HERSHEY_SIMPLEX,.65,color[::-1],2)
        return frame

class LatestCameraFrame:
    """Read the camera continuously and keep one newest frame, without a video backlog."""
    def __init__(self,cap):
        import threading
        self.cap=cap;self.condition=threading.Condition();self.latest=None
        self.index=0;self.consumed=0;self.stopped=False;self.capture_times=deque(maxlen=60)
        self.thread=threading.Thread(target=self._capture,daemon=True);self.thread.start()
    def _capture(self):
        while not self.stopped:
            ok,frame=self.cap.read();stamp=time.monotonic()
            with self.condition:
                if not ok:self.stopped=True;self.condition.notify_all();break
                self.latest=(frame,stamp);self.index+=1;self.capture_times.append(stamp);self.condition.notify_all()
    def measured_fps(self):
        with self.condition:
            t=list(self.capture_times)
        return (len(t)-1)/(t[-1]-t[0]) if len(t)>1 and t[-1]>t[0] else 0.
    def read(self):
        with self.condition:
            ready=self.condition.wait_for(lambda:self.index!=self.consumed or self.stopped,timeout=2.)
            if not ready or self.index==self.consumed:return False,None,None
            self.consumed=self.index;frame,stamp=self.latest
            return True,frame,stamp
    def close(self):
        self.stopped=True;self.cap.release()
        with self.condition:self.condition.notify_all()
        self.thread.join(timeout=2.)

class SigningContextWorker:
    """Update the coarse anchor without blocking the webcam detector loop."""
    def __init__(self,model_path=None):
        import threading
        self.condition=threading.Condition();self.pending=None;self.stopped=False
        self.anchor=np.zeros(4,np.float32);self.stamp=-np.inf;self.next_submit=-np.inf;self.error=None
        self.model_path=model_path
        self.thread=threading.Thread(target=self._run,daemon=True);self.thread.start()
    def update(self,frame,now):
        with self.condition:
            if self.error is not None:raise RuntimeError('Định vị người ký hiệu bị lỗi: '+str(self.error))
            if now>=self.next_submit:
                self.next_submit=now+.4;self.pending=(frame.copy(),now);self.condition.notify_all()
            return self.anchor.copy() if now-self.stamp<=1.2 else np.zeros(4,np.float32)
    def snapshot(self,now):
        """Read the last real image anchor, retaining its capture time and TTL."""
        with self.condition:
            if self.error is not None:raise RuntimeError('Face context failed: '+str(self.error))
            if not 0<=now-self.stamp<=1.2:return np.zeros(4,np.float32),None
            return self.anchor.copy(),self.stamp
    def _run(self):
        try:
            tracker=SigningContextTracker(self.model_path)
            while True:
                with self.condition:
                    self.condition.wait_for(lambda:self.pending is not None or self.stopped)
                    if self.stopped:tracker.close();return
                    frame,now=self.pending;self.pending=None
                anchor=tracker.update(frame,now)
                with self.condition:self.anchor=anchor;self.stamp=now
        except Exception as exc:
            if 'tracker' in locals():tracker.close()
            with self.condition:self.error=exc
    def close(self):
        with self.condition:self.stopped=True;self.condition.notify_all()
        self.thread.join(timeout=3.)

class LiveRecognitionWorker:
    """Keep hand detection responsive while sequence matching runs independently."""
    def __init__(self,session):
        import threading
        self.session=session;self.condition=threading.Condition();self.pending=deque(maxlen=180)
        self.generation=0;self.applied_generation=0;self.mode=session.recognizer.mode
        self.snapshot=(None,None,False,None,None);self.error=None;self.stopped=False
        self.event_start=len(session.events)
        self.thread=threading.Thread(target=self._run,daemon=True);self.thread.start()
    def submit(self,pose,wrist,now,context=None):
        with self.condition:
            anchor=np.zeros(4,np.float32) if context is None else np.asarray(context,np.float32)
            self.pending.append((pose.copy(),wrist.copy(),now,anchor.copy()));self.condition.notify_all()
    def reset(self,mode=None):
        with self.condition:
            if mode is not None:self.mode=mode
            self.generation+=1;self.pending.clear();self.snapshot=(None,None,False,None,None)
            self.condition.notify_all()
    def poll(self):
        with self.condition:
            if self.error is not None:raise RuntimeError('Nhận diện chuỗi bị lỗi: '+str(self.error))
            return self.snapshot
    def _run(self):
        try:
            while True:
                with self.condition:
                    self.condition.wait_for(lambda:self.pending or self.generation!=self.applied_generation or self.stopped)
                    if self.stopped:return
                    generation=self.generation;mode=self.mode;batch=list(self.pending);self.pending.clear()
                if generation!=self.applied_generation:
                    self.session.recognizer.set_mode(mode);self.session.reset();self.applied_generation=generation
                    self.event_start=len(self.session.events)
                # Retain every sampled observation, including dropouts. Only classification
                # is deferred to the newest observation when several frames arrived together.
                for i,(pose,wrist,now,anchor) in enumerate(batch):
                    self.session.update(pose,wrist,now,allow_prediction=i==len(batch)-1,context=anchor)
                output=self.session.output
                scores=None if self.session.decision.smoothed is None else self.session.decision.smoothed.copy()
                collision=None if scores is None else self.session.recognizer.domain_collision(scores)
                with self.condition:
                    if generation==self.generation:
                        completed=self.session.events[-1].copy() if len(self.session.events)>self.event_start else None
                        self.snapshot=(output,scores,self.session.hold.anchor is not None,collision,completed)
        except Exception as exc:
            with self.condition:self.error=exc
    def close(self):
        with self.condition:self.stopped=True;self.condition.notify_all()
        self.thread.join(timeout=3.)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir',type=Path,default=Path(__file__).resolve().parent)
    parser.add_argument('--camera',type=int,default=0)
    parser.add_argument('--mode',choices=['all','letters','digits','words'],default='all')
    parser.add_argument('--legacy-words',action='store_true',help='Compare with the old word DTW engine instead of the new temporal word model.')
    parser.add_argument('--takes',type=int,default=1)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--image',type=Path)
    parser.add_argument('--video',type=Path)
    parser.add_argument('--record',metavar='LABEL')
    parser.add_argument('--seconds',type=float,default=4.)
    parser.add_argument('--min-hand-radius',type=float,default=.055,help='Minimum visible hand size when no face anchor is available.')
    parser.add_argument('--processing-width',type=int,default=640,help='Camera/image processing width; keeps the original aspect ratio.')
    parser.add_argument('--capture-fps',type=float,default=30.,help='Requested webcam FPS; the actual measured capture rate is displayed.')
    parser.add_argument('--opencv-demo',action='store_true',help='Show hand ROIs, contrast, optical flow and image motion beside the camera.')
    parser.add_argument('--opencv-assist',action='store_true',help='Use optical flow to guide missing-hand search; experimental, adds image processing work.')
    parser.add_argument('--show-relative-scores',action='store_true',help='Show uncalibrated relative percentages as well as similarity.')
    parser.add_argument('--diagnostics-dir',type=Path,help='Opt-in: save camera images BEFORE overlays, timestamps and recognition results for replay; never adds them to training.')
    parser.add_argument('--video-roi',type=int,nargs=4,metavar=('X','Y','WIDTH','HEIGHT'),help='Exact camera rectangle in a multi-window screen recording; requires --screen-recording.')
    parser.add_argument('--screen-recording',action='store_true',help='For --video containing the SignVoice window: crop its camera panel and undo mirroring.')
    parser.add_argument('--embed-weight',type=float,choices=[0.,.8,1.],default=None,help='Diagnostic only: TCN (0), guarded fusion (0.8), prototype-only (1). Complete verified bundle required.')
    args=parser.parse_args()
    if args.screen_recording and not args.video:parser.error('--screen-recording cần --video.')
    if args.video_roi and not args.screen_recording:parser.error('--video-roi cần --screen-recording.')
    if not 320<=args.processing_width<=1280:parser.error('--processing-width phải từ 320 đến 1280.')
    if not 5<=args.capture_fps<=120:parser.error('--capture-fps phải từ 5 đến 120.')
    if not .01<=args.min_hand_radius<=.25:parser.error('--min-hand-radius phải từ 0.01 đến 0.25.')
    if args.record:
        if not np.isfinite(args.seconds) or not .5<=args.seconds<=30:parser.error('--seconds phải từ 0.5 đến 30.')
        if not 1<=args.takes<=20:parser.error('--takes phải từ 1 đến 20.')
        for take in range(args.takes):
            print(f'Lượt {take+1}/{args.takes}')
            import cv2
            # This action is opt-in: it never records during ordinary recognition.
            import csv,unicodedata
            label=unicodedata.normalize('NFC',args.record.strip().lower())
            if not label or any(c in label for c in '/\\\r\n'):
                parser.error('Nhãn không hợp lệ.')
            out=args.model_dir/'personal_samples';out.mkdir(exist_ok=True)
            cap=cv2.VideoCapture(args.camera)
            if not cap.isOpened():raise RuntimeError('Không mở được camera.')
            writer=None;path=out/(label+'_'+str(time.time_ns())+'.mp4')
            start=time.monotonic();times=[]
            print('Chuẩn bị 2 giây; sau đó làm TRỌN ký hiệu trong',args.seconds,'giây.')
            try:
                while True:
                    ok,frame=cap.read()
                    if not ok:raise RuntimeError('Không đọc được camera.')
                    elapsed=time.monotonic()-start
                    if elapsed>=2:
                        if writer is None:
                            h,w=frame.shape[:2];writer=cv2.VideoWriter(str(path),cv2.VideoWriter_fourcc(*'mp4v'),15,(w,h))
                            if not writer.isOpened():raise RuntimeError('Không tạo được video.')
                        # Limit recording cadence to the declared video FPS.
                        if not times or elapsed-times[-1]>=1/15:
                            writer.write(frame);times.append(elapsed)
                    shown=display_text(cv2.flip(frame,1),[(f'{label}: '+('Chuẩn bị' if elapsed<2 else 'Đang ghi'),(255,255,0))])
                    cv2.imshow('SignVoice - Record',shown)
                    if cv2.waitKey(1)&0xff==ord('q') or elapsed>=2+args.seconds:break
            finally:
                cap.release()
                if writer:writer.release()
                cv2.destroyAllWindows()
            if len(times)>=6:
                csv_path=out/'labels.csv';new=not csv_path.exists()
                with csv_path.open('a',encoding='utf-8',newline='') as f:
                    csv_writer=csv.writer(f)
                    if new:csv_writer.writerow(['VIDEO','LABEL'])
                    csv_writer.writerow([path.name,label])
                print('Đã lưu:',path,'; nén thư mục personal_samples và đưa ZIP vào PROJECT_DIR trên Drive.')
            else:
                if path.exists():path.unlink()
                print('Clip quá ngắn, chưa thêm vào dataset.')
        if (out/'labels.csv').is_file():
            import zipfile
            archive=args.model_dir/'personal_samples.zip'
            with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
                z.write(out/'labels.csv',arcname='personal_samples/labels.csv')
                for sample in sorted(out.glob('*.mp4')):z.write(sample,arcname='personal_samples/'+sample.name)
            print('Đã đóng gói mẫu webcam:',archive)
            print('Đưa ZIP này vào Train_AI_SignVoice trên Drive, chạy Colab 1–9 rồi tải model mới.')
        return
    recognizer,legacy=load_bundle(args.model_dir)
    # Overrides are diagnostic only; never disable checksum or delete bundle files.
    if args.embed_weight is not None:
        if recognizer.word_head is None:raise ValueError('No word head in this bundle')
        recognizer.word_head.policy['embed_weight']=args.embed_weight
        print('EXPERIMENTAL score override; not a calibrated webcam operating point:',args.embed_weight)
    if args.legacy_words:recognizer.word_head=None
    recognizer.set_mode(args.mode)
    outdated_model=(not legacy and recognizer.config.get('feature_pipeline')!=EXTRACTOR_VERSION)
    if outdated_model:
        print('MODEL CHƯA CẬP NHẬT: '+str(recognizer.config.get('feature_pipeline'))+
              '; code hiện tại '+EXTRACTOR_VERSION+'. Chạy lại Colab 1–9, tải ZIP cell 9 và thay đủ các file model.')
    print(f'Bundle OK: {len(recognizer.labels)} nhãn; schema={"legacy" if legacy else SCHEMA}.')
    if recognizer.config.get('word_labels'):
        print('Word engine:',WORD_TEMPORAL_VERSION if recognizer.word_head else 'DTW cũ; cần train lại Colab 4–9 để có model từ mới.')
        if recognizer.word_head:
            print('WORD runtime:',WORD_RUNTIME_VERSION)
            print('WORD policy:',recognizer.word_head.policy)
            print('WORD TCN còn thử nghiệm; điểm softmax chưa được hiệu chỉnh thành xác suất nhận đúng webcam.')
            sampling=recognizer.word_head.config.get('training_sampling',{})
            report=recognizer.word_head.config.get('multivsl_training',{})
            validation=recognizer.word_head.config.get('validation_labels',0)
            print('Độ phủ đánh giá từ:',validation,'/',len(recognizer.word_head.names),'nhãn có VAL;',
                  sampling.get('two_video_words','?'),'nhãn chỉ có 2 video TRAIN.')
            if report:print('Model đang dùng:',report.get('selected_for_export','không rõ'),'; nhánh Multi-VSL không tự thêm nhãn từ tiếng Việt.')
    if not legacy:
        print('U/V geometry:', 'ON' if recognizer.config.get('finger_spread_refiner',{}).get('enabled') else 'OFF',
              '| Finger context:', 'ON' if recognizer.config.get('finger_context_refiner',{}).get('enabled') else 'OFF')
    import cv2
    cv2.setNumThreads(1)
    import mediapipe as mp
    if recognizer.config.get('word_labels') and not args.video and not args.image and not args.check and args.mode=='all':
        print('Để thử từ sinh hoạt, chọn W hoặc chạy --mode words. Nhãn xin chào trong dataset là chào.')
    if args.check:
        with create_landmarker(args.model_dir,False):
            pass
        face_path=args.model_dir/'face_detector.tflite'
        if face_path.is_file():
            face_check=SigningContextTracker(face_path);face_check.close()
            print('MediaPipe face model OK.')
        print('MediaPipe/task OK. Có thể chạy camera.')
        print('Từ sinh hoạt trong bundle:',len(recognizer.config.get('word_labels',[])))
        print('Theo dõi hai tay:',recognizer.config.get('feature_pipeline','bản cũ; chạy lại Colab 1–9 để cập nhật'))
        print('Phiên bản code:',EXTRACTOR_VERSION,'| Chuỗi model:',int(np.asarray(recognizer.arrays.get('sequence_version',1)).item()))
        if recognizer.config.get('word_policy_validation'):
            print('Đánh giá riêng chế độ W:',recognizer.config['word_policy_validation'])
        audit=recognizer.config.get('word_train_diagnostic')
        if audit:
            print('Kiểm tra lại mẫu TRAIN từ:',audit['correct'],'/',audit['labels'],'(không phải accuracy webcam).')
            print('Từ chưa qua kiểm tra TRAIN:',sorted({row['label'] for row in audit.get('failures',[])}))
        if recognizer.config.get('feature_pipeline')!=EXTRACTOR_VERSION:
            print('Model chưa dùng toàn bộ cải tiến hiện tại: chạy lại Colab 4–9 và tải đủ các file ZIP mới.')
        for label in ('chào','tạm biệt'):
            info=recognizer.config.get('train_hand_usage',{}).get(label,{})
            if info:print(label,'— tỷ lệ khung TRAIN có hai tay:',round(100*info.get('two_hand_fraction',0),1),'%')
        return
    if args.image:
        image=cv2.imread(str(args.image))
        if image is None:raise ValueError('Không đọc được ảnh.')
        with create_landmarker(args.model_dir,False) as detector:
            result=detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=cv2.cvtColor(image,cv2.COLOR_BGR2RGB)))
        h,w=image.shape[:2];p,g,_=features_from_result(result,w,h,legacy,allow_low_hands=True,keep_both_hands=recognizer.config.get('feature_pipeline') in TRACKED_PIPELINES)
        if not np.any(p):raise ValueError('Không có bàn tay hợp lệ trong ảnh.')
        scores,ready=legacy_scores(recognizer,np.tile(p,(40,1))) if legacy else recognizer.predict(np.tile(p,(40,1)),np.tile(g,(40,1)),windows=[])
        print([(recognizer.labels[i],round(float(scores[i]),4)) for i in np.argsort(-scores)[:3]])
        print('Ảnh đơn chỉ kiểm tra tư thế tĩnh; không đánh giá được ký hiệu hai bước.')
        return
    cap=cv2.VideoCapture(str(args.video) if args.video else args.camera)
    if not cap.isOpened():raise RuntimeError('Không mở được video/camera; kiểm tra --camera hoặc quyền camera Windows.')
    if not args.video:
        cap.set(cv2.CAP_PROP_BUFFERSIZE,1)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,args.processing_width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT,round(args.processing_width*.75))
        cap.set(cv2.CAP_PROP_FPS,args.capture_fps)
        print(f'Camera thương lượng: {int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}×{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}; FPS driver {cap.get(cv2.CAP_PROP_FPS):.1f}. FPS đo tay hiển thị riêng.')
    session=LiveSession(recognizer,legacy)
    stable_tracking=recognizer.config.get('feature_pipeline') in TRACKED_PIPELINES
    tracker=HandSlotTracker() if stable_tracking else None
    timestamp=-1;start=time.monotonic();frame_no=0
    capture=LatestCameraFrame(cap) if not args.video else None
    recognition=LiveRecognitionWorker(session) if capture else None
    processing_times=deque(maxlen=30);last_loop=None
    face_model=args.model_dir/'face_detector.tflite'
    face_model=face_model if face_model.is_file() else None
    signer_context=SigningContextWorker(face_model) if capture else SigningContextTracker(face_model)
    fps=cap.get(cv2.CAP_PROP_FPS);fps=fps if np.isfinite(fps) and fps>0 else 30.
    frame_times=None
    if args.video:
        sidecar=args.video.with_suffix('.json')
        if sidecar.is_file():
            info=json.loads(sidecar.read_text(encoding='utf-8'))
            if info.get('kind')=='SignVoiceCameraDiagnostic':
                frame_times=np.asarray(info['frame_times'],float)
                if not len(frame_times) or not np.isfinite(frame_times).all() or np.any(np.diff(frame_times)<=0):
                    raise ValueError('Timestamp trong bản ghi chẩn đoán không hợp lệ.')
    diagnostic_writer=None;diagnostic_path=None;diagnostic_rows=[];diagnostic_times=[]
    window_sized=False
    event_start=len(session.events)
    segment_recording=False
    segment_buffer=[]
    segment_result=None
    if not args.video or args.opencv_demo:cv2.namedWindow('SignVoice - Stable Hybrid',cv2.WINDOW_NORMAL)
    try:
        with create_landmarker(args.model_dir,True,args.opencv_assist or args.opencv_demo) as detector:
            while True:
                if capture:ok,raw,captured_at=capture.read()
                else:ok,raw=cap.read();captured_at=None
                if not ok:break
                if args.screen_recording:
                    if args.video_roi:
                        x,y,rw,rh=args.video_roi
                        if x<0 or y<0 or rw<100 or rh<100 or x+rw>raw.shape[1] or y+rh>raw.shape[0]:
                            raise ValueError('--video-roi vượt khung video hoặc vùng camera quá nhỏ.')
                        raw=cv2.flip(raw[y:y+rh,x:x+rw],1)
                    else:raw=camera_region_from_recording(raw)
                if raw.shape[1]>args.processing_width:
                    scale=args.processing_width/raw.shape[1];raw=cv2.resize(raw,(round(raw.shape[1]*scale),round(raw.shape[0]*scale)))
                frame_no+=1
                if frame_times is not None and frame_no>len(frame_times):raise ValueError('Video và timestamp chẩn đoán không khớp số khung.')
                now=float(frame_times[frame_no-1]) if frame_times is not None else frame_no/fps if args.video else captured_at-start
                if last_loop is not None:processing_times.append(time.monotonic()-last_loop)
                last_loop=time.monotonic()
                timestamp=max(timestamp+1,int(now*1000))
                display_mode=recognition.mode if recognition else recognizer.mode
                anchor=signer_context.update(raw,now) if display_mode in ('all','words') else np.zeros(4,np.float32)
                detector.target_hands=1 if display_mode in ('digits','letters') else 2
                detector.search_regions=display_mode not in ('digits','letters')
                result=detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB,data=cv2.cvtColor(raw,cv2.COLOR_BGR2RGB)),timestamp)
                h,w=raw.shape[:2];observed_hands=len(result.hand_landmarks or [])
                result=foreground_hand_result(result,w,h,anchor,args.min_hand_radius)
                ignored_hands=observed_hands-len(result.hand_landmarks)
                pose,wrist,hands=features_from_result(result,w,h,legacy,allow_low_hands=True,tracker=tracker,now=now,keep_both_hands=stable_tracking)
                if segment_recording:
                    segment_buffer.append((pose.copy(),wrist.copy(),anchor.copy(),float(now)))
                if recognition:
                    recognition.submit(pose,wrist,now,anchor)
                    output,shown_scores,is_held,collision,last_completed=recognition.poll()
                else:
                    output=session.update(pose,wrist,now,context=anchor)
                    shown_scores=session.decision.smoothed;is_held=session.hold.anchor is not None
                    collision=None if shown_scores is None else recognizer.domain_collision(shown_scores)
                    last_completed=session.events[-1] if len(session.events)>event_start else None
                if args.diagnostics_dir:
                    if diagnostic_writer is None:
                        args.diagnostics_dir.mkdir(parents=True,exist_ok=True)
                        diagnostic_path=args.diagnostics_dir/('camera_'+time.strftime('%Y%m%d_%H%M%S')+'_'+str(time.time_ns())+'.mp4')
                        diagnostic_writer=cv2.VideoWriter(str(diagnostic_path),cv2.VideoWriter_fourcc(*'mp4v'),30.,(w,h))
                        if not diagnostic_writer.isOpened():raise RuntimeError('Không tạo được video chẩn đoán.')
                    # Save actual camera pixels, without dots, text, mirroring or panels.
                    diagnostic_writer.write(raw);diagnostic_times.append(float(now))
                    ranking=[] if shown_scores is None else [int(i) for i in np.argsort(-shown_scores) if shown_scores[i]>-.99][:3]
                    diagnostic_rows.append({'time':float(now),'mode':display_mode,'hands':len(hands),
                        'capture_fps':capture.measured_fps() if capture else float(fps),
                        'detector_timing':dict(getattr(detector,'last_timing',{})),
                        'top':[(recognizer.labels[i],float(shown_scores[i])) for i in ranking],
                        'confirmed':recognizer.labels[output[0]] if output is not None and output[0] is not None else None,
                        'word_window':dict(recognizer.word_head.last_diagnostics) if recognizer.word_head else {}})
                if args.video and not args.opencv_demo:continue
                shown=cv2.flip(raw,1)
                focus=int(np.argmax([np.linalg.norm(np.array([[lm.x,lm.y*h/w,lm.z] for lm in hand])-np.array([hand[0].x,hand[0].y*h/w,hand[0].z]),axis=1).max() for hand in hands])) if hands else -1
                for index,hand in enumerate(hands):
                    color=(0,255,0) if display_mode not in ('digits','letters') or index==focus else (130,130,130)
                    for lm in hand:cv2.circle(shown,(int((1-lm.x)*w),int(lm.y*h)),3,color,-1)
                mode_title={'all':'Tất cả','letters':'Chữ','digits':'Số','words':'Từ sinh hoạt'}[display_mode]
                lines=[(f'Chế độ: {mode_title} | N: số, C: chữ, W: từ, A: tất cả',(255,255,255))]
                if segment_recording:
                    duration=now-segment_buffer[0][3] if segment_buffer else 0.
                    lines.insert(0,(f'[● DANG THU KY HIEU: {duration:.1f}s | {len(segment_buffer)} frames - BAM R DE DUNG & NHAN DIEN]',(50,50,255)))
                elif segment_result:
                    top_name,top_sc,top_pr=segment_result[0]
                    lines.insert(0,(f'Đoạn chẩn đoán — ứng viên: {top_name.upper()} | điểm model {top_sc:.3f}',(120,220,255)))
                    if len(segment_result)>1:
                        sub=' | '.join(f'{k}. {w.upper()} (điểm {s:.3f})' for k,(w,s,p) in enumerate(segment_result[1:3],2))
                        lines.insert(1,(f'   Du doan khac: {sub}',(180,230,255)))
                if outdated_model:
                    lines.append(('MODEL CŨ: chạy lại Colab và thay đủ các file từ ZIP cell 9.',(255,175,80)))
                if hands:
                    text=(f'Thấy {len(hands)} tay; dùng tay xanh để nhận chữ/số.' if display_mode in ('letters','digits') and len(hands)>1 else f'Đang theo dõi: {len(hands)} tay')
                    lines.append((text+(' | vừa bắt lại tay' if detector.recovered else ''),(80,255,120)))
                    if len(hands)==1 and display_mode=='words':
                        lines.append(('Nếu ký hiệu dùng 2 tay: hiện chỉ bắt được 1 tay.',(255,215,80)))
                if ignored_hands:lines.append((f'Đã bỏ qua {ignored_hands} tay quá nhỏ/xa vùng người ký hiệu.',(200,200,200)))
                if processing_times:
                    rate=1/max(float(np.mean(processing_times)),1e-6)
                    camera_rate=capture.measured_fps() if capture else fps
                    lines.append((f'Camera: {camera_rate:.1f} FPS | đo tay: {rate:.1f} FPS',(200,200,200)))
                    if rate<10:lines.append(('Xử lý chậm; giảm nhịp ký hiệu để giữ đủ các bước.',(255,215,80)))
                if not hands:
                    detected=len(result.hand_landmarks or [])
                    status=('Đã thấy tay nhưng landmark chưa đủ rõ; đưa trọn tay vào khung.' if detected
                            else 'Tạm mất tay: có thể bị nhòe/che khuất; đưa trọn hai tay vào khung.')
                    lines.append((status,(255,215,80)))
                elif output is None:
                    lines.append((f'Đã bắt {len(hands)} tay; đang lấy mẫu ký hiệu.',(80,255,120)))
                else:
                    confirmed,ranked,gap,reliable,probabilities,ready=output
                    name=(collision+' — KHÓ PHÂN BIỆT; CHỌN N HOẶC C') if collision else (recognizer.labels[confirmed] if confirmed is not None else 'CHƯA RÕ / ĐANG XÁC NHẬN')
                    lines.append(('Kết quả: '+name.upper(),(80,255,120) if confirmed is not None else (255,215,80)))
                    evidence=('đủ bằng chứng xác nhận' if ready else 'chưa đủ bằng chứng xác nhận') if recognizer.word_head and display_mode=='words' else ('có chuỗi chuyển động' if ready else 'tư thế tĩnh')
                    lines.append((f'Khoảng cách TOP 1–2: {gap:.3f}; '+evidence,(230,230,230)))
                    valid_ranked=[i for i in ranked if recognizer.active[i] and shown_scores[i]>-.99]
                    for rank,i in enumerate(valid_ranked[:3],1):
                        relative=f'điểm tương đối {probabilities[i]*100:.1f}% | ' if args.show_relative_scores else ''
                        score_title='điểm model' if recognizer.word_head and recognizer.labels[i] in recognizer.word_head.names else 'similarity'
                        lines.append((f'{rank}. {recognizer.labels[i].upper()}: {relative}{score_title} {shown_scores[i]:.3f}',(120,220,255)))
                    if not valid_ranked:
                        diagnostic=recognizer.word_head.last_diagnostics if recognizer.word_head else {}
                        status='Model đang ưu tiên lớp nền; chưa xác nhận từ.' if diagnostic.get('selected_word')=='__background__' else 'Chưa đủ quan sát để so khớp; chưa xác nhận từ.'
                        lines.append((status,(255,215,80)))
                    elif confirmed is None and not collision:
                        dynamic=recognizer.dynamic[int(valid_ranked[0])]
                        minimum=float(recognizer.setting('min_dynamic_score',.45) if dynamic else recognizer.setting('min_score',.55))
                        required_gap=float(recognizer.setting('min_dynamic_margin',.035) if dynamic else recognizer.setting('min_margin',.025))
                        if recognizer.labels[valid_ranked[0]] in recognizer.config.get('word_labels',[]):
                            policy=recognizer.config.get('word_policy',{})
                            if recognizer.word_head:policy={**policy,**recognizer.word_head.policy}
                            minimum=float(policy.get('min_dynamic_score' if dynamic else 'min_score',minimum))
                            required_gap=float(policy.get('min_dynamic_margin' if dynamic else 'min_margin',required_gap))
                        evidence=recognizer.word_head.last_diagnostics if recognizer.word_head and display_mode=='words' else {}
                        rejects=evidence.get('rejection_reasons',[])
                        if 'hand_coverage' in rejects:reason=f"Tỷ lệ đo được tay {evidence['measured_hand_coverage']:.0%}; chưa đủ để xác nhận."
                        elif 'pair_or_motion' in rejects:reason='Chưa đủ bằng chứng hai tay hoặc chuyển động cho ứng viên.'
                        elif shown_scores[valid_ranked[0]]<minimum:reason=f'Điểm {shown_scores[valid_ranked[0]]:.3f} chưa đạt ngưỡng {minimum:.3f}; chưa xác nhận.'
                        elif 'margin_with_background' in rejects:reason='Ứng viên còn gần lớp nền/từ khác; chưa xác nhận.'
                        elif dynamic and not ready:reason='Chưa đủ chuỗi chuyển động để xác nhận.'
                        elif gap<required_gap:reason='Các từ gần nhau; chưa đủ chênh lệch để chọn.'
                        else:reason='Đang xác nhận qua nhiều lần dự đoán.'
                        lines.append((reason,(255,215,80)))
                    if is_held:lines.append(('Đã xong chuỗi; đổi tư thế/hạ tay để bắt đầu ký hiệu mới.',(80,255,120)))
                    lines.append(('Điểm model/độ khớp không phải % chính xác đã kiểm định.',(200,200,200)))
                if last_completed and last_completed['label'] in recognizer.config.get('word_labels',[]):
                    lines.append(('Từ đã xác nhận gần nhất: '+last_completed['label'].upper(),(80,255,120)))
                lines.append(('Nhận diện tự động | R: thu đoạn chẩn đoán | SPACE: làm mới | Q: thoát',(255,215,80)))
                shown=display_text(shown,lines,below=True,refresh_hz=8.)
                if not window_sized:
                    scale=min(1.,1100/shown.shape[1],850/shown.shape[0])
                    cv2.resizeWindow('SignVoice - Stable Hybrid',round(shown.shape[1]*scale),round(shown.shape[0]*scale))
                    window_sized=True
                cv2.imshow('SignVoice - Stable Hybrid',shown)
                if args.opencv_demo:
                    cv2.imshow('SignVoice - OpenCV processing',opencv_demo_panel(raw,hands,detector.motion))
                key=cv2.waitKey(1)&0xff
                if key==ord('q'):break
                if key in (ord('r'),ord('R')):
                    if not segment_recording:
                        segment_recording=True
                        segment_buffer.clear()
                        segment_result=None
                        print('\n[SignVoice] BẮT ĐẦU THU ĐOẠN CỬ CHỈ... Hãy thực hiện ký hiệu rồi bấm R lần nữa!',flush=True)
                    else:
                        segment_recording=False
                        print(f'\n[SignVoice] KẾT THÚC THU ({len(segment_buffer)} frames). Đang nhận diện...',flush=True)
                        active=[i for i,item in enumerate(segment_buffer) if np.any(item[0])]
                        if active:segment_buffer=list(segment_buffer)[active[0]:active[-1]+1]
                        if len(segment_buffer)>=4 and recognizer.word_head is not None:
                            p_seg=np.array([item[0] for item in segment_buffer],np.float32)
                            w_seg=np.array([item[1] for item in segment_buffer],np.float32)
                            c_seg=np.array([item[2] for item in segment_buffer],np.float32)
                            t_seg=np.array([item[3] for item in segment_buffer],np.float64)
                            w_scores,w_ready=recognizer.word_head.predict([(p_seg,w_seg,c_seg,t_seg)])
                            w_probs=relative_probabilities(w_scores,recognizer.config.get('temperature',.08))
                            w_ranked=np.argsort(-w_scores)
                            segment_result=[(recognizer.labels[i],float(w_scores[i]),float(w_probs[i])) for i in w_ranked[:3]]
                            print('=== KẾT QUẢ NHẬN DIỆN ĐOẠN VỪA THU ===',flush=True)
                            for rk,(name,sc,pr) in enumerate(segment_result,1):
                                print(f'  {rk}. {name.upper()}: điểm model={sc:.3f} (ứng viên chẩn đoán)',flush=True)
                        else:
                            print('Đoạn thu quá ngắn hoặc chưa có bàn tay hợp lệ.',flush=True)
                if key==ord('i'):
                    args.opencv_demo=not args.opencv_demo
                    if args.opencv_demo and detector.motion is None:detector.motion=OpenCVHandMotion()
                    if not args.opencv_demo:cv2.destroyWindow('SignVoice - OpenCV processing')
                if key in (ord('n'),ord('c'),ord('w'),ord('a')):
                    mode={ord('n'):'digits',ord('c'):'letters',ord('w'):'words',ord('a'):'all'}[key]
                    if recognition:recognition.reset(mode)
                    else:recognizer.set_mode(mode);session.reset()
                    if tracker:tracker.reset()
                    if detector.motion:detector.motion.reset()
                    detector.last_pair=None;detector.last_observed=None;detector.last_retry=-100000
                    event_start=len(session.events)
                if key==32:
                    if recognition:recognition.reset()
                    else:session.reset()
                    if tracker:tracker.reset()
                    if detector.motion:detector.motion.reset()
                    detector.last_pair=None;detector.last_observed=None;detector.last_retry=-100000
                    event_start=len(session.events)
    finally:
        if diagnostic_writer is not None:
            diagnostic_writer.release()
            diagnostic_path.with_suffix('.json').write_text(json.dumps({'kind':'SignVoiceCameraDiagnostic',
                'frame_times':diagnostic_times,'rows':diagnostic_rows,'extractor':EXTRACTOR_VERSION,
                'opencv_assist':detector.motion is not None,'overlays_in_saved_pixels':False,
                'raw_resolution':[w,h],'timestamp_origin':'camera_capture_monotonic',
                'word_runtime_version':WORD_RUNTIME_VERSION,
                'word_policy':recognizer.word_head.policy if recognizer.word_head else {},
                'word_model_sha256':__import__('hashlib').sha256((args.model_dir/'word_temporal.keras').read_bytes()).hexdigest() if recognizer.word_head else None},ensure_ascii=False),encoding='utf-8')
            print('Đã lưu camera gốc và timestamp chẩn đoán:',diagnostic_path)
        if capture:signer_context.close()
        else:signer_context.close()
        if recognition:recognition.close()
        if capture:capture.close()
        else:cap.release()
        cv2.destroyAllWindows()
    if args.video and session.last_output is not None:
        confirmed,ranked,gap,reliable,probabilities,ready=session.last_output
        print(json.dumps({'events':session.events,'last_completed':session.events[-1]['label'] if session.events else None,'confirmed':None if confirmed is None else recognizer.labels[confirmed],
              'top3':[(recognizer.labels[i],float(probabilities[i]),float(session.last_scores[i])) for i in ranked[:3]],
              'relative_scores_not_accuracy':True},ensure_ascii=False))
    elif args.video:
        print(json.dumps({'events':session.events,'error':'No usable hand frames'},ensure_ascii=False))

if __name__=='__main__':
    try:main()
    except (ValueError,FileNotFoundError,RuntimeError) as exc:
        raise SystemExit('SignVoice: '+str(exc))

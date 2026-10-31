"""Shared TRAIN/live optional anatomy features. Never changes legacy features.

Image x and y are both expressed in image-width units. Face keypoint order is
MediaPipe BlazeFace: eyes, nose, mouth, right and left ear tragion. Predictions
must use measured packets and their capture clock; no bounding-box fake ears.
"""
import copy
from functools import lru_cache
import numpy as np

SCHEMA='signvoice_face_geometry_v1'
EXTRA_FEATURES=('hand0_ear','hand0_mouth','hand0_tip_x','hand0_tip_y','hand0_scale','hand0_valid',
                'hand1_ear','hand1_mouth','hand1_tip_x','hand1_tip_y','hand1_scale','hand1_valid','face_yaw','face_valid')
TTL=1.2
FACE_DETECTION_VERSION='full_frame_then_upper_center_v2'

def remap_face_detections(result,roi,size):
    """Map real crop detections back to full-frame normalized coordinates."""
    x0,y0,x1,y1=roi;width,height=size;out=copy.deepcopy(result)
    for face in out.detections:
        for point in face.keypoints:
            point.x=(x0+point.x*(x1-x0))/width
            point.y=(y0+point.y*(y1-y0))/height
        face.bounding_box.origin_x+=x0;face.bounding_box.origin_y+=y0
    return out

def detect_face_with_fallback(detector,image):
    """One extra crop only after a full-frame miss, using the same detector.

    This is label-independent and shared by TRAIN and live. Detection confidence,
    signer consistency checks and original hand/model inputs stay unchanged.
    """
    result=detector.detect(image)
    if result.detections:return result
    pixels=image.numpy_view();h,w=pixels.shape[:2]
    x0,y0,x1,y1=w//4,0,3*w//4,round(.65*h)
    if min(x1-x0,y1-y0)<32:return result
    import mediapipe as mp
    cropped=mp.Image(image_format=mp.ImageFormat.SRGB,data=np.ascontiguousarray(pixels[y0:y1,x0:x1]))
    found=detector.detect(cropped)
    return remap_face_detections(found,(x0,y0,x1,y1),(w,h)) if found.detections else result

def geometry_packet(points,stamp,width,height):
    xy=np.asarray(points,np.float32)
    if xy.shape!=(6,2) or not np.isfinite(xy).all() or not np.isfinite(stamp) or width<16 or height<16:
        raise ValueError('Expected six finite face keypoints, capture time and dimensions')
    return dict(schema=SCHEMA,timestamp_ms=float(stamp)*1000,width=int(width),height=int(height),
                coordinate_units='image_width_xy',keypoints=xy.tolist())

def mirror_packet(packet):
    if packet is None:return None
    out=copy.deepcopy(packet);p=np.asarray(out['keypoints'],np.float32);p[:,0]=1.-p[:,0]
    p[[0,1]]=p[[1,0]];p[[4,5]]=p[[5,4]];out['keypoints']=p.tolist();return out

def geometry_frame(pose,wrist,packet,now,expected_size=None):
    out=np.zeros(14,np.float32)
    p=np.asarray(pose,np.float32).reshape(2,21,3);w=np.asarray(wrist,np.float32).reshape(2,4)
    if not np.isfinite(p).all() or not np.isfinite(w).all() or not np.isfinite(now):raise ValueError('Nonfinite hand/time input')
    if packet is None:return out
    if packet.get('schema')!=SCHEMA or packet.get('coordinate_units')!='image_width_xy':raise ValueError('Unknown geometry packet')
    if expected_size is not None and (packet['width'],packet['height'])!=tuple(expected_size):raise ValueError('Geometry image dimensions differ')
    points=np.asarray(packet['keypoints'],np.float32);stamp=packet['timestamp_ms']/1000
    if points.shape!=(6,2) or not np.isfinite(points).all() or not np.isfinite(stamp):raise ValueError('Invalid face coordinates/time')
    if not 0<=now*1000-float(packet['timestamp_ms'])<=TTL*1000:return out
    eye=points[:2].mean(axis=0);axis=points[1]-points[0];eye_distance=float(np.linalg.norm(axis));scale=2.3*eye_distance
    if not .035<scale<.9:return out
    # Screen-oriented eye basis keeps horizontal sign direction available.
    if axis[0]<0:axis=-axis
    ex=axis/max(eye_distance,1e-6);ey=np.array([-ex[1],ex[0]],np.float32)
    for hand in range(2):
        if not np.any(p[hand]) or w[hand,2]<=0:continue
        sign=-1. if np.signbit(w[hand,0]) else 1.
        tip=np.array([abs(w[hand,0])+sign*p[hand,8,0]*w[hand,2],w[hand,1]+p[hand,8,1]*w[hand,2]])
        delta=(tip-eye)/scale
        ear=float(np.min(np.linalg.norm(points[4:6]-tip,axis=1)))/scale
        mouth=float(np.linalg.norm(points[3]-tip))/scale
        out[hand*6:hand*6+6]=[min(ear,4.)/4.,min(mouth,4.)/4.,
            np.clip(delta@ex,-6,6)/6.,np.clip(delta@ey,-6,6)/6.,min(float(w[hand,2])/scale,6.)/6.,1.]
    out[12]=np.clip(float((points[2]-eye)@ex)/max(eye_distance,1e-6),-2,2)/2.
    out[13]=1.
    return out

def geometry_sequence(runtime,pose,wrist,context,times,packets,now=None,length=48,observed=None):
    p=np.asarray(pose,np.float32);w=np.asarray(wrist,np.float32);t=np.asarray(times,np.float64)
    if len(packets)!=len(p) or t.shape!=(len(p),) or np.any(np.diff(t)<=0):raise ValueError('Unaligned face/hand/time sequence')
    base_p,base_m=runtime.word_temporal_features(p,w,context,t,length)
    prepared_p,prepared_w=runtime.prepare_sign_sequence(p,w)
    pp,ww=runtime.resample_hand_sequence(prepared_p,prepared_w,length)
    grid=np.linspace(0,len(p)-1,length)
    previous=np.floor(grid).astype(int)
    clock=np.interp(grid,np.arange(len(p)),t)
    # Packet age is tested on each contributing observation's original clock,
    # not against window end or a future face measurement.
    extra=np.stack([geometry_frame(pp[i],ww[i],packets[j],float(clock[i])) for i,j in enumerate(previous)])
    if observed is not None:
        _,_,measured=runtime.prepare_sign_sequence(p,w,observed)
        mask=measured[np.rint(grid).astype(int)]
        for hand in range(2):extra[~mask[:,hand],hand*6:hand*6+6]=0
    return base_p,np.concatenate([base_m,extra],axis=1).astype(np.float32)

class GeometryTimeline:
    """Capture-time lookup shared by cached TRAIN and individual live windows."""
    def __init__(self,packets):
        unique={}
        for packet in packets:
            if packet is None:continue
            # Validate metadata even when no hands were observed.
            geometry_frame(np.zeros(126),np.zeros(8),packet,packet['timestamp_ms']/1000)
            stamp=float(packet['timestamp_ms'])/1000
            if stamp in unique and unique[stamp]!=packet:raise ValueError('Conflicting face packets')
            unique[stamp]=copy.deepcopy(packet)
        self.times=np.asarray(sorted(unique),np.float64)
        self.packets=[unique[t] for t in self.times]
        self.milliseconds=np.asarray([p['timestamp_ms'] for p in self.packets],np.float64)
    def at(self,times):
        times=np.asarray(times,np.float64)
        if not np.isfinite(times).all():raise ValueError('Nonfinite lookup times')
        clock=times*1000;indices=np.searchsorted(self.milliseconds,clock,side='right')-1
        return [copy.deepcopy(self.packets[j]) if j>=0 and 0<=t-self.milliseconds[j]<=TTL*1000 else None
                for t,j in zip(clock,indices)]

def swap_geometry_slots(motion):
    out=np.asarray(motion).copy()
    if out.ndim!=2 or out.shape[1]!=33:raise ValueError('Expected 33 motion channels')
    out[:,19:31]=out[:,19:31].reshape(-1,2,6)[:,::-1].reshape(-1,12)
    return out

@lru_cache(maxsize=2)
def _geometry_predict_code(runtime_source):
    import ast
    tree=ast.parse(runtime_source)
    cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='TemporalWordHead')
    method=copy.deepcopy(next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='predict'))
    calls=0;swaps=0
    class Extend(ast.NodeTransformer):
        def visit_Call(self,node):
            nonlocal calls
            self.generic_visit(node)
            if isinstance(node.func,ast.Name) and node.func.id=='word_temporal_features':
                node.func.id='_geometry_features';node.keywords.append(ast.keyword(arg='observed',value=ast.Name(id='observed',ctx=ast.Load())))
                calls+=1
            return node
        def visit_AugAssign(self,node):
            nonlocal swaps
            self.generic_visit(node)
            if ast.dump(node,include_attributes=False)==ast.dump(ast.parse('swapped_m[:,15:18]*=-1').body[0],include_attributes=False):
                swaps+=1
                return [node,ast.parse('swapped_m=_swap_geometry_slots(swapped_m)').body[0]]
            return node
    method=Extend().visit(method)
    if (calls,swaps)!=(1,1):raise RuntimeError('Unknown temporal head; geometry adapter refused')
    return compile(ast.fix_missing_locations(ast.Module(body=[method],type_ignores=[])),'<geometry_head_adapter>','exec')

def bind_geometry_head(head,runtime,runtime_source,timeline,enabled=True):
    """Per-instance adapter; keep frozen window/decision logic and globals.

    The new per-hand channels follow the original two-hand slot-order branch.
    Compile its guarded adapter once, not once per replayed video.
    """
    import types
    def features(p,w,c,t,observed=None):
        shape,motion=geometry_sequence(runtime,p,w,c,t,timeline.at(t),observed=observed)
        if not enabled:motion[:,19:]=0
        return shape,motion
    namespace=dict(head.predict.__func__.__globals__)
    namespace.update(_geometry_features=features,_swap_geometry_slots=swap_geometry_slots)
    exec(_geometry_predict_code(runtime_source),namespace)
    head.predict=types.MethodType(namespace['predict'],head)
    return head

class FaceGeometryTracker:
    """Decorate existing coarse face tracker without an additional detector."""
    def __init__(self,runtime,model_path):
        self.tracker=runtime.SigningContextTracker(model_path);self.packet=None;self.latest=None
        actual=self.tracker.detector;owner=self
        class Capture:
            def detect(self,image):
                result=detect_face_with_fallback(actual,image);owner.latest=result;return result
            def close(self):actual.close()
        self.tracker.detector=Capture()

    def update(self,frame,now):
        fresh=now>=self.tracker.next_check;anchor=self.tracker.update(frame,now)
        h,w=frame.shape[:2]
        if fresh and self.tracker.last_seen==now and anchor[3]>0 and self.latest is not None:
            matches=[]
            for detection in self.latest.detections:
                if len(detection.keypoints)!=6:continue
                xy=np.array([[point.x,point.y*h/w] for point in detection.keypoints],np.float32)
                center=xy[:2].mean(axis=0);scale=2.3*float(np.linalg.norm(xy[1]-xy[0]))
                # Only expose the very same accepted face, not a nearby rejected
                # background face or a stale reference with a new timestamp.
                error=float(np.linalg.norm(center-anchor[:2]))+abs(scale-float(anchor[2]))
                if error<1e-5:matches.append((error,xy))
            if matches:self.packet=geometry_packet(min(matches,key=lambda x:x[0])[1],now,w,h)
        return anchor,self.snapshot(now,(w,h))

    def snapshot(self,now,size=None):
        if self.packet is None or not 0<=now*1000-self.packet['timestamp_ms']<=TTL*1000:return None
        if size is not None and tuple(size)!=(self.packet['width'],self.packet['height']):return None
        return copy.deepcopy(self.packet)

    def close(self):self.tracker.close()

class GeometryContextWorker:
    """Optional live collector, one existing FaceDetector on a bounded thread.

    update/snapshot keep the original four-channel anchor API. Geometry remains
    a separate measured packet until an independently validated model is loaded.
    """
    def __init__(self,runtime,model_path):
        import threading
        self.condition=threading.Condition();self.pending=None;self.stopped=False;self.error=None
        self.anchor=np.zeros(4,np.float32);self.packet=None;self.size=None
        self.stamp=-np.inf;self.processed_stamp=-np.inf;self.next_submit=-np.inf
        self.thread=threading.Thread(target=self._run,args=(runtime,model_path),daemon=True);self.thread.start()
    def update(self,frame,now):
        with self.condition:
            if self.error is not None:raise RuntimeError('Face geometry worker failed') from self.error
            if now>=self.next_submit:
                self.next_submit=now+.4;self.pending=(frame.copy(),now);self.condition.notify_all()
            return self.anchor.copy() if 0<=now-self.stamp<=TTL else np.zeros(4,np.float32)
    def snapshot(self,now):
        with self.condition:
            if self.error is not None:raise RuntimeError('Face geometry worker failed') from self.error
            return (self.anchor.copy(),self.stamp) if 0<=now-self.stamp<=TTL else (np.zeros(4,np.float32),None)
    def geometry_snapshot(self,now,size=None):
        with self.condition:
            if self.error is not None:raise RuntimeError('Face geometry worker failed') from self.error
            if self.packet is None or not 0<=now*1000-self.packet['timestamp_ms']<=TTL*1000:return None
            if size is not None and tuple(size)!=self.size:return None
            return copy.deepcopy(self.packet)
    def _run(self,runtime,model_path):
        tracker=None
        try:
            tracker=FaceGeometryTracker(runtime,model_path)
            while True:
                with self.condition:
                    self.condition.wait_for(lambda:self.pending is not None or self.stopped)
                    if self.stopped:return
                    frame,now=self.pending;self.pending=None
                anchor,packet=tracker.update(frame,now)
                with self.condition:
                    self.anchor=anchor;self.packet=packet;self.stamp=tracker.tracker.last_seen
                    self.processed_stamp=now;self.size=(frame.shape[1],frame.shape[0])
                    self.condition.notify_all()
        except Exception as error:
            with self.condition:self.error=error;self.condition.notify_all()
        finally:
            if tracker is not None:tracker.close()
    def close(self):
        with self.condition:self.stopped=True;self.condition.notify_all()
        self.thread.join(timeout=3.)

def expand_motion_model(tf,model):
    """Zero-init the extra Conv1D inputs; legacy model output must stay equal."""
    import json
    config=json.loads(model.to_json())
    for layer in config['config']['layers']:
        if layer['config'].get('name')=='motion_context':
            shape=layer['config'].get('batch_shape')
            if not shape or shape[-1]!=19:raise ValueError('Expected legacy motion_context with 19 features')
            shape[-1]=33
        if layer['config'].get('name')=='motion_projection':
            build_shape=layer.get('build_config',{}).get('input_shape')
            if build_shape:
                if build_shape[-1]!=19:raise ValueError('Unexpected motion projection build shape')
                build_shape[-1]=33
    # Keras stores graph tensor shapes in inbound_nodes as well.
    def replace_shapes(node):
        if isinstance(node,dict):
            if node.get('class_name')=='__keras_tensor__' and node['config'].get('keras_history',[None])[0]=='motion_context':node['config']['shape'][-1]=33
            for value in node.values():replace_shapes(value)
        elif isinstance(node,list):
            for value in node:replace_shapes(value)
    replace_shapes(config)
    result=tf.keras.models.model_from_json(json.dumps(config))
    for layer in result.layers:
        weights=model.get_layer(layer.name).get_weights()
        if layer.name=='motion_projection':
            kernel,bias=weights
            if kernel.shape[1]!=19:raise ValueError('Unexpected motion projection')
            weights=[np.concatenate([kernel,np.zeros((kernel.shape[0],14,kernel.shape[2]),kernel.dtype)],axis=1),bias]
        layer.set_weights(weights)
    return result

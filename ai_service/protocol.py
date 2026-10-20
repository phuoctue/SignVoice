"""Binary camera transport. Pixels stay unmirrored; mirror only the preview."""
import json
import math
import struct
import cv2
import numpy as np

MAX_PACKET = 4 * 1024 * 1024
MAX_HEADER = 128 * 1024  # bounded measured hand history + current frame metadata


def read_live_observation(message, expected_hash):
    """Validate pixel-free measured hands with the same model/XYZ contract."""
    if not isinstance(message,dict) or message.get('type')!='hand_observation':
        raise ValueError('Invalid live hand message')
    observation=message.get('observation')
    if not isinstance(observation,dict):raise ValueError('Missing live hand observation')
    width,height,stamp=(observation.get(k) for k in ('width','height','timestamp_ms'))
    if (not all(isinstance(v,int) and not isinstance(v,bool) for v in (width,height))
            or not 16<=width<=1920 or not 16<=height<=1920 or width*height>1920*1080
            or not isinstance(stamp,(int,float)) or isinstance(stamp,bool)
            or not math.isfinite(stamp) or stamp<0):raise ValueError('Invalid live hand dimensions/time')
    meta=dict(width=width,height=height,timestamp_ms=stamp,rotation=0,hand_observation=observation)
    if browser_hand_result(meta,expected_hash) is None:
        raise ValueError('Live hand model/SDK does not match selected model')
    return meta


def browser_hand_result(meta, expected_hash):
    """Use same-frame XYZ from the matching MediaPipe model, never UI XY points."""
    from types import SimpleNamespace
    observation=meta.get('hand_observation')
    if observation is None:return None
    if not isinstance(observation,dict):raise ValueError('Invalid hand observation')
    if (observation.get('schema')!='mediapipe_hand_3d_v1' or
            observation.get('sdk')!='0.10.32' or observation.get('model_sha256')!=expected_hash):
        return None  # Another export/device must use its verified CPU extractor.
    if any(observation.get(k)!=meta[k] for k in ('width','height','timestamp_ms')) or meta.get('rotation',0)!=0:
        raise ValueError('Landmarks and pixels must describe the same unrotated frame')
    hands=observation.get('landmarks');categories=observation.get('handedness')
    if not isinstance(hands,list) or len(hands)>2 or not isinstance(categories,list) or len(categories)!=len(hands):
        raise ValueError('Invalid hand count/categories')
    landmarks=[];handedness=[]
    for hand,category in zip(hands,categories):
        points=np.asarray(hand,dtype=np.float64)
        if points.shape!=(21,3) or not np.isfinite(points).all() or np.any(np.abs(points)>4):
            raise ValueError('Invalid normalized XYZ hand landmarks')
        if category not in ('Left','Right'):raise ValueError('Invalid anatomical handedness')
        landmarks.append([SimpleNamespace(x=float(x),y=float(y),z=float(z)) for x,y,z in points])
        handedness.append([SimpleNamespace(category_name=category)])
    return SimpleNamespace(hand_landmarks=landmarks,handedness=handedness,
                           hand_world_landmarks=[[] for _ in landmarks])

def browser_hand_history(meta, expected_hash):
    """Historical XYZ only; these samples do not claim to contain pixel frames."""
    if browser_hand_result(meta,expected_hash) is None:return []
    rows=meta.get('hand_history',[])
    if not isinstance(rows,list) or len(rows)>32:raise ValueError('Invalid hand history size')
    current=float(meta['timestamp_ms']);previous=-1.;results=[]
    for row in rows:
        if not isinstance(row,dict):raise ValueError('Invalid historical observation')
        stamp=row.get('timestamp_ms')
        if (not isinstance(stamp,(int,float)) or isinstance(stamp,bool) or not math.isfinite(stamp)
                or not max(0,current-2000)<=stamp<=current or stamp<=previous):
            raise ValueError('Invalid hand history timestamp')
        observation={**meta['hand_observation'],'timestamp_ms':stamp,
                     'landmarks':row.get('landmarks'),'handedness':row.get('handedness')}
        found=browser_hand_result({**meta,'timestamp_ms':stamp,'hand_observation':observation},expected_hash)
        results.append((stamp,found));previous=stamp
    return results


def read_header(packet):
    if not 5 <= len(packet) <= MAX_PACKET:
        raise ValueError('Frame size is outside the supported range')
    size = struct.unpack('!I', packet[:4])[0]
    if not 2 <= size <= MAX_HEADER or size + 4 >= len(packet):
        raise ValueError('Invalid frame header')
    meta = json.loads(packet[4:4 + size])
    width, height = int(meta['width']), int(meta['height'])
    stamp = float(meta['timestamp_ms'])
    sequence = int(meta['sequence'])
    rotation = int(meta.get('rotation', 0))
    if not (16 <= width <= 1920 and 16 <= height <= 1920 and width * height <= 1920 * 1080):
        raise ValueError('Unsupported dimensions')
    if not math.isfinite(stamp) or stamp < 0 or sequence < 0 or rotation not in (0, 90, 180, 270):
        raise ValueError('Invalid timestamp, sequence or rotation')
    if meta.get('mirrored', False):
        raise ValueError('Send raw unmirrored pixels; mirror only the preview')
    return meta, memoryview(packet)[4 + size:]

def decode_frame(packet):
    meta, payload = read_header(packet)
    width, height = int(meta['width']), int(meta['height'])
    rotation = int(meta.get('rotation', 0))
    fmt = meta['format']
    if fmt == 'jpeg':
        # Inspect JPEG SOF before decoding so an oversized image cannot allocate arbitrary memory.
        data = bytes(payload)
        pos = 2
        dimensions = None
        if data[:2] != b'\xff\xd8':raise ValueError('Invalid JPEG')
        while pos + 4 <= len(data):
            if data[pos] != 255:raise ValueError('Invalid JPEG markers')
            while pos < len(data) and data[pos] == 255:pos += 1
            marker = data[pos];pos += 1
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:continue
            length = int.from_bytes(data[pos:pos + 2], 'big')
            if length < 2 or pos + length > len(data):raise ValueError('Invalid JPEG segment')
            if marker in (0xC0,0xC1,0xC2):
                dimensions = (int.from_bytes(data[pos+5:pos+7], 'big'),int.from_bytes(data[pos+3:pos+5], 'big'))
                break
            pos += length
        if dimensions != (width, height):raise ValueError('JPEG dimensions do not match the header')
        frame = cv2.imdecode(np.frombuffer(payload, np.uint8), cv2.IMREAD_COLOR)
        if frame is None:raise ValueError('Invalid JPEG pixels')
    elif fmt in ('yuv420', 'bgra8888'):
        planes = meta['planes']
        if len(planes) != (3 if fmt == 'yuv420' else 1):raise ValueError('Invalid plane count')
        offset = 0
        decoded = []
        for i, plane in enumerate(planes):
            pw, ph = (width, height) if i == 0 else ((width + 1)//2, (height + 1)//2)
            stride, step, length = int(plane['row_stride']), int(plane['pixel_stride']), int(plane['length'])
            channels = 4 if fmt == 'bgra8888' else 1
            if stride < (pw-1)*step+channels or step < channels or length < (ph-1)*stride+(pw-1)*step+channels or offset+length > len(payload):
                raise ValueError('Invalid plane strides or lengths')
            shape = (ph,pw,4) if channels == 4 else (ph,pw)
            strides = (stride,step,1) if channels == 4 else (stride,step)
            decoded.append(np.ndarray(shape, np.uint8, buffer=payload[offset:offset+length], strides=strides).copy())
            offset += length
        if offset != len(payload):raise ValueError('Unexpected trailing pixels')
        if fmt == 'bgra8888':frame = cv2.cvtColor(decoded[0],cv2.COLOR_BGRA2BGR)
        else:
            if width % 2 or height % 2:raise ValueError('YUV420 requires even dimensions')
            planar = np.concatenate([a.ravel() for a in decoded]).reshape(height*3//2,width)
            frame = cv2.cvtColor(planar,cv2.COLOR_YUV2BGR_I420)
    else:raise ValueError('Unsupported pixel format')
    if rotation:
        frame = cv2.rotate(frame,{90:cv2.ROTATE_90_CLOCKWISE,180:cv2.ROTATE_180,270:cv2.ROTATE_90_COUNTERCLOCKWISE}[rotation])
    return meta, frame

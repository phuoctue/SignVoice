"""Optional bounded regression trace of model inputs; no camera pixel recording."""
from collections import deque
from datetime import datetime, timezone
import json
from pathlib import Path
import uuid
import numpy as np


class SessionTrace:
    def __init__(self, directory, metadata, limit=3600):
        self.directory=Path(directory) if directory else None
        self.metadata=dict(metadata)
        self.frames=deque(maxlen=limit)
        self.total=0

    def add(self, pose, wrist, context, result):
        if self.directory is None:return
        self.total+=1
        details={k:result.get(k) for k in ('sequence','timestamp_ms','landmark_source',
            'hands','processing_ms','detection_fps','timing','detector_timing','client_detector',
            'prediction_age_ms','inference','confirmed','events','context_age_ms')}
        self.frames.append((np.asarray(pose,np.float32).copy(),np.asarray(wrist,np.float32).copy(),
            np.asarray(context,np.float32).copy(),details))

    def save(self):
        if self.directory is None or not self.frames:return None
        self.directory.mkdir(parents=True,exist_ok=True)
        name=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'_'+uuid.uuid4().hex[:8]+'.npz'
        path=self.directory/name
        p,w,c,details=zip(*self.frames)
        metadata={**self.metadata,'total_frames':self.total,'saved_frames':len(p),
            'purpose':'regression_only','use_for_training':False,'contains_camera_pixels':False}
        np.savez_compressed(path,pose=np.stack(p),wrist=np.stack(w),context=np.stack(c),
            times=np.asarray([r['timestamp_ms']/1000 for r in details],np.float64),
            metadata=np.array(json.dumps(metadata,ensure_ascii=False)),
            results=np.array(json.dumps(details,ensure_ascii=False)))
        self.frames.clear()
        return path

    def update_result(self,result):
        """Attach delayed inference to its existing measured frame, not a fake sample."""
        if not self.frames:return
        details=self.frames[-1][3]
        if (details['sequence'],details['timestamp_ms'])!=(result['sequence'],result['timestamp_ms']):return
        events=details.get('events') or []
        for key in details:
            if key in result:details[key]=result[key]
        details['events']=events+[e for e in result.get('events',[]) if e not in events]

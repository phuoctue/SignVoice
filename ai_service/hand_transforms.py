"""Explicit observation transforms for paired regression/training experiments.

Never choose a transform using prediction scores. Mirroring a directional sign
may change its meaning; callers must establish label compatibility first.
"""
import copy

import numpy as np


def mirror_observation(observation, face_anchor):
    """Reflect unmirrored image XYZ and its face anchor before feature extraction.

    Image depth and timestamps stay unchanged. Left/Right is exchanged together
    with x; swapping the two detection slots alone is not this transform.
    """
    result=copy.deepcopy(observation)
    points=np.asarray(result['landmarks'],dtype=np.float64)
    labels=result['handedness']
    anchor=np.asarray(face_anchor,dtype=np.float64).copy()
    if anchor.shape!=(4,) or not np.isfinite(anchor).all():
        raise ValueError('Expected finite four-value face anchor')
    if (len(points)!=len(labels) or (len(points) and points.shape!=(len(labels),21,3))
            or not np.isfinite(points).all() or any(label not in ('Left','Right') for label in labels)):
        raise ValueError('Expected matching finite hand XYZ and Left/Right categories')
    if len(points):
        points[...,0]=1.-points[...,0]
        result['landmarks']=points.tolist()
    result['handedness']=[{'Left':'Right','Right':'Left'}[label] for label in labels]
    if anchor[3]>0:anchor[0]=1.-anchor[0]
    return result,anchor.tolist()


def mirror_aligned_sequence(pose, wrist, context, times):
    """Reflect cached normalized observations before building temporal features.

    Hand-local x was already canonicalized by handedness, so local pose stays
    unchanged. Signed image wrist-x must reflect AND exchange handedness. Missing
    hands stay zero. Refuse off-image wrists whose signed encoding is ambiguous.
    """
    p=np.asarray(pose,np.float32).copy();w=np.asarray(wrist,np.float32).copy()
    c=np.asarray(context,np.float32).copy();t=np.asarray(times,np.float64).copy()
    n=len(t)
    if (p.shape!=(n,126) or w.shape!=(n,8) or c.shape!=(n,4) or t.shape!=(n,)
            or any(not np.isfinite(a).all() for a in (p,w,c,t)) or np.any(np.diff(t)<=0)):
        raise ValueError('Expected aligned finite pose/wrist/context with increasing time')
    hands=p.reshape(n,2,21,3);wrists=w.reshape(n,2,4)
    present=np.any(hands!=0,axis=(2,3))
    x=wrists[:,:,0]
    if np.any(np.abs(x[present])>1):raise ValueError('Cannot unambiguously mirror off-image signed wrist')
    direction=np.where(np.signbit(x),-1.,1.)
    x[present]=(-direction*(1.-np.abs(x)))[present]
    wrists[~present]=0
    valid=c[:,3]>0;c[valid,0]=1.-c[valid,0]
    return p,w,c,t

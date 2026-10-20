"""Matched before/after latency only, using a held-out screen recording.

The existing overlay/preview makes this unsuitable for a labeled accuracy claim.
Never write these frames to TRAIN or choose recognition thresholds from them.
"""
import importlib.util
import json
from pathlib import Path
import time
import cv2
import numpy as np
from .engine import Engine,VideoSession


def recording_frames():
    video=Path.home()/'Downloads'/'Recording 2026-10-17 202335.mp4'
    cap=cv2.VideoCapture(str(video));assert cap.isOpened()
    frames=[]
    for start in (1.,8.,18.,27.):
        for i in range(20):
            stamp=round((start+i/15)*1000)
            cap.set(cv2.CAP_PROP_POS_MSEC,stamp);ok,image=cap.read();assert ok
            h,w=image.shape[:2]
            image=image[round(h*.113):round(h*.478),round(w*.03):round(w*.985)]
            image=cv2.flip(image,1)  # Recover orientation from the mirrored front preview.
            frames.append((stamp,image))
    cap.release();return frames


def main():
    frames=recording_frames();engine=Engine(Path(__file__).resolve().parents[2])
    before_path=Path(__file__).parent/'reports/camera_20261017/before/engine.py'
    spec=importlib.util.spec_from_file_location('ai_service.before_engine',before_path)
    before=importlib.util.module_from_spec(spec);spec.loader.exec_module(before)
    report=dict(frames=len(frames),same_pixels=True,vlm_disabled_for_latency_comparison=True,
        source='screen_recording_with_existing_overlay',accuracy_measured=False,rows={})
    for name,create in [('before',lambda:before.VideoSession(engine,'words')),('after',lambda:VideoSession(engine,'words',False))]:
        session=create();times=[];hands=[];stage=[]
        try:
            for i,(stamp,image) in enumerate(frames):
                start=time.perf_counter();result=session.process(dict(sequence=i,timestamp_ms=stamp),image.copy())
                times.append(1000*(time.perf_counter()-start));hands.append(result['hands'])
                if 'timing' in result:stage.append(result['timing'])
        finally:session.close()
        report['rows'][name]=dict(median_ms=float(np.median(times[3:])),p90_ms=float(np.quantile(times[3:],.9)),
            mean_ms=float(np.mean(times[3:])),frames_with_hands=sum(h>0 for h in hands),
            frames_with_two_hands=sum(h==2 for h in hands),timing=stage)
        print(name,json.dumps({k:v for k,v in report['rows'][name].items() if k!='timing'}),flush=True)
    report['median_speedup']=report['rows']['before']['median_ms']/report['rows']['after']['median_ms']
    output=Path(__file__).parent/'reports/camera_20261017/latency_comparison.json'
    output.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('Saved',output)


if __name__=='__main__':main()

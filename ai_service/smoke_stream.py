"""Replay held-out pixels through the real socket. Never train or tune on this."""
import asyncio,json,struct,time
from pathlib import Path
import cv2,httpx,numpy as np
from websockets.asyncio.client import connect

async def main():
    async def receive_result(ws):
        while True:
            result=json.loads(await asyncio.wait_for(ws.recv(),timeout=20))
            if result['type']!='frame_received':return result
    async with httpx.AsyncClient(trust_env=False) as client:
        health=(await client.get('http://127.0.0.1:8001/health')).json()
    assert health['ready'] and health['word_classes']>0
    video=Path(__file__).resolve().parents[2]/'evaluation_videos/raw_camera/raw_test_20261012_102354_1bf1777f.mp4'
    cap=cv2.VideoCapture(str(video));assert cap.isOpened()
    rows=[]
    async with connect('ws://127.0.0.1:8001/v1/stream',max_size=4*1024*1024) as ws:
        await ws.send(json.dumps({'mode':'words','vision':False}));ready=json.loads(await ws.recv());assert ready['type']=='ready'
        for i in range(18):
            cap.set(cv2.CAP_PROP_POS_MSEC,3000+i*100)
            ok,frame=cap.read();assert ok
            frame=cv2.resize(frame,(640,480));ok,jpeg=cv2.imencode('.jpg',frame);assert ok
            meta=dict(sequence=i,timestamp_ms=3000+i*100,format='jpeg',width=640,height=480,rotation=0,mirrored=False)
            h=json.dumps(meta).encode();t=time.perf_counter()
            await ws.send(struct.pack('!I',len(h))+h+jpeg.tobytes())
            result=await receive_result(ws)
            assert result['type']=='result',result
            assert result['sequence']==i and result['timestamp_ms']==meta['timestamp_ms']
            assert 0<=result['hands']<=2
            assert result['opencv']['enabled'] and result['opencv']['recovery_guidance_enabled']
            assert result['opencv']['quality']['advisory_only']
            rows.append(dict(hands=result['hands'],processing_ms=result['processing_ms'],roundtrip_ms=round(1000*(time.perf_counter()-t),1),events=result['events'],
                opencv_regions=len(result['opencv']['regions']),opencv_flow_vectors=len(result['opencv']['flow_vectors'])))
        # Reject non-monotonic data instead of corrupting the temporal buffer.
        await ws.send(struct.pack('!I',len(h))+h+jpeg.tobytes())
        assert (await receive_result(ws))['type']=='error'
    cap.release()
    # Fresh connection has its own timestamp domain and mode.
    async with connect('ws://127.0.0.1:8001/v1/stream') as ws:
        await ws.send(json.dumps({'mode':'digits','vision':False}));assert json.loads(await ws.recv())['type']=='ready'
        blank=np.zeros((480,640,3),np.uint8);_,jpg=cv2.imencode('.jpg',blank)
        meta.update(sequence=0,timestamp_ms=1);h=json.dumps(meta).encode()
        await ws.send(struct.pack('!I',len(h))+h+jpg.tobytes())
        result=await receive_result(ws);assert result['type']=='result' and result['hands']==0
    report=dict(model=health,frames=len(rows),frames_with_hands=sum(r['hands']>0 for r in rows),median_processing_ms=float(np.median([r['processing_ms'] for r in rows])),
        timestamps_preserved=True,out_of_order_rejected=True,fresh_session_isolated=True,accuracy_measured=False,
        frames_with_opencv_regions=sum(r['opencv_regions']>0 for r in rows),frames_with_opencv_flow=sum(r['opencv_flow_vectors']>0 for r in rows),rows=rows)
    out=Path(__file__).with_name('smoke_report.json');out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'},ensure_ascii=False,indent=2))

if __name__=='__main__':asyncio.run(main())

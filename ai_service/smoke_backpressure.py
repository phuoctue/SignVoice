"""Burst-test real receipt ACKs and the one-frame queue, without camera input."""
import asyncio,json,struct,time
from pathlib import Path
import cv2
import numpy as np
from websockets.asyncio.client import connect


async def main():
    _,jpg=cv2.imencode('.jpg',np.zeros((240,320,3),np.uint8))
    async with connect('ws://127.0.0.1:8001/v1/stream',max_size=4*1024**2) as ws:
        await ws.send(json.dumps(dict(mode='digits',vision=False)))
        ready=json.loads(await ws.recv());assert ready['stream_protocol']==2
        start=time.perf_counter()
        for i in range(40):
            h=json.dumps(dict(sequence=i,timestamp_ms=1+i*67,width=320,height=240,format='jpeg',rotation=0,mirrored=False)).encode()
            await ws.send(struct.pack('!I',len(h))+h+jpg.tobytes())
        receipts=[];results=[]
        while not results or results[-1]['sequence']!=39 or len(receipts)!=40:
            message=json.loads(await asyncio.wait_for(ws.recv(),timeout=20))
            if message['type']=='frame_received':receipts.append(message['sequence'])
            else:
                assert message['type']=='result',message
                assert message['mode']=='digits' and message['confirmed'] is None and not message['events']
                assert 'candidates' not in message
                results.append(message)
        assert receipts==list(range(40)) and results[-1]['dropped_frames']>0
        assert len(results)<40
        report=dict(receipts=len(receipts),processed=len(results),last_sequence=results[-1]['sequence'],
            dropped=results[-1]['dropped_frames'],elapsed_ms=round(1000*(time.perf_counter()-start)),
            bounded_queue_verified=True,mode_isolated=True,single_result_only=True)
    output=Path(__file__).parent/'reports/camera_20261017/backpressure_smoke.json'
    output.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))


if __name__=='__main__':asyncio.run(main())

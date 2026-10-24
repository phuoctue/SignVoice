"""Independent camera AI service. No MongoDB or Node backend dependency."""
import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
import os
from pathlib import Path
import secrets
from fastapi import FastAPI,HTTPException,WebSocket,WebSocketDisconnect,Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel,Field
from .protocol import decode_frame,read_header,read_live_observation
from .language import compose
from .latest_frame import LatestFrameMailbox

DEFAULT_ORIGINS=','.join(f'http://{host}:{port}' for host in ('localhost','127.0.0.1') for port in (8080,3000,3001))
ORIGINS=[x.strip() for x in os.getenv('AI_ALLOWED_ORIGINS',DEFAULT_ORIGINS).split(',') if x.strip()]

def authorized(token):
    expected=os.getenv('AI_SERVICE_TOKEN','')
    return not expected or secrets.compare_digest(str(token),expected)

@asynccontextmanager
async def lifespan(app):
    from .engine import Engine
    from .model_selection import resolve_selection
    selection=await asyncio.to_thread(resolve_selection,os.getenv('SIGNVOICE_MODEL_DIR') or None)
    app.state.engine=await asyncio.to_thread(Engine,selection['model_dir'])
    app.state.clients=0
    yield

app=FastAPI(title='SignVoice Camera AI',version='1.0.0',lifespan=lifespan)
app.add_middleware(CORSMiddleware,allow_origins=ORIGINS,allow_methods=['GET','POST'],allow_headers=['Content-Type','Authorization'])

@app.get('/health')
async def health():return app.state.engine.info()

class ComposeRequest(BaseModel):
    words:list[str]=Field(max_length=120)

@app.post('/v1/compose')
async def sentence(body:ComposeRequest,request:Request):
    if not authorized(request.headers.get('authorization','').removeprefix('Bearer ')):raise HTTPException(401,'Invalid AI service token')
    if any(len(w)>100 or not w.strip() for w in body.words):raise HTTPException(422,'Invalid words')
    return await compose(body.words)

@app.websocket('/v1/stream')
async def stream(ws:WebSocket):
    origin=ws.headers.get('origin')
    if origin and origin not in ORIGINS:
        await ws.close(code=1008);return
    await ws.accept()
    session=None;pool=None;counted=False
    try:
        hello=await asyncio.wait_for(ws.receive_json(),timeout=10.)
        if not authorized(hello.get('token','')):
            await ws.close(code=1008,reason='Invalid token');return
        mode=hello.get('mode','words')
        if mode not in ('words','letters','digits','all'):raise ValueError('Invalid recognition mode')
        if app.state.clients>=2:
            await ws.close(code=1013,reason='AI service is busy');return
        app.state.clients+=1;counted=True
        # One owner thread for each MediaPipe session; no detector state crosses clients.
        pool=ThreadPoolExecutor(max_workers=1,thread_name_prefix='signvoice-stream')
        loop=asyncio.get_running_loop()
        # Old clients may retain vision=True in preferences. Camera recognition
        # now always uses the trained model directly, without an LM veto.
        session=await loop.run_in_executor(pool,app.state.engine.session,mode,False)
        diagnostic = hello.get('diagnostic') is True
        diagnostic_identity = None
        if diagnostic:
            from .diagnostic_replay import identity
            session.worker.enable_diagnostics()
            diagnostic_identity = identity(app.state.engine, mode)
        await ws.send_json(dict(type='ready',**app.state.engine.info(),worker_identity=diagnostic_identity))
        mailbox=LatestFrameMailbox();observations=LatestFrameMailbox();send_lock=asyncio.Lock()
        recognition_ready=asyncio.Event();last_publication=-1
        session.worker.on_update=lambda:loop.call_soon_threadsafe(recognition_ready.set)
        async def send(data):
            nonlocal last_publication
            async with send_lock:
                if data.get('type')=='result':
                    publication=data.get('publication',0)
                    if publication<=last_publication:return
                    last_publication=publication
                    if diagnostic:
                        data = {**data, 'worker_diagnostic': session.worker.drain_diagnostics(),
                                'dropped_observations': observations.dropped}
                await ws.send_json(data)
        async def receive_frames():
            previous_stamp=-1.;previous_sequence=-1
            while True:
                incoming=await asyncio.wait_for(ws.receive(),timeout=35.)
                if incoming['type']=='websocket.disconnect':raise WebSocketDisconnect(incoming.get('code',1000))
                if incoming.get('text') is not None:
                    if len(incoming['text'].encode('utf-8'))>16384:
                        raise ValueError('Unsupported live observation message')
                    meta=read_live_observation(json.loads(incoming['text']),app.state.engine.info()['hand_model_sha256'])
                    observations.offer(meta)
                    await send(dict(type='observation_received',timestamp_ms=meta['timestamp_ms']))
                    continue
                packet=incoming.get('bytes')
                if packet is None:raise ValueError('Expected a camera packet')
                meta,_=read_header(packet)
                stamp=float(meta['timestamp_ms']);sequence=int(meta['sequence'])
                if stamp<=previous_stamp or sequence<=previous_sequence:raise ValueError('Frame timestamps and sequences must strictly increase')
                previous_stamp=stamp;previous_sequence=sequence
                mailbox.offer(packet)
                # Receipt ACK is independent of inference. There is at most one
                # waiting frame; a newer frame replaces it instead of adding lag.
                await send(dict(type='frame_received',sequence=sequence))
        async def process_frames():
            while True:
                packet=await mailbox.get()
                def process():
                    meta,frame=decode_frame(packet)
                    return session.process(meta,frame)
                result=await loop.run_in_executor(pool,process)
                result['dropped_frames']=mailbox.dropped
                await send(result)
        async def publish_recognition():
            while True:
                await recognition_ready.wait();recognition_ready.clear()
                result=await loop.run_in_executor(pool,session.recognition_update)
                if result is not None:
                    result['dropped_frames']=mailbox.dropped
                    await send(result)
        async def process_observations():
            while True:
                meta=await observations.get()
                result=await loop.run_in_executor(pool,session.observe,meta)
                if result is not None:
                    result['dropped_frames']=mailbox.dropped
                    await send(result)
        tasks=[asyncio.create_task(receive_frames()),asyncio.create_task(process_frames()),
               asyncio.create_task(publish_recognition()),asyncio.create_task(process_observations())]
        try:
            done,_=await asyncio.wait(tasks,return_when=asyncio.FIRST_EXCEPTION)
            for task in done:task.result()
        finally:
            session.worker.on_update=None
            for task in tasks:task.cancel()
            await asyncio.gather(*tasks,return_exceptions=True)
    except WebSocketDisconnect:pass
    except (ValueError,KeyError,TypeError,TimeoutError) as exc:
        try:
            await ws.send_json(dict(type='error',message=str(exc)[:180]));await ws.close(code=1008)
        except RuntimeError:pass
    except Exception:
        import logging
        logging.exception('Camera session failed')
        try:
            await ws.send_json(dict(type='error',message='Service AI gặp lỗi; hãy thử kết nối lại.'));await ws.close(code=1011)
        except RuntimeError:pass
    finally:
        if session is not None and pool is not None:
            await asyncio.get_running_loop().run_in_executor(pool,session.close)
        if pool:pool.shutdown(wait=False,cancel_futures=True)
        if counted:app.state.clients-=1

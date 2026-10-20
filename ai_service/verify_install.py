"""Check the installed model and actual WebSocket pipeline, without private test videos."""
import argparse
import asyncio
import json
import struct

import cv2
import httpx
import numpy as np
from websockets.asyncio.client import connect


async def verify(url):
    url = url.rstrip('/')
    async with httpx.AsyncClient(trust_env=False, timeout=30) as client:
        response = await client.get(url + '/health')
        response.raise_for_status()
        health = response.json()
    if not health.get('ready') or health.get('word_classes', 0) < 1:
        raise RuntimeError('AI is not ready with a complete model.')
    if not health.get('embedding_enabled') and health.get('word_engine') != 'probability_ensemble':
        raise RuntimeError('Expected both temporal and embedding models.')
    websocket_url = url.replace('https://', 'wss://', 1).replace('http://', 'ws://', 1) + '/v1/stream'
    blank = np.zeros((480, 640, 3), np.uint8)
    ok, encoded = cv2.imencode('.jpg', blank)
    if not ok:
        raise RuntimeError('OpenCV JPEG encoding failed.')
    checks = []
    for mode in ('words', 'digits', 'letters', 'all'):
        async with connect(websocket_url, open_timeout=30, max_size=4 * 1024**2) as socket:
            await socket.send(json.dumps(dict(mode=mode, vision=False)))
            ready = json.loads(await asyncio.wait_for(socket.recv(), 30))
            if ready.get('type') != 'ready':
                raise RuntimeError('WebSocket did not initialize: ' + str(ready))
            metadata = json.dumps(dict(sequence=0, timestamp_ms=1, format='jpeg',
                                      width=640, height=480, rotation=0, mirrored=False)).encode()
            await socket.send(struct.pack('!I', len(metadata)) + metadata + encoded.tobytes())
            while True:
                result = json.loads(await asyncio.wait_for(socket.recv(), 30))
                if result.get('type') == 'error':
                    raise RuntimeError(str(result))
                if result.get('type') == 'result':
                    if result.get('hands') != 0 or result.get('sequence') != 0:
                        raise RuntimeError('Unexpected blank-frame result: ' + str(result))
                    checks.append(dict(mode=mode, websocket=True, blank_frame=True))
                    break
    print(json.dumps(dict(ready=True, word_classes=health['word_classes'],
        word_engine=health.get('word_engine'), manifest_sha256=health.get('model_manifest_sha256'),
        checks=checks, recognition_accuracy_measured=False), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:8001')
    args = parser.parse_args()
    asyncio.run(verify(args.url))


if __name__ == '__main__':
    main()

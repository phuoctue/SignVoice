import asyncio
import json
import os
import struct
import unittest
from unittest.mock import patch
import cv2
import httpx
import numpy as np
from ai_service.protocol import decode_frame
from ai_service.language import compose

def packet(meta,pixels):
    header=json.dumps(dict(sequence=1,timestamp_ms=100,rotation=0,mirrored=False,**meta)).encode()
    return struct.pack('!I',len(header))+header+pixels

class PixelTests(unittest.TestCase):
    def test_jpeg_orientation_and_dimensions(self):
        image=np.zeros((24,32,3),np.uint8);image[:,:16]=(0,0,255);image[:,16:]=(255,0,0)
        ok,jpeg=cv2.imencode('.jpg',image);self.assertTrue(ok)
        data=packet(dict(format='jpeg',width=32,height=24),jpeg.tobytes())
        meta,result=decode_frame(data)
        self.assertEqual(result.shape,(24,32,3))
        self.assertGreater(result[12,5,2],240)
        self.assertGreater(result[12,27,0],240)
        header=json.loads(data[4:4+int.from_bytes(data[:4],'big')]);header['rotation']=90
        encoded=json.dumps(header).encode()
        _,rotated=decode_frame(struct.pack('!I',len(encoded))+encoded+jpeg.tobytes())
        self.assertEqual(rotated.shape,(32,24,3))
        with self.assertRaises(ValueError):decode_frame(packet(dict(format='jpeg',width=33,height=24),jpeg.tobytes()))
    def test_bgra_padding_and_no_mirroring(self):
        image=np.zeros((24,32,4),np.uint8);image[:,:16]=(0,0,255,255);image[:,16:]=(255,0,0,255)
        padded=np.pad(image,((0,0),(0,3),(0,0)))
        _,result=decode_frame(packet(dict(format='bgra8888',width=32,height=24,
            planes=[dict(row_stride=140,pixel_stride=4,length=padded.nbytes)]),padded.tobytes()))
        np.testing.assert_array_equal(result,image[:,:,:3])
    def test_yuv_pixel_stride_two(self):
        image=np.full((24,32,3),(40,150,230),np.uint8)
        yuv=cv2.cvtColor(image,cv2.COLOR_BGR2YUV_I420).ravel()
        y=yuv[:768].reshape(24,32);u=yuv[768:960].reshape(12,16);v=yuv[960:].reshape(12,16)
        planes=[];pixels=b''
        for i,a in enumerate([y,u,v]):
            step=1 if i==0 else 2
            padded=np.zeros((a.shape[0],a.shape[1]*step+4),np.uint8);padded[:,:a.shape[1]*step:step]=a
            planes.append(dict(row_stride=padded.shape[1],pixel_stride=step,length=padded.nbytes));pixels+=padded.tobytes()
        _,result=decode_frame(packet(dict(format='yuv420',width=32,height=24,planes=planes),pixels))
        np.testing.assert_allclose(result,image,atol=2)
    def test_reject_invalid_packets(self):
        for data in [b'',b'\x00\x00\xff\xffhello',packet(dict(format='jpeg',width=50000,height=50000),b'broken')]:
            with self.assertRaises((ValueError,KeyError)):decode_frame(data)

class LanguageTests(unittest.IsolatedAsyncioTestCase):
    async def test_embedding_model_is_never_selected_for_chat(self):
        chosen=[]
        class Client:
            def __init__(self,*a,**kw):pass
            async def __aenter__(self):return self
            async def __aexit__(self,*a):pass
            async def get(self,*a,**kw):
                return httpx.Response(200,json={'data':[{'id':'text-embedding-nomic-embed-text-v1.5'},{'id':'qwen2.5-vl-7b-instruct'}]},request=httpx.Request('GET','http://test/models'))
            async def post(self,*a,**kw):
                chosen.append(kw['json']['model'])
                return httpx.Response(200,json={'choices':[{'message':{'content':'{"text":"Chào."}'}}]},request=httpx.Request('POST','http://test/chat'))
        with patch.dict(os.environ,{'LM_STUDIO_MODEL':''}),patch('ai_service.language.httpx.AsyncClient',Client):
            result=await compose(['chào'])
        self.assertTrue(result['used_lm']);self.assertEqual(chosen,['qwen2.5-vl-7b-instruct'])
    async def test_lm_cannot_change_words_or_negation(self):
        async def run(text):
            class Client:
                def __init__(self,*a,**kw):pass
                async def __aenter__(self):return self
                async def __aexit__(self,*a):pass
                async def post(self,*a,**kw):
                    return httpx.Response(200,json={'choices':[{'message':{'content':json.dumps({'text':text},ensure_ascii=False)}}]},request=httpx.Request('POST','http://test'))
            with patch.dict(os.environ,{'LM_STUDIO_MODEL':'test'}),patch('ai_service.language.httpx.AsyncClient',Client):
                return await compose(['tôi','không muốn','ăn'])
        self.assertTrue((await run('Tôi không muốn ăn.'))['used_lm'])
        rejected=await run('Tôi muốn ăn.')
        self.assertFalse(rejected['used_lm']);self.assertIn('không muốn',rejected['text'])
        self.assertFalse((await run('Tôi không muốn ăn bánh mì.'))['used_lm'])
        self.assertFalse((await run('Ăn tôi không muốn.'))['used_lm'])

if __name__=='__main__':unittest.main()

import asyncio
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import numpy as np
from ai_service.latest_frame import LatestFrameMailbox
from ai_service.vision import ReferenceLibrary, VisionWorker, accepted_review, should_review, verify_images, visual_sheet


class LatestFrameTests(unittest.IsolatedAsyncioTestCase):
    async def test_newest_pending_frame_replaces_backlog(self):
        mailbox=LatestFrameMailbox()
        mailbox.offer(b'first')
        self.assertEqual(await mailbox.get(),b'first')
        for i in range(50):mailbox.offer(str(i).encode())
        self.assertEqual(mailbox.queue.qsize(),1)
        self.assertEqual(await mailbox.get(),b'49')
        self.assertEqual(mailbox.dropped,49)


class VisionTests(unittest.TestCase):
    def test_slow_review_is_not_invalidated_by_repeated_same_sign(self):
        self.assertFalse(should_review('rau','rau',13.,True,None))
        self.assertFalse(should_review('rau','rau',30.,False,'rau'))
        self.assertTrue(should_review('rau','rau',7.,False,None))
        self.assertTrue(should_review('other','rau',1.,True,None))
        self.assertFalse(should_review(None,'rau',30.,False,None))

    def test_only_latest_same_mode_colab_and_visual_agreement_is_accepted(self):
        review=dict(job=2,status='matched',colab_supported=True,label='rau',expected_label='rau')
        self.assertTrue(accepted_review(review,2,{'rau'}))
        for change in [dict(job=1),dict(colab_supported=False),dict(label='other'),dict(status='uncertain')]:
            self.assertFalse(accepted_review({**review,**change},2,{'rau'}))
        self.assertFalse(accepted_review(review,2,{'a'}))

    def test_empty_or_missing_reference_never_calls_lm(self):
        class References:
            def get(self,label):return []
        with patch('ai_service.vision.httpx.Client') as client:
            result=verify_images([np.zeros((32,32,3),np.uint8)],['rau'],References())
            self.assertEqual(result['status'],'no_reference');client.assert_not_called()
        self.assertEqual(visual_sheet([],['rau'],References()),(None,[]))

    def test_worker_does_not_block_capture_or_publish_after_close(self):
        entered=threading.Event();release=threading.Event()
        def slow(*args):
            entered.set();release.wait(2);return dict(status='matched',label='rau')
        with patch('ai_service.vision.verify_images',side_effect=slow):
            worker=VisionWorker(None)
            job=dict(id=1,label='rau',candidates=['rau'],frames=[],timestamp_ms=1000,colab_supported=True,score=.9)
            worker.submit(job);self.assertTrue(entered.wait(1))
            started=time.monotonic();self.assertTrue(worker.poll()[1])
            self.assertLess(time.monotonic()-started,.05)
            worker.close();release.set();worker.thread.join(1)
            self.assertIsNone(worker.poll()[0])

    def test_reference_index_excludes_test_val_bad_labels_numeric_and_b_variant(self):
        import csv,io,zipfile
        base=dict(kind='rgb',rgb_train_candidate='True',fixed_split='train',semantic_review='',source='user_Dataset.tgz',label='rau',bytes='20',sha256='x',sha1='a'*40,path='rgb/W0001N.mp4')
        rows=[base,{**base,'label':'test_only','fixed_split':'test'},
            {**base,'label':'val_only','fixed_split':'val'},{**base,'label':'bad','semantic_review':'false'},
            {**base,'label':'numeric','kind':'skeleton'},{**base,'label':'regional_b','path':'rgb/W0001B.mp4'},
            {**base,'label':'unproven_training_candidate','fixed_split':'','sha1':'b'*40}]
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'bundle.zip';csv_text=io.StringIO();writer=csv.DictWriter(csv_text,fieldnames=base.keys());writer.writeheader();writer.writerows(rows)
            with zipfile.ZipFile(path,'w') as archive:archive.writestr('manifest_all_sources.csv',csv_text.getvalue())
            lib=ReferenceLibrary(path,Path(d)/'cache',['a'*16]);lib.get('not_present')
            self.assertEqual(set(lib.index),{'rau'})

    def test_multimodal_request_contains_image_and_rejects_invalid_label(self):
        class References:
            def get(self,label):return [np.zeros((32,32,3),np.uint8)]*3
        class Response:
            def raise_for_status(self):pass
            def json(self):return {'choices':[{'message':{'content':'{"reference":99}'}}]}
        with patch('ai_service.vision.httpx.Client') as factory:
            client=factory.return_value.__enter__.return_value
            client.post.return_value=Response()
            result=verify_images([np.zeros((32,32,3),np.uint8)]*4,['rau'],References())
            self.assertEqual(result['status'],'unavailable')
            body=client.post.call_args.kwargs['json']
            self.assertTrue(body['messages'][1]['content'][1]['image_url']['url'].startswith('data:image/jpeg;base64,'))


if __name__=='__main__':unittest.main()

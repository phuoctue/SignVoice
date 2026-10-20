import unittest
import json
import struct
from types import SimpleNamespace
import numpy as np
from .model_runtime import CompletedSignHold, LiveSession
from .protocol import browser_hand_history, read_header, MAX_HEADER


class LetterSequenceTests(unittest.TestCase):
    def packet(self):
        base=dict(schema='mediapipe_hand_3d_v1',sdk='0.10.32',model_sha256='a'*64,
                  width=640,height=480,timestamp_ms=1000,landmarks=[],handedness=[])
        rows=[dict(timestamp_ms=t,landmarks=[[[.3+i*.002,.4+i*.003,0.] for i in range(21)]],
                   handedness=['Left']) for t in (400,467,534,601,668,735)]
        return dict(width=640,height=480,timestamp_ms=1000,rotation=0,hand_observation=base,hand_history=rows)

    def test_history_keeps_order_and_validates_each_observation(self):
        rows=browser_hand_history(self.packet(),'a'*64)
        self.assertEqual([stamp for stamp,_ in rows],[400,467,534,601,668,735])
        self.assertEqual(len(rows[0][1].hand_landmarks),1)
        for bad in ('future','order','nan','size'):
            meta=self.packet()
            if bad=='future':meta['hand_history'][-1]['timestamp_ms']=1001
            if bad=='order':meta['hand_history'].reverse()
            if bad=='nan':meta['hand_history'][0]['landmarks'][0][0][0]=float('nan')
            if bad=='size':meta['hand_history']*=6
            with self.assertRaises(ValueError,msg=bad):browser_hand_history(meta,'a'*64)

    def test_another_detector_cannot_supply_history(self):
        self.assertEqual(browser_hand_history(self.packet(),'b'*64),[])

    def test_transport_accepts_bounded_history_but_rejects_oversized_header(self):
        meta=self.packet();meta.update(sequence=1,format='jpeg')
        meta['hand_history']*=5
        header=json.dumps(meta).encode()
        self.assertGreater(len(header),8192)
        decoded,_=read_header(struct.pack('!I',len(header))+header+b'pixels')
        self.assertEqual(len(decoded['hand_history']),30)
        with self.assertRaises(ValueError):
            read_header(struct.pack('!I',MAX_HEADER+1)+b' '*(MAX_HEADER+1)+b'pixels')

    def test_completed_letter_hold_releases_on_a_new_wrist_movement(self):
        p=np.zeros((2,21,3),np.float32)
        p[1,:,0]=np.arange(21)*.01;p[1,:,1]=np.arange(21)*.02
        w=np.zeros((2,4),np.float32);w[1]=[.4,.4,.08,.5]
        hold=CompletedSignHold();hold.capture(p.ravel(),1.,w.ravel())
        jitter=w.copy();jitter[1,0]+=.006
        self.assertTrue(hold.update(p.ravel(),1.1,jitter.ravel()))
        moved=w.copy();moved[1,1]+=.12
        self.assertFalse(hold.update(p.ravel(),1.2,moved.ravel()))

    def test_static_letter_can_repeat_after_a_real_unrecognized_interval(self):
        class Recognizer:
            mode='letters'
            labels=['ă','a'];dynamic_labels={'ă'};dynamic=np.array([True,False]);word_head=None
            config={};score=np.array([-.5,.9],np.float32)
            def setting(self,key,default):return self.config.get(key,default)
            def predict(self,*args,**kwargs):return self.score.copy(),np.array([False,False])
            def domain_collision(self,scores):return None
        recognizer=Recognizer();session=LiveSession(recognizer)
        pose=np.ones(126,np.float32);wrist=np.zeros(8,np.float32)
        for t in np.arange(0,1,.1):session.update(pose,wrist,t)
        self.assertEqual([e['label'] for e in session.events],['a'])
        recognizer.score[:]=-1
        for t in np.arange(1,2,.1):session.update(pose,wrist,t)
        recognizer.score[:]=[-.5,.9]
        for t in np.arange(2,3,.1):session.update(pose,wrist,t)
        self.assertEqual([e['label'] for e in session.events],['a','a'])


if __name__=='__main__':unittest.main()

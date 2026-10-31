import json,unittest
import numpy as np
from .face_geometry import geometry_frame, geometry_sequence, geometry_packet, mirror_packet
from . import model_runtime as runtime

def packet(stamp=1.):
    points=[[.4,.2],[.6,.2],[.5,.3],[.5,.4],[.2,.3],[.8,.3]]
    return geometry_packet(points,stamp,640,480)

class FaceGeometryTests(unittest.TestCase):
    def test_roi_mapping_uses_original_image_coordinates_without_mutating_result(self):
        from .face_geometry import remap_face_detections
        from types import SimpleNamespace as S
        detection=S(keypoints=[S(x=.5,y=.25)],bounding_box=S(origin_x=10,origin_y=20,width=30,height=40))
        result=S(detections=[detection])
        mapped=remap_face_detections(result,(160,0,480,234),(640,360))
        self.assertAlmostEqual(mapped.detections[0].keypoints[0].x,.5)
        self.assertAlmostEqual(mapped.detections[0].keypoints[0].y,.1625)
        self.assertEqual(mapped.detections[0].bounding_box.origin_x,170)
        self.assertEqual(detection.keypoints[0].y,.25)

    def test_small_face_fallback_preserves_full_frame_result_and_is_bounded(self):
        from .face_geometry import detect_face_with_fallback
        import mediapipe as mp
        from types import SimpleNamespace as S
        frame=mp.Image(image_format=mp.ImageFormat.SRGB,data=np.zeros((360,640,3),np.uint8))
        found=S(detections=[S(keypoints=[S(x=.5,y=.5)],bounding_box=S(origin_x=0,origin_y=0,width=10,height=10))])
        class Detector:
            def __init__(self,results):self.results=iter(results);self.shapes=[]
            def detect(self,img):self.shapes.append(img.numpy_view().shape);return next(self.results)
        full=Detector([found]);self.assertIs(detect_face_with_fallback(full,frame),found)
        fallback=Detector([S(detections=[]),found]);mapped=detect_face_with_fallback(fallback,frame)
        self.assertEqual(fallback.shapes,[(360,640,3),(234,320,3)])
        self.assertAlmostEqual(mapped.detections[0].keypoints[0].y,.325)
        empty=Detector([S(detections=[]),S(detections=[])])
        self.assertEqual(detect_face_with_fallback(empty,frame).detections,[])

    def sample(self):
        p=np.zeros((2,21,3),np.float32);w=np.zeros((2,4),np.float32)
        p[1,8]=[.5,-.2,0];w[1]=[-.7,.3,.2,.4]
        return p.reshape(126),w.reshape(8)

    def test_train_arrays_and_live_json_packet_are_identical(self):
        p,w=self.sample();g=packet()
        np.testing.assert_array_equal(geometry_frame(p,w,g,1.1),geometry_frame(p,w,json.loads(json.dumps(g)),1.1))
        self.assertEqual(geometry_frame(p,w,g,1.1).shape,(14,))

    def test_masks_absent_hand_and_stale_or_future_face(self):
        p,w=self.sample();g=packet()
        f=geometry_frame(p,w,g,1.1);np.testing.assert_array_equal(f[:6],0)
        self.assertEqual(f[11],1);self.assertEqual(f[13],1)
        for now in [.9,2.21]:np.testing.assert_array_equal(geometry_frame(p,w,g,now),0)
        np.testing.assert_array_equal(geometry_frame(p,w,None,1.1),0)

    def test_mirror_keeps_distances_and_flips_only_signed_directions(self):
        from .hand_transforms import mirror_aligned_sequence
        p,w=self.sample();pp,ww,_,_=mirror_aligned_sequence(p[None],w[None],np.array([[.5,.2,.46,1]]),np.array([1.]))
        a=geometry_frame(p,w,packet(),1.1);b=geometry_frame(pp[0],ww[0],mirror_packet(packet()),1.1)
        np.testing.assert_allclose(a[[6,7,9,10,11,13]],b[[6,7,9,10,11,13]],atol=2e-6)
        self.assertAlmostEqual(float(a[8]),-float(b[8]),places=6)

    def test_sequence_preserves_all_19_existing_motion_channels_exactly(self):
        p,w=self.sample();pp=np.tile(p,(12,1));ww=np.tile(w,(12,1));c=np.tile([.5,.2,.46,1],(12,1));t=np.arange(12)/15+1
        old=runtime.word_temporal_features(pp,ww,c,t,48)
        new=geometry_sequence(runtime,pp,ww,c,t,[packet()]*12,now=t[-1])
        np.testing.assert_array_equal(new[0],old[0]);np.testing.assert_array_equal(new[1][:,:19],old[1])
        self.assertEqual(new[1].shape,(48,33));self.assertTrue(np.isfinite(new[1]).all())

    def test_bad_packets_are_rejected_not_filled_with_invented_ears(self):
        p,w=self.sample()
        for points in ([[0,0]]*5,[[float('nan'),0]]*6):
            with self.assertRaises(ValueError):geometry_packet(points,1,640,480)
        bad=packet();bad['width']=480
        with self.assertRaises(ValueError):geometry_frame(p,w,bad,1.1,expected_size=(640,480))

    def test_lookup_never_uses_future_packets_and_expires_last_measurement(self):
        from .face_geometry import GeometryTimeline
        timeline=GeometryTimeline([packet(1.),packet(2.)])
        result=timeline.at([.9,1.,1.9,2.,3.21])
        self.assertIsNone(result[0]);self.assertIsNone(result[-1])
        self.assertEqual([p['timestamp_ms'] for p in result[1:4]],[1000.,1000.,2000.])
        result[1]['keypoints'][0][0]=999
        self.assertNotEqual(timeline.at([1.])[0]['keypoints'][0][0],999)

    def test_millisecond_roundtrip_does_not_reject_a_same_frame_face(self):
        from .face_geometry import FaceGeometryTracker,GeometryTimeline
        now=84/(30000/1001)
        g=packet(now);p,w=self.sample()
        self.assertEqual(geometry_frame(p,w,g,now)[13],1.)
        tracker=FaceGeometryTracker.__new__(FaceGeometryTracker);tracker.packet=g
        self.assertIsNotNone(tracker.snapshot(now))
        self.assertIsNotNone(GeometryTimeline([g]).at([now])[0])

    def test_worker_snapshot_masks_future_and_wrong_dimensions(self):
        from .face_geometry import GeometryContextWorker
        import threading
        worker=GeometryContextWorker.__new__(GeometryContextWorker)
        worker.condition=threading.Condition();worker.error=None;worker.anchor=np.ones(4,np.float32)
        worker.stamp=1.;worker.packet=packet();worker.size=(640,480)
        np.testing.assert_array_equal(worker.snapshot(.9)[0],0)
        self.assertIsNone(worker.geometry_snapshot(.9))
        self.assertIsNone(worker.geometry_snapshot(1.1,(480,640)))
        self.assertEqual(worker.geometry_snapshot(1.1,(640,480))['timestamp_ms'],1000.)

    def test_worker_does_not_refresh_capture_time_when_tracker_holds_old_face(self):
        from .face_geometry import GeometryContextWorker
        from unittest.mock import patch
        from types import SimpleNamespace
        class HeldFace:
            def __init__(self,*args):self.tracker=SimpleNamespace(last_seen=0.)
            def update(self,frame,now):return np.ones(4,np.float32),packet(0.)
            def close(self):pass
        with patch('ai_service.face_geometry.FaceGeometryTracker',HeldFace):
            worker=GeometryContextWorker(runtime,'unused')
            try:
                for now in [0.,1.]:
                    worker.update(np.zeros((32,32,3),np.uint8),now)
                    with worker.condition:
                        self.assertTrue(worker.condition.wait_for(lambda:getattr(worker,'processed_stamp',worker.stamp)==now,timeout=2.))
                np.testing.assert_array_equal(worker.snapshot(2.)[0],0)
                self.assertIsNone(worker.geometry_snapshot(2.))
            finally:worker.close()

    def test_two_hand_swapping_moves_new_features_with_the_hand(self):
        from .face_geometry import swap_geometry_slots
        features=np.arange(48*33,dtype=np.float32).reshape(48,33)
        swapped=swap_geometry_slots(features)
        np.testing.assert_array_equal(swapped[:,19:25],features[:,25:31])
        np.testing.assert_array_equal(swapped[:,25:31],features[:,19:25])
        np.testing.assert_array_equal(swapped[:,:19],features[:,:19])
        np.testing.assert_array_equal(swapped[:,31:],features[:,31:])

    def test_unobserved_interpolated_hand_does_not_create_anatomy_evidence(self):
        p,w=self.sample();p=np.tile(p,(12,1));w=np.tile(w,(12,1));t=np.arange(12)/15+1
        c=np.tile([.5,.2,.46,1],(12,1));observed=np.zeros((12,2),bool)
        _,m=geometry_sequence(runtime,p,w,c,t,[packet()]*12,observed=observed)
        np.testing.assert_array_equal(m[:,19:31],0)

    def test_head_adapter_keeps_reference_decisions_when_extra_channels_masked(self):
        from .face_geometry import bind_geometry_head,GeometryTimeline
        from pathlib import Path
        import copy
        p,w=self.sample();p=np.tile(p,(12,1));w=np.tile(w,(12,1));t=np.arange(12)/15+1
        c=np.tile([.5,.2,.46,1],(12,1))
        cfg=dict(version=runtime.WORD_TEMPORAL_VERSION,labels=['nghe','điếc'],dynamic_labels=[],requires_pair={})
        def infer(inputs):
            return np.tile([.9,.05,.05],(len(inputs[0]),1)).astype(np.float32)
        original=runtime.TemporalWordHead(['nghe','điếc'],cfg,infer)
        extended=copy.copy(original)
        fn=runtime.word_temporal_features
        bind_geometry_head(extended,runtime,Path(runtime.__file__).read_text(encoding='utf8'),GeometryTimeline([packet()]),False)
        a=original.predict([(p,w,c,t)]);b=extended.predict([(p,w,c,t)])
        np.testing.assert_array_equal(a[0],b[0]);np.testing.assert_array_equal(a[1],b[1])
        self.assertIs(runtime.word_temporal_features,fn)

if __name__=='__main__':unittest.main()

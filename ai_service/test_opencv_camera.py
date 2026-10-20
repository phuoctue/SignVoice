from types import SimpleNamespace
import unittest
import cv2
import numpy as np
from ai_service.opencv_camera import OpenCVCameraAnalysis
from ai_service.model_runtime import OpenCVHandMotion


def hand_points():
    # Synthetic palm outline with 21 measured points for geometry/texture tests.
    return [SimpleNamespace(x=(32+(i%7)*10)/160,y=(30+(i//7)*20)/120) for i in range(21)]


class OpenCVCameraTests(unittest.TestCase):
    def test_roi_hull_and_advice_do_not_change_pixels_or_invent_flow(self):
        image=np.full((120,160,3),20,np.uint8);before=image.copy()
        result=OpenCVCameraAnalysis().analyze(image,[hand_points()],None,0.)
        self.assertTrue(result['enabled'])
        self.assertEqual(len(result['regions']),1)
        self.assertGreaterEqual(len(result['regions'][0]['hull']),3)
        self.assertTrue(result['quality']['warnings'])
        self.assertTrue(result['quality']['advisory_only'])
        self.assertEqual(result['quality']['scope'],'hand_regions')
        self.assertEqual(result['flow_vectors'],[])
        self.assertFalse(result['recovery_guidance_enabled'])
        np.testing.assert_array_equal(image,before)
        for region in result['regions']:
            self.assertTrue(all(0<=v<=1 for v in region['box']))

    def test_lk_measures_translation_and_expires_after_gap(self):
        rng=np.random.default_rng(73)
        image=rng.integers(0,255,(120,160,3),dtype=np.uint8)
        motion=OpenCVHandMotion();motion.begin(image,0);motion.observe([hand_points()])
        moved=cv2.warpAffine(image,np.array([[1,0,3],[0,1,2]],np.float32),(160,120))
        motion.begin(moved,100)
        self.assertTrue(motion.arrows)
        shifts=np.array([b-a for a,b in motion.arrows])
        np.testing.assert_allclose(np.median(shifts,axis=0),[3,2],atol=.35)
        self.assertIsNotNone(motion.missing_bounds([]))
        report=OpenCVCameraAnalysis().analyze(cv2.cvtColor(moved,cv2.COLOR_RGB2BGR),[],motion,.1)
        self.assertEqual(report['regions'],[])
        self.assertGreater(len(report['flow_vectors']),0)
        motion.begin(moved,1000)
        self.assertEqual(motion.arrows,[])
        self.assertEqual(motion.tracks,[])

    def test_quality_is_throttled_without_rejecting_a_frame(self):
        camera=OpenCVCameraAnalysis()
        dark=np.zeros((120,160,3),np.uint8);bright=np.full_like(dark,255)
        first=camera.analyze(dark,[],None,0.)
        second=camera.analyze(bright,[],None,.1)
        self.assertEqual(first['quality'],second['quality'])
        third=camera.analyze(bright,[],None,.6)
        self.assertEqual(third['quality']['brightness'],255)
        self.assertTrue(third['quality']['advisory_only'])


if __name__=='__main__':unittest.main()

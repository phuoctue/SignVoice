import threading
import unittest
from types import SimpleNamespace
import numpy as np
from .model_runtime import SigningContextWorker, LiveSession


class WordClockTests(unittest.TestCase):
    def test_face_snapshot_expires_and_cannot_read_future_measurements(self):
        worker=SigningContextWorker.__new__(SigningContextWorker)
        worker.condition=threading.Condition();worker.error=None
        worker.anchor=np.array([.4,.3,.2,1.],np.float32);worker.stamp=2.
        anchor,stamp=worker.snapshot(2.5)
        np.testing.assert_array_equal(anchor,worker.anchor);self.assertEqual(stamp,2.)
        for now in (1.9,3.21):
            anchor,stamp=worker.snapshot(now)
            self.assertFalse(np.any(anchor));self.assertIsNone(stamp)

    def test_word_window_needs_real_samples_not_repeated_interpolation(self):
        from .model_runtime import GestureBuffer
        pose=np.ones(126,np.float32);wrist=np.ones(8,np.float32)
        sparse=GestureBuffer();dense=GestureBuffer()
        for t in np.arange(0,1.2,.6):sparse.add(pose,wrist,t)
        for t in np.arange(0,1.2,.1):dense.add(pose,wrist,t)
        self.assertEqual(sparse.windows(),[])
        self.assertTrue(dense.windows())
        self.assertGreaterEqual(len(dense.windows()[0][0]),6)

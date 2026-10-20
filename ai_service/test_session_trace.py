import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from .session_trace import SessionTrace


class SessionTraceTests(unittest.TestCase):
    def test_disabled_trace_does_not_retain_inputs(self):
        trace=SessionTrace(None,{})
        trace.add(np.zeros(126),np.zeros(8),np.zeros(4),{})
        self.assertEqual(len(trace.frames),0)
        self.assertIsNone(trace.save())

    def test_bounded_trace_preserves_exact_inputs_and_capture_times(self):
        with tempfile.TemporaryDirectory() as folder:
            trace=SessionTrace(folder,{'manifest_sha256':'verified','mode':'words'},limit=2)
            pose=np.arange(126,dtype=np.float32)
            for i in range(3):trace.add(pose+i,np.zeros(8),np.ones(4),dict(timestamp_ms=i*100,sequence=i,inference={}))
            path=trace.save()
            with np.load(path,allow_pickle=False) as data:
                np.testing.assert_array_equal(data['pose'][0],pose+1)
                np.testing.assert_array_equal(data['times'],[.1,.2])
                meta=json.loads(str(data['metadata']))
                self.assertEqual(meta['total_frames'],3)
                self.assertFalse(meta['use_for_training'])
                self.assertFalse(meta['contains_camera_pixels'])
            self.assertIsNone(trace.save())

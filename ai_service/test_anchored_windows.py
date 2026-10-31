from collections import deque
from pathlib import Path
from types import SimpleNamespace
import types
import unittest
import numpy as np
from . import model_runtime
from .experiment_anchored_windows import ActiveStartWindow, metadata_predictor
from .review_anchored_windows import exact_discordance_p


class AnchoredWindowTests(unittest.TestCase):
    def test_exact_p_does_not_make_one_lost_clip_significant(self):
        self.assertEqual(exact_discordance_p(0,1),1.)
        self.assertEqual(exact_discordance_p(0,0),1.)
        self.assertEqual(exact_discordance_p(3,0),.25)

    def adapter(self,enabled=True):
        frames=deque((i/10,np.full(126,i+1,np.float32),np.zeros(8,np.float32),np.zeros(4,np.float32)) for i in range(8))
        buffer=SimpleNamespace(frames=frames,repair_gaps=False,gap_seconds=.6,
            windows=lambda:[],clear=lambda:frames.clear())
        head=SimpleNamespace(_selected_interval_metadata=None,_selected_eligible_metadata=False)
        session=SimpleNamespace(buffer=buffer,recognizer=SimpleNamespace(word_head=head))
        def predict(self,candidates):return np.array([-.1,.2]),np.array([False,False])
        return ActiveStartWindow(session,SimpleNamespace(),predict,enabled)

    def test_extra_window_uses_newest_measurements_and_original_observation_mask(self):
        adapter=self.adapter();adapter.anchor=(.2,.7)
        windows=adapter.windows()
        self.assertEqual(len(windows),1)
        p,w,c,t,observed=windows[0]
        self.assertAlmostEqual(t[0],.2)
        self.assertAlmostEqual(t[-1],.7)
        np.testing.assert_array_equal(p[-1],adapter.session.buffer.frames[-1][1])
        self.assertTrue(observed.all())
        self.assertEqual(adapter.stats['added_windows'],1)

    def test_expiry_and_buffer_clear_cannot_keep_stale_window(self):
        adapter=self.adapter();adapter.anchor=(.2,0.)
        self.assertEqual(adapter.windows(),[])
        self.assertIsNone(adapter.anchor)
        adapter.anchor=(.2,.7);adapter.session.buffer.clear()
        self.assertIsNone(adapter.anchor)
        self.assertFalse(adapter.session.buffer.frames)

    def test_disabled_adapter_never_adds_or_creates_anchor(self):
        adapter=self.adapter(False);adapter.anchor=(.2,.7)
        self.assertEqual(adapter.windows(),[])
        self.assertEqual(adapter.stats['added_windows'],0)

    def test_no_anchor_without_current_eligible_prediction(self):
        adapter=self.adapter();adapter.predict([])
        self.assertIsNone(adapter.anchor)
        self.assertEqual(adapter.stats['anchors_created'],0)

    def test_metadata_method_null_for_empty_candidates_and_clears_prior_metadata(self):
        source=Path(model_runtime.__file__).read_text(encoding='utf-8')
        modified=metadata_predictor(source,model_runtime.TemporalWordHead.predict)
        head=SimpleNamespace(labels=['a','b'],_selected_interval_metadata=(0,1),_selected_eligible_metadata=True)
        before=model_runtime.TemporalWordHead.predict(head,[])
        after=types.MethodType(modified,head)([])
        np.testing.assert_array_equal(before[0],after[0]);np.testing.assert_array_equal(before[1],after[1])
        self.assertIsNone(head._selected_interval_metadata)
        self.assertFalse(head._selected_eligible_metadata)

    def test_metadata_builder_refuses_unknown_implementation(self):
        source=Path(model_runtime.__file__).read_text(encoding='utf-8')
        changed=source.replace('quality=words.max(axis=1)+.25*gap','quality=words.max(axis=1)+.26*gap')
        with self.assertRaises(ValueError):metadata_predictor(changed,model_runtime.TemporalWordHead.predict)


if __name__=='__main__':unittest.main()

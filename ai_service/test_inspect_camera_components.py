import unittest
import numpy as np
from .inspect_camera_components import FusionTap, describe, digest_features, swap_features


class ComponentInspectionTests(unittest.TestCase):
    def test_tap_returns_original_array_and_detaches_observations(self):
        output = np.ones((2, 3), np.float32)
        tap = FusionTap(lambda tcn, cosine: output)
        tcn, cosine = np.zeros((2, 3), np.float32), np.zeros((2, 2), np.float32)
        self.assertIs(tap(tcn, cosine), output)
        output[0, 0] = 9
        tcn[0, 0] = 8
        self.assertEqual(tap.calls[0][2][0, 0], 1)
        self.assertEqual(tap.calls[0][0][0, 0], 0)

    def test_slot_swap_preserves_non_slot_features_and_is_involutive(self):
        pair = (np.arange(48*126, dtype=np.float32).reshape(48, 126),
                np.arange(48*19, dtype=np.float32).reshape(48, 19))
        once = swap_features(pair)
        twice = swap_features(once)
        np.testing.assert_array_equal(pair[0], twice[0])
        np.testing.assert_array_equal(pair[1], twice[1])
        np.testing.assert_array_equal(pair[1][:, [14, 18]], once[1][:, [14, 18]])
        self.assertEqual(digest_features(pair), digest_features(twice))

    def test_ranking_keeps_original_score_scale(self):
        record = describe([.1, .8, .4], ['a', 'b', 'c'], ['a', 'c'])
        self.assertEqual(record['top3'][0]['label'], 'b')
        self.assertEqual(record['targets']['c'], {'rank': 2, 'score': .4})

"""Exact matching optimizations must keep scores, including absent/negative classes."""
import unittest
import numpy as np
from .model_runtime import class_max, dtw_distances, HybridRecognizer


class MatchingTests(unittest.TestCase):
    def test_moving_letter_endpoint_does_not_run_unusable_dtw(self):
        from unittest.mock import patch
        from . import model_runtime as r
        rng=np.random.default_rng(19)
        dimension=r.shape_descriptor(np.zeros((1,126),np.float32)).shape[1]
        arrays=dict(static=np.zeros((1,dimension),np.float32),static_y=np.array([0]),
            temporal=np.zeros((2,24,dimension+8),np.float32),temporal_y=np.array([0,1]),
            metric_mean=np.zeros(dimension,np.float32),metric_std=np.ones(dimension,np.float32),
            sequence_version=np.array(3),template_hand_presence=np.zeros(2),
            template_motion_evidence=np.ones((2,2),np.float32))
        rec=r.HybridRecognizer(['a','ă'],arrays,{'dynamic_labels':['ă'],'endpoint_stability':.001})
        rec.set_mode('letters')
        pose=rng.normal(size=(12,126)).astype(np.float32)
        wrist=np.zeros((12,8),np.float32)
        with patch.object(r,'dtw_distances',side_effect=AssertionError('moving endpoint cannot confirm')):
            scores,ready=rec.predict(pose,wrist,return_ready_mask=True)
        self.assertFalse(ready.any())

    def test_grouped_max_preserves_missing_negative_and_nan_scores(self):
        values=np.array([-.4,-2.,.8,np.nan,.2],np.float32)
        labels=np.array([0,1,0,3,3])
        expected=np.array([.8,-2.,-1.,np.nan,-1.],np.float32)
        np.testing.assert_equal(class_max(values,labels,5),expected)

    def test_reuses_template_bank_and_norms_without_changing_dtw(self):
        rng=np.random.default_rng(8)
        templates=rng.normal(size=(12,24,18)).astype(np.float32)
        rec=HybridRecognizer.__new__(HybridRecognizer)
        rec.arrays={'temporal':templates};rec._dtw_banks={}
        ids=np.array([1,4,7])
        bank,norms=rec._dtw_bank(ids)
        again=rec._dtw_bank(ids.copy())
        self.assertIs(bank,again[0]);self.assertIs(norms,again[1])
        for length in (12,24,30):
            query=rng.normal(size=(length,18)).astype(np.float32)
            expected=dtw_distances(query,templates[ids])
            np.testing.assert_array_equal(dtw_distances(query,bank,template_norms=norms),expected)
        self.assertIs(rec._dtw_bank(np.arange(12))[0],templates)

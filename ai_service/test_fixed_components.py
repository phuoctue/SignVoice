import unittest
import numpy as np
from .ensemble import ProbabilityEnsemble
from .evaluate_fixed_components import ComponentFusion, InferenceMemo, metrics, paired, VARIANTS


class FixedComponentTests(unittest.TestCase):
    def test_reference_is_identical_and_branches_preserve_background(self):
        original = ProbabilityEnsemble(dict(tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.06))
        tcn = np.array([[.1,.2,.7]], np.float32)
        cosine = np.array([[.8,.1]], np.float32)
        np.testing.assert_array_equal(ComponentFusion(original,'reference')(tcn,cosine), original(tcn,cosine))
        for name in VARIANTS:
            result = ComponentFusion(original,name)(tcn,cosine)
            np.testing.assert_allclose(result.sum(axis=1),1,atol=1e-6)
            np.testing.assert_allclose(result[:,-1], tcn[:,-1],atol=1e-6)

    def test_memo_key_includes_shapes_and_returns_detached_data(self):
        calls = []
        def f(a):
            calls.append(a.shape)
            return a*2
        memo = InferenceMemo(f)
        x = np.ones((2,3),np.float32)
        result = memo(x);result[0,0] = 0
        np.testing.assert_array_equal(memo(x),x*2)
        memo(x.reshape(3,2))
        self.assertEqual(len(calls),2)
        self.assertEqual(memo.hits,1)

    def row(self, index, truth, before, after):
        return dict(item=dict(label=truth,group=str(index),independently_verified_signer=False),
            results={v:dict(pred=before if v=='reference' else after,
                events=[] if (before if v=='reference' else after) is None else
                    [dict(label=before if v=='reference' else after,time=1.)]) for v in VARIANTS})

    def test_missing_is_separate_from_wrong_and_train_metrics_do_not_mix(self):
        rows=[self.row(1,'a','a','b'),self.row(2,'a',None,'a'),self.row(3,'b','a',None)]
        result=metrics(rows,'reference')
        self.assertEqual((result['correct'],result['wrong'],result['none']),(1,1,1))
        self.assertEqual(result['wrong_events'],1)
        self.assertEqual(result['accepted_precision'],.5)

    def test_paired_identical_and_uniform_improvement_controls(self):
        same=[self.row(i,'a' if i<4 else 'b','a' if i<4 else 'b','a' if i<4 else 'b') for i in range(6)]
        report=paired(same,'embedding75')
        self.assertEqual(report['macro_recall_delta_ci95'],[0.,0.])
        self.assertFalse(report['signer_holdout_verified'])
        better=[self.row(i,'a' if i<4 else 'b',None,'a' if i<4 else 'b') for i in range(6)]
        report=paired(better,'embedding75')
        self.assertEqual(report['macro_recall_delta_ci95'],[1.,1.])
        self.assertEqual((report['gained'],report['lost']),(6,0))

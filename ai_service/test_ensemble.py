import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from .ensemble import ProbabilityEnsemble, load_ensemble, embedded_ensemble
from .model_runtime import prepare_sign_sequence, TemporalWordHead, WORD_TEMPORAL_VERSION


class EnsembleTests(unittest.TestCase):
    def test_notebook_ensemble_is_bound_to_both_models(self):
        hashes={'embedding_model_v2.keras':'a','word_temporal.keras':'b'}
        cfg=dict(deployment_engine='probability_ensemble',ensemble=dict(model_hashes=hashes,
            tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.08),policy={'embed_weight':.5})
        self.assertIsNotNone(embedded_ensemble(cfg,hashes))
        with self.assertRaises(ValueError):embedded_ensemble(cfg,dict(hashes,**{'word_temporal.keras':'different'}))
        self.assertIsNone(embedded_ensemble({'deployment_engine':'tcn'},hashes))

    def fusion(self, weight=.5):
        return ProbabilityEnsemble(dict(tcn_weight=weight,tcn_temperature=1,embedding_temperature=.08))

    def test_is_a_distribution_and_preserves_background_evidence(self):
        tcn=np.array([[.2,.5,.3],[.05,.05,.9]],np.float32)
        result=self.fusion()(tcn,np.array([[.9,.2],[.99,.1]]))
        np.testing.assert_allclose(result.sum(axis=1),1,atol=1e-6)
        np.testing.assert_allclose(result[:,-1],tcn[:,-1],atol=1e-6)
        self.assertEqual(result[1].argmax(),2)

    def test_embedding_can_resolve_weak_tcn_without_erasing_background(self):
        tcn=np.array([[.1,.25,.3,.35]],np.float32)
        result=self.fusion()(tcn,np.array([[.1,.1,.99]]))
        self.assertEqual(result.argmax(axis=1).item(),2)
        self.assertAlmostEqual(float(result[0,-1]),.35,places=6)

    def test_both_models_are_required_and_bad_outputs_fail(self):
        for weight in [0,1,float('nan')]:
            with self.assertRaises(ValueError):self.fusion(weight)
        with self.assertRaises(ValueError):self.fusion()(np.array([[1.,0.]]),np.array([[float('nan')]]))

    def test_policy_cannot_be_applied_to_another_export_or_label_order(self):
        policy=dict(version='paired_probability_ensemble_v1',manifest_sha256='a',
            model_hashes={'embedding':'b','tcn':'c'},labels=['one','two'],
            tcn_weight=.5,tcn_temperature=1,embedding_temperature=.08)
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'policy.json';p.write_text(json.dumps(policy))
            self.assertIsNotNone(load_ensemble(p,'a',policy['model_hashes'],policy['labels']))
            self.assertIsNone(load_ensemble(p,'different',policy['model_hashes'],policy['labels']))
            self.assertIsNone(load_ensemble(p,'a',policy['model_hashes'],['two','one']))


class ObservationMaskTests(unittest.TestCase):
    def test_feature_dedup_keeps_windows_with_different_measured_evidence(self):
        p=np.zeros((12,2,21,3),np.float32);p[:,1]=.1
        w=np.zeros((12,2,4),np.float32);w[:,1]=[.4,.3,.1,.3]
        good=np.zeros((12,2),bool);good[:,1]=True
        poor=good.copy();poor[:6,1]=False
        head=TemporalWordHead(['one','two'],dict(version=WORD_TEMPORAL_VERSION,
            labels=['one','two'],dynamic_labels=[]),
            infer=lambda inputs:np.tile([.99,.005,.005],(len(inputs[0]),1)))
        args=(p.reshape(12,126),w.reshape(12,8),None,np.arange(12)/15)
        _,ready=head.predict([(*args,poor),(*args,good)])
        self.assertTrue(ready[0])
        self.assertEqual(head.last_diagnostics['measured_hand_frames'],12)

    def test_word_head_does_not_drop_a_measured_single_hand_in_slot_zero(self):
        p=np.zeros((12,2,21,3),np.float32);p[:,0]=.1
        w=np.zeros((12,2,4),np.float32);w[:,0]=[.4,.3,.1,.3]
        observed=np.zeros((12,2),bool);observed[:,0]=True;observed[5,0]=False
        head=TemporalWordHead(['one','two'],dict(version=WORD_TEMPORAL_VERSION,
            labels=['one','two'],dynamic_labels=[]),
            infer=lambda inputs:np.tile([.99,.005,.005],(len(inputs[0]),1)))
        _,ready=head.predict([(p.reshape(12,126),w.reshape(12,8),None,np.arange(12)/15,observed)])
        self.assertTrue(ready[0])
        self.assertEqual(head.last_diagnostics['measured_hand_frames'],11)

    def test_slot_canonicalization_moves_measured_mask_and_keeps_repaired_gaps_unmeasured(self):
        p=np.zeros((12,2,21,3),np.float32);p[:,0]=.1
        w=np.zeros((12,2,4),np.float32);w[:,0]=[.4,.3,.1,.3]
        observed=np.zeros((12,2),bool);observed[:,0]=True;observed[5,0]=False
        fixed,_,mask=prepare_sign_sequence(p.reshape(12,126),w.reshape(12,8),observed)
        self.assertTrue(np.any(fixed.reshape(12,2,21,3)[:,1]))
        self.assertFalse(mask[:,0].any())
        self.assertEqual(int(mask[:,1].sum()),11)
        self.assertFalse(mask[5].any())


if __name__=='__main__':unittest.main()

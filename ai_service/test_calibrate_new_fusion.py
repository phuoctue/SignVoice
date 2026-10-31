import copy
import unittest
import numpy as np
from .calibrate_new_fusion import SPECS,CAL,EPOCH,selection
from .ensemble import ProbabilityEnsemble


def fixture():
    rows=[]
    for i,word in enumerate(('alpha','bravo','charlie')):
        outcomes={name:dict(pred=word if i<2 else None,events=[dict(label=word,time=1.)] if i<2 else []) for name in ('app',*SPECS)}
        outcomes['tcn75']=dict(pred=word,events=[dict(label=word,time=1.)])
        rows.append(dict(item=dict(video_id=str(i),label=word,role=CAL,unverified_chao_khangcn=False),results=outcomes))
    return rows


class FusionCalibrationTests(unittest.TestCase):
    def test_registered_points_change_one_factor_and_keep_both_models(self):
        self.assertEqual(len(SPECS),6)
        for name,spec in SPECS.items():
            self.assertEqual(sum(spec[k]!=SPECS['anchor'][k] for k in spec),0 if name=='anchor' else 1)
            out=ProbabilityEnsemble(spec)(np.array([[.5,.3,.2]],np.float32),np.array([[.8,.6]],np.float32))
            self.assertTrue(np.isfinite(out).all());self.assertAlmostEqual(float(out.sum()),1.,places=5)
            self.assertGreater(out[0,-1],0)

    def test_selection_uses_only_calibration_and_excludes_unverified_labels(self):
        rows=fixture();before=copy.deepcopy(rows)
        self.assertEqual(selection(rows)['nominee'],'tcn75')
        extra=copy.deepcopy(rows[0]);extra['item']['role']=EPOCH;extra['results']={}
        unverified=copy.deepcopy(extra);unverified['item']['role']=CAL;unverified['item']['unverified_chao_khangcn']=True
        self.assertEqual(selection(rows+[extra,unverified]),selection(rows))
        self.assertEqual(rows,before)

    def test_added_wrong_events_cannot_be_selected(self):
        rows=fixture();rows[2]['results']['tcn75']['events'].insert(0,dict(label='wrong',time=.5))
        result=selection(rows)
        self.assertEqual(result['nominee'],'anchor')
        self.assertFalse(result['candidate_checks']['tcn75']['checks']['wrong_events_not_increased'])

    def test_same_accuracy_does_not_claim_improvement(self):
        rows=fixture()
        for r in rows:r['results']['tcn75']=copy.deepcopy(r['results']['anchor'])
        self.assertEqual(selection(rows)['reason'],'no_supported_development_improvement')

    def test_missing_branch_or_calibration_fails_closed(self):
        rows=fixture();rows[0]['results'].pop('tcn25')
        with self.assertRaises(ValueError):selection(rows)
        with self.assertRaises(ValueError):selection([])


if __name__=='__main__':unittest.main()

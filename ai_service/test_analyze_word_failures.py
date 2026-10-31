import unittest
from types import SimpleNamespace
import numpy as np
from .analyze_word_failures import classify, cut_snapshot, decision_snapshot, summarize


def step(top='a', reliable=False, elapsed=None, ready=False, blockers=None, emitted=None):
    return dict(time=1., head=dict(target_ready=ready, diagnostic=dict(inference_ran=True),
        windows=[dict(raw_top=top,eligible_after_primary_preference=ready)]),
        decision=dict(top=top,reliable=reliable,candidate_elapsed=elapsed,dwell=.3,
            confirmed='a' if elapsed is not None and elapsed>=.3 else None,locked=False,
            blockers=blockers or []),emitted=emitted or [])


class FailureDiagnosisTests(unittest.TestCase):
    def test_missing_hand_input_is_retained_and_not_called_a_model_prediction(self):
        engine=SimpleNamespace(runtime=SimpleNamespace(prepare_sign_sequence=lambda p,w:(p,w)))
        pose=np.zeros((10,126),np.float32);pose[:2,0]=1
        cut=cut_snapshot(engine,(pose,np.zeros((10,8)),np.arange(10),np.zeros((10,4))),'a')
        self.assertFalse(cut['available'])
        self.assertEqual(cut['usable_hand_frames'],2)
        self.assertIsNone(cut['target_score'])
        self.assertFalse(cut['diagnostic']['inference_ran'])

    def test_short_run_is_not_inferred_from_cut_success_or_peak_alone(self):
        cut=dict(top='a',target_ready=True)
        score_only=classify('a',cut,[step(blockers=['score'])],[])
        self.assertEqual(score_only['category'],'target_top_but_head_gates_not_met')
        short=classify('a',cut,[step(reliable=True,elapsed=.25,ready=True)],[])
        self.assertEqual(short['category'],'qualified_target_run_shorter_than_dwell')

    def test_emitted_then_overwritten_is_distinct_from_no_recognition(self):
        cut=dict(top='a',target_ready=True)
        result=classify('a',cut,[],[dict(label='a',time=1.),dict(label='b',time=2.)])
        self.assertEqual(result['category'],'target_emitted_then_other_label')
        self.assertEqual(result['wrong_events'],1)

    def test_clip_normalization_excludes_startup(self):
        cut=dict(top='a',target_ready=False)
        startup=step();startup['head']['diagnostic']['inference_ran']=False
        result=classify('a',cut,[startup,step(blockers=['score']),step(blockers=['margin'])],[])
        self.assertEqual(result['target_top_blocker_fraction'],{'score':.5,'margin':.5})
        self.assertEqual(result['inference_steps'],2)

    def test_mature_but_unconfirmed_is_explicit_invariant_failure(self):
        s=step(reliable=True,elapsed=.4,ready=True);s['decision']['confirmed']=None
        result=classify('a',dict(top='a',target_ready=True),[s],[])
        self.assertEqual(result['unexplained_mature_target_times'],[1.])

    def test_snapshot_refuses_reliable_inconsistent_with_observed_gates(self):
        d=SimpleNamespace(labels=['a','b'],smoothed=np.array([.5,.2]),candidate=None,since=0.)
        loc=dict(top=0,ready_for=lambda _:True,minimum=.6,margin=.2,needs_sequence=True,now=1.)
        with self.assertRaises(RuntimeError): decision_snapshot(d,loc,(None,[0,1],.3,True),'a')

    def test_missing_word_kept_separate_from_failed_clip(self):
        report=summarize([],['a','b'])
        self.assertEqual(report['words_without_calibration'],['a','b'])
        self.assertEqual(report['overall']['failed_clips'],0)
        self.assertIsNone(report['overall']['false_accept_per_minute'])


if __name__=='__main__': unittest.main()

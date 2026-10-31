import unittest
from .compare_colab_checkpoints import select_cohort,verify_original_metadata
from .evaluate_fixed_components import digest


class CheckpointComparisonTests(unittest.TestCase):
    def rows(self):
        return [dict(item=dict(video_id=k,role='calibration_development')) for k in ['cal','epoch','audit']]

    def identity(self):
        return dict(train_ids=['train'],calibration_ids=['cal'],epoch_val_ids=['epoch'],audit_ids=['audit'])

    def test_audit_is_excluded_before_any_data_access_and_roles_remain_separate(self):
        selected,excluded=select_cohort(self.rows(),self.identity())
        self.assertEqual([x['item']['video_id'] for x in selected],['cal','epoch'])
        self.assertEqual([x['item']['role'] for x in selected],['checkpoint_calibration_development','checkpoint_epoch_development'])
        self.assertEqual(excluded,[dict(video_id='audit',reason='reserved_new_checkpoint_audit')])

    def test_training_overlap_refuses_even_if_the_id_is_also_marked_validation(self):
        identity=self.identity();identity['train_ids'].append('cal')
        with self.assertRaises(ValueError):select_cohort(self.rows(),identity)

    def test_unassigned_role_is_not_assumed_calibration(self):
        rows=self.rows();rows.append(dict(item=dict(video_id='unknown',role='calibration_development')))
        with self.assertRaises(ValueError):select_cohort(rows,self.identity())

    def test_duplicate_split_ids_are_rejected(self):
        identity=self.identity();identity['calibration_ids'].append('cal')
        with self.assertRaises(ValueError):select_cohort(self.rows(),identity)

    def test_corrupt_original_metadata_is_rejected_without_loading_feature_files(self):
        contract=dict(cohort=[dict(video_id='a',role='calibration_development')])
        row=dict(item=contract['cohort'][0].copy(),contract_sha256=digest(contract),results=dict(null_control_passed=True))
        verify_original_metadata([row],contract)
        row['item']['role']='train'
        with self.assertRaises(ValueError):verify_original_metadata([row],contract)


if __name__=='__main__':unittest.main()

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('audit', Path(__file__).with_name('audit-sign-library.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def row(**changes):
    value = dict(kind='rgb', label='chào', fixed_split='train',
                 source_label_verified='True', is_personal='False',
                 basic_quality_pass='True', sha256='a'*64, path='sources/a.mp4')
    value.update(changes)
    return value


class InventoryTests(unittest.TestCase):
    def test_never_select_test_or_private_or_numeric_skeleton(self):
        for changes in [dict(fixed_split='test'), dict(fixed_split='val'),
                        dict(is_personal='True'), dict(kind='skeleton'),
                        dict(source_label_verified='False'), dict(label='123'),
                        dict(training_exclusion_reason='requires_review')]:
            self.assertFalse(audit.eligible(row(**changes)))

    def test_reject_cross_label_hash_conflicts(self):
        groups, counts = audit.build_inventory([row(), row(label='nghe')], {'sources/a.mp4'})
        self.assertEqual(dict(groups), {})
        self.assertEqual(counts['conflicting_hash_labels'], 2)

    def test_deduplicate_and_keep_unicode(self):
        groups, counts = audit.build_inventory([row(), row(label='CHA\u0300O')], {'sources/a.mp4'})
        self.assertEqual(len(groups['chào']), 1)
        self.assertEqual(counts['duplicate_hash'], 1)

    def test_reject_unsafe_and_missing_member(self):
        for name in ['../outside.mp4', '/a.mp4', 'C:/a.mp4', 'sources\\a.mp4']:
            self.assertFalse(audit.safe_member(name))
        groups, counts = audit.build_inventory([row()], set())
        self.assertFalse(groups)
        self.assertEqual(counts['missing_or_unsafe_member'], 1)


if __name__ == '__main__':
    unittest.main()

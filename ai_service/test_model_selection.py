import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from .model_selection import inspect_bundle


class ModelSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.words = dict(steps=48, labels=['first', 'second'], inputs=dict(hand_shape=126, motion_context=19))
        names = ['embedding_model_v2.keras', 'prototypes_v2.json', 'train_mean.npy', 'train_std.npy',
                 'recognizer_v5.npz', 'hand_landmarker.task', 'face_detector.tflite', 'word_temporal.keras']
        for name in names:
            (self.folder / name).write_bytes(name.encode())
        self.config = dict(schema='signvoice_hybrid_v5', word_labels=self.words['labels'],
                           feature_pipeline='stable_two_hand_v5')
        self.save()

    def save(self):
        (self.folder / 'word_temporal_config.json').write_text(json.dumps(self.words), encoding='utf8')
        self.config['sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in self.folder.iterdir() if p.name != 'recognizer_config.json'}
        (self.folder / 'recognizer_config.json').write_text(json.dumps(self.config), encoding='utf8')

    def test_identity_is_derived_from_complete_export(self):
        info = inspect_bundle(self.folder)
        self.assertEqual(info['word_classes'], 2)
        self.assertEqual(info['word_model_sha256'], self.config['sha256']['word_temporal.keras'])
        self.assertEqual(inspect_bundle(self.folder, info['manifest_sha256']), info)

    def test_mixed_exports_and_manifest_replacement_are_rejected(self):
        info = inspect_bundle(self.folder)
        (self.folder / 'word_temporal.keras').write_bytes(b'other export')
        with self.assertRaisesRegex(ValueError, 'differs'):
            inspect_bundle(self.folder)
        self.save()
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            inspect_bundle(self.folder, info['manifest_sha256'])

    def test_feature_change_needs_matching_adapter(self):
        self.words['inputs']['motion_context'] = 31
        self.save()
        with self.assertRaisesRegex(ValueError, 'Feature contract'):
            inspect_bundle(self.folder)

    def test_label_vocabulary_mismatch_is_rejected(self):
        self.words['labels'] = ['third', 'first']
        self.save()
        with self.assertRaisesRegex(ValueError, 'vocabularies'):
            inspect_bundle(self.folder)

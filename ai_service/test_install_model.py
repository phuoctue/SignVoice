import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from . import model_selection
from .install_model import download, install_archive
from . import test_model_selection as fixtures


class ModelInstallerTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.ModelSelectionTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / 'another-machine'
        self.archive = Path(self.temp.name) / 'runtime.zip'
        self.descriptor = dict(directory='runtime_test', word_classes=2,
                               feature_pipeline='stable_two_hand_v5')
        self.bundle()

    def bundle(self, extra=None):
        files = list(self.fixture.folder.iterdir())
        self.descriptor['files'] = {p.name: dict(bytes=p.stat().st_size,
            sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in files}
        self.descriptor['manifest_sha256'] = self.descriptor['files']['recognizer_config.json']['sha256']
        with zipfile.ZipFile(self.archive, 'w') as z:
            for path in files:
                z.write(path, path.name)
            if extra:
                z.writestr(extra, b'not a model')
        self.descriptor.update(bytes=self.archive.stat().st_size,
                               sha256=hashlib.sha256(self.archive.read_bytes()).hexdigest())

    def test_relocated_clone_loads_packaged_bundle_and_existing_pin_wins(self):
        info = install_archive(self.archive, self.descriptor, self.project)
        self.assertEqual(info['word_classes'], 2)
        descriptor = self.project / 'ai_service/model_bundle.json'
        descriptor.write_text(json.dumps(self.descriptor), encoding='utf8')
        selection = self.project / '.runtime/ai-model-selection.json'
        with patch.object(model_selection, 'PROJECT', self.project), patch.object(model_selection, 'SELECTION', selection):
            self.assertEqual(model_selection.resolve_selection(), info)
            selection.parent.mkdir()
            relative = dict(info, model_dir='ai_service/models/runtime_test')
            selection.write_text(json.dumps(relative), encoding='utf8')
            self.assertEqual(model_selection.resolve_selection(), info)
            relative['manifest_sha256'] = 'bad'
            selection.write_text(json.dumps(relative), encoding='utf8')
            with self.assertRaisesRegex(ValueError, 'manifest changed'):
                model_selection.resolve_selection()
        self.assertEqual(install_archive(self.archive, self.descriptor, self.project), info)

    def test_corrupt_download_rejected_before_install(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            install_archive(self.archive, self.descriptor, self.project)
        self.assertFalse(self.project.exists())

    def test_unexpected_zip_member_and_traversal_are_rejected(self):
        self.bundle('../outside')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            install_archive(self.archive, self.descriptor, self.project)
        self.assertFalse((self.project / 'ai_service/outside').exists())

    def test_modified_existing_model_is_never_overwritten(self):
        info = install_archive(self.archive, self.descriptor, self.project)
        path = Path(info['model_dir']) / 'word_temporal.keras'
        path.write_bytes(b'modified by owner')
        with self.assertRaisesRegex(ValueError, 'differs'):
            install_archive(self.archive, self.descriptor, self.project)
        self.assertEqual(path.read_bytes(), b'modified by owner')


class DownloadTests(unittest.TestCase):
    def test_resume_and_servers_ignoring_range_keep_the_correct_bytes(self):
        payload = b'complete pinned runtime archive'
        descriptor = dict(url='https://example.test/runtime.zip', bytes=len(payload),
                          sha256=hashlib.sha256(payload).hexdigest())
        for status in (200, 206):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                partial = Path(directory) / (descriptor['sha256'] + '.partial')
                partial.write_bytes(payload[:5])
                response = io.BytesIO(payload[5:] if status == 206 else payload)
                response.status = status
                response.headers = {'Content-Range': f'bytes 5-{len(payload)-1}/{len(payload)}'}
                response.geturl = lambda: descriptor['url']
                with patch('urllib.request.urlopen', return_value=response) as request:
                    result = download(descriptor, directory)
                self.assertEqual(request.call_args.args[0].get_header('Range'), 'bytes=5-')
                self.assertEqual(result.read_bytes(), payload)
                self.assertFalse(partial.exists())

    def test_server_returning_wrong_resume_offset_is_rejected(self):
        payload = b'complete pinned runtime archive'
        descriptor = dict(url='https://example.test/runtime.zip', bytes=len(payload),
                          sha256=hashlib.sha256(payload).hexdigest())
        with tempfile.TemporaryDirectory() as directory:
            partial = Path(directory) / (descriptor['sha256'] + '.partial')
            partial.write_bytes(payload[:5])
            response = io.BytesIO(payload)
            response.status = 206
            response.headers = {'Content-Range': 'bytes 0-30/31'}
            response.geturl = lambda: descriptor['url']
            with patch('urllib.request.urlopen', return_value=response):
                with self.assertRaisesRegex(ValueError, 'resume offset'):
                    download(descriptor, directory)
            self.assertEqual(partial.read_bytes(), payload[:5])

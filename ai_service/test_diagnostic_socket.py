"""Opt-in socket adds diagnostics without changing the ordinary result."""
from types import SimpleNamespace
from unittest.mock import patch
import unittest
from fastapi.testclient import TestClient
from .server import app


class DiagnosticSocketTests(unittest.TestCase):
    def test_only_opt_in_enables_worker_and_exports_journal(self):
        for enabled in (False, True):
            calls = []
            worker = SimpleNamespace(on_update=None,
                enable_diagnostics=lambda: calls.append('enabled'),
                drain_diagnostics=lambda: {'records': [{'index': 0}], 'truncated': False})
            session = SimpleNamespace(worker=worker, close=lambda: None,
                process=lambda meta, frame: dict(type='result', sequence=0, publication=1, confirmed='a'),
                recognition_update=lambda: None)
            engine = SimpleNamespace(info=lambda: {'ready': True}, session=lambda *a: session)
            with patch('ai_service.engine.Engine', return_value=engine), patch(
                    'ai_service.model_selection.resolve_selection', return_value={'model_dir': 'unused'}), patch(
                    'ai_service.diagnostic_replay.identity', return_value={'mode': 'words'}), patch(
                    'ai_service.server.read_header', return_value=({'timestamp_ms': 1000, 'sequence': 0}, None)), patch(
                    'ai_service.server.decode_frame', return_value=({}, None)):
                with TestClient(app) as client:
                    with client.websocket_connect('/v1/stream') as socket:
                        socket.send_json(dict(mode='words', diagnostic=enabled))
                        ready = socket.receive_json()
                        self.assertEqual(ready['worker_identity'], {'mode': 'words'} if enabled else None)
                        socket.send_bytes(b'frame')
                        result = socket.receive_json()
                        if result['type'] != 'result': result = socket.receive_json()
                        self.assertEqual(result['confirmed'], 'a')
                        self.assertEqual('worker_diagnostic' in result, enabled)
                        self.assertEqual(calls, ['enabled'] if enabled else [])

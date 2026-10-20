"""Explicit model selection; uploading another Colab export does not activate it."""
import argparse
import hashlib
import json
import os
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SELECTION = PROJECT / '.runtime' / 'ai-model-selection.json'


def inspect_bundle(folder, expected_manifest=None):
    folder = Path(folder).resolve()
    manifest = folder / 'recognizer_config.json'
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest()
    if expected_manifest and digest != expected_manifest:
        raise ValueError('Selected model manifest changed; select a complete verified export explicitly.')
    config = json.loads(manifest.read_text(encoding='utf-8'))
    if config.get('schema') != 'signvoice_hybrid_v5':
        raise ValueError('Camera adapter does not support this model schema.')
    required = {'embedding_model_v2.keras', 'prototypes_v2.json', 'train_mean.npy', 'train_std.npy',
                'recognizer_v5.npz', 'hand_landmarker.task', 'face_detector.tflite',
                'word_temporal.keras', 'word_temporal_config.json'}
    if set(config.get('sha256', {})) != required:
        raise ValueError('Incomplete model manifest; keep all files from one Colab export together.')
    for name, expected in config['sha256'].items():
        actual = hashlib.sha256((folder / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError('Model file differs from its export: ' + name)
    words = json.loads((folder / 'word_temporal_config.json').read_text(encoding='utf-8'))
    if words.get('steps') != 48 or words.get('inputs') != {'hand_shape': 126, 'motion_context': 19}:
        raise ValueError('Feature contract changed; this export needs a matching camera adapter.')
    if set(words['labels']) != set(config.get('word_labels', [])) or len(words['labels']) != len(set(words['labels'])):
        raise ValueError('Word vocabularies differ between model files.')
    return dict(model_dir=str(folder), manifest_sha256=digest, word_classes=len(words['labels']),
                word_model_sha256=config['sha256']['word_temporal.keras'],
                feature_pipeline=config['feature_pipeline'])


def resolve_selection(explicit=None):
    if explicit:
        return inspect_bundle(explicit)
    if SELECTION.is_file():
        selection = json.loads(SELECTION.read_text(encoding='utf-8'))
        folder = Path(selection['model_dir'])
        if not folder.is_absolute():
            folder = PROJECT / folder
        return inspect_bundle(folder, selection['manifest_sha256'])
    descriptor_path = PROJECT / 'ai_service' / 'model_bundle.json'
    if descriptor_path.is_file():
        descriptor = json.loads(descriptor_path.read_text(encoding='utf-8'))
        folder = PROJECT / 'ai_service' / 'models' / descriptor['directory']
        if not folder.is_dir():
            raise FileNotFoundError('Install the shared model first: scripts/setup-ai-service.ps1')
        return inspect_bundle(folder, descriptor['manifest_sha256'])
    return inspect_bundle(PROJECT.parent)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'pin', 'resolve'])
    parser.add_argument('--model-dir')
    parser.add_argument('--expected-words', type=int)
    args = parser.parse_args()
    if args.action != 'resolve' and not args.model_dir:
        parser.error('--model-dir is required')
    result = resolve_selection(args.model_dir)
    if args.expected_words is not None and result['word_classes'] != args.expected_words:
        raise ValueError('Export word count differs from the requested model.')
    if args.action == 'pin':
        SELECTION.parent.mkdir(parents=True, exist_ok=True)
        temporary = SELECTION.with_suffix('.tmp')
        temporary.write_text(json.dumps(result, indent=2), encoding='utf-8')
        os.replace(temporary, SELECTION)
    print(json.dumps(result))


if __name__ == '__main__':
    main()

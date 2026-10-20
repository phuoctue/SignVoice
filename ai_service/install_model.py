"""Download and verify the pinned public runtime bundle, without changing an existing selection."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.error
import urllib.request
import zipfile

from .model_selection import PROJECT, SELECTION, inspect_bundle

DESCRIPTOR = PROJECT / 'ai_service' / 'model_bundle.json'


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify_archive(path, descriptor):
    if Path(path).stat().st_size != descriptor['bytes'] or sha256(path) != descriptor['sha256']:
        raise ValueError('Runtime ZIP size/checksum differs from the pinned release.')


def download(descriptor, cache):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / (descriptor['sha256'] + '.zip')
    if destination.is_file():
        verify_archive(destination, descriptor)
        return destination
    partial = destination.with_suffix('.partial')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > descriptor['bytes']:
        raise ValueError('Partial download is larger than the expected ZIP; remove it and retry.')
    if offset < descriptor['bytes']:
        if not descriptor['url'].startswith('https://'):
            raise ValueError('Model downloads require HTTPS.')
        headers = {'User-Agent': 'SignVoice-model-installer'}
        if offset:
            headers['Range'] = f'bytes={offset}-'
        request = urllib.request.Request(descriptor['url'], headers=headers)
        print(f'Downloading runtime model ({descriptor["bytes"] / 1024**2:.1f} MiB); resume at {offset / 1024**2:.1f} MiB.', flush=True)
        with urllib.request.urlopen(request, timeout=60) as response:
            if not response.geturl().startswith('https://'):
                raise ValueError('Refusing insecure model download redirect.')
            if response.status == 206:
                content_range = response.headers.get('Content-Range', '')
                if not content_range.startswith(f'bytes {offset}-'):
                    raise ValueError('Server returned an unexpected resume offset.')
            else:
                offset = 0  # A server may ignore Range and return the full ZIP.
            with partial.open('ab' if offset else 'wb') as stream:
                total = offset
                last_report = total
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > descriptor['bytes']:
                        raise ValueError('Download exceeded expected model size.')
                    stream.write(block)
                    if total - last_report >= 8 * 1024**2:
                        print(f'  {total * 100 / descriptor["bytes"]:.0f}%', flush=True)
                        last_report = total
    verify_archive(partial, descriptor)
    os.replace(partial, destination)
    return destination


def install_archive(archive, descriptor, project=PROJECT):
    project = Path(project).resolve()
    directory = descriptor['directory']
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', directory):
        raise ValueError('Unsafe runtime directory name.')
    expected = descriptor['files']
    if any(Path(name).name != name or '/' in name or '\\' in name or name in ('.', '..') for name in expected):
        raise ValueError('Unsafe model member name.')
    verify_archive(archive, descriptor)
    models = project / 'ai_service' / 'models'
    models.mkdir(parents=True, exist_ok=True)
    target = models / directory

    def verify_folder(folder):
        for name, identity in expected.items():
            path = folder / name
            if path.is_symlink() or path.stat().st_size != identity['bytes'] or sha256(path) != identity['sha256']:
                raise ValueError('Installed runtime file differs: ' + name)
        result = inspect_bundle(folder, descriptor['manifest_sha256'])
        if (result['word_classes'] != descriptor['word_classes'] or
                result['feature_pipeline'] != descriptor['feature_pipeline']):
            raise ValueError('Installed model vocabulary/feature contract differs.')
        return result

    if target.exists():
        return verify_folder(target)  # Never overwrite an unrelated or modified model.
    stage = Path(tempfile.mkdtemp(prefix='.install-', dir=models))
    try:
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            if len(entries) != len(expected) or {entry.filename for entry in entries} != set(expected):
                raise ValueError('Runtime ZIP contains missing, duplicate or unexpected files.')
            for entry in entries:
                identity = expected[entry.filename]
                kind = (entry.external_attr >> 16) & 0o170000
                if entry.file_size != identity['bytes'] or kind == 0o120000 or entry.flag_bits & 1:
                    raise ValueError('Invalid runtime ZIP member: ' + entry.filename)
                with bundle.open(entry) as source, (stage / entry.filename).open('wb') as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
        verify_folder(stage)
        stage.rename(target)
    finally:
        if stage.exists():
            shutil.rmtree(stage)  # Only this freshly created staging directory.
    return verify_folder(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Use the release ZIP already downloaded on this machine.')
    parser.add_argument('--activate', action='store_true', help='Explicitly replace the current local model selection.')
    args = parser.parse_args()
    descriptor = json.loads(DESCRIPTOR.read_text(encoding='utf-8'))
    archive = args.archive or download(descriptor, PROJECT / 'ai_service' / '.cache')
    result = install_archive(archive, descriptor)
    if args.activate or not SELECTION.exists():
        selection = dict(result, model_dir=Path(result['model_dir']).relative_to(PROJECT).as_posix())
        SELECTION.parent.mkdir(parents=True, exist_ok=True)
        temporary = SELECTION.with_suffix('.tmp')
        temporary.write_text(json.dumps(selection, indent=2), encoding='utf-8')
        os.replace(temporary, SELECTION)
        print('Selected the verified shared model.')
    else:
        print('Installed model; preserved the existing local selection.')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

"""Check current delivered plugin sources; --write explicitly refreshes pins.

Historical DELIVERY_SHA256/UPSTREAM_HASHES files are never overwritten.
Runtime results and omitted upstream trees are not part of these source pins.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def inventory(root, folders, extras=(), excluded=()):
    paths = {p for folder in folders for p in (root / folder).rglob('*') if p.is_file()}
    paths.update(root / name for name in extras if (root / name).is_file())
    result = {}
    for path in sorted(paths):
        name = path.relative_to(root).as_posix()
        if '__pycache__' in path.parts or path.suffix == '.pyc' or name in excluded:
            continue
        if path.is_symlink():
            raise ValueError('symlink in delivered source: ' + name)
        result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def check_or_write(path, files, write):
    record = dict(schema=1, scope='current delivered sources, not historical validation results', files=files)
    if write:
        path.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    if not path.is_file():
        raise RuntimeError('manifest missing: ' + str(path))
    expected = json.loads(path.read_text(encoding='utf-8'))['files']
    changed = sorted(name for name in set(files) | set(expected) if files.get(name) != expected.get(name))
    if changed:
        raise RuntimeError('release inventory changed: ' + ', '.join(changed[:20]))
    print('CURRENT_PLUGIN_SOURCE_PASS', path.name, len(files))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    mimic = ROOT / 'mimic_plugin'
    files = inventory(mimic, ('afdx_mimic', 'executors', 'scripts', 'tests', 'cases', 'rtl', 'security_lab'),
                      ('README.md', 'VERSION.txt', 'requirements.txt', 'trusted_selftests.json', 'DELIVERY_SHA256.json'))
    check_or_write(mimic / 'RELEASE_MANIFEST.json', files, args.write)
    name = 'docs/mimic_plugin/CURRENT_DELIVERY_SHA256.json'
    docs = inventory(ROOT, ('docs/mimic_plugin',), excluded=(name,))
    docs.update({'mimic_plugin/' + key: value for key, value in files.items()})
    docs['mimic_plugin/RELEASE_MANIFEST.json'] = hashlib.sha256((mimic / 'RELEASE_MANIFEST.json').read_bytes()).hexdigest()
    check_or_write(ROOT / name, docs, args.write)
    name = 'docs/agent_plugin/CURRENT_DELIVERY_SHA256.json'
    files = inventory(ROOT, ('afdx_agent', 'afdx_ai', 'host', 'cases', 'models', 'reference_evidence',
                             'security_lab', 'scripts', 'tests', 'docs/agent_plugin'),
                      ('README.md', 'VERSION.txt'), excluded=(name,))
    check_or_write(ROOT / name, files, args.write)


if __name__ == '__main__':
    main()

"""Resolve standalone and merged release layouts without inventing evidence."""
import hashlib
import json
from pathlib import Path


def upstream_manifest(root):
    root = Path(root).resolve()
    candidates = (root / 'docs/UPSTREAM_HASHES.json',
                  root.parent / 'docs/mimic_plugin/UPSTREAM_HASHES.json')
    for path in candidates:
        if path.is_file():
            return path
    raise FileNotFoundError('UPSTREAM_HASHES.json unavailable in standalone or merged layout')


def verify_local(root):
    root = Path(root).resolve()
    manifest = json.loads((root / 'RELEASE_MANIFEST.json').read_text(encoding='utf-8'))
    bad = []
    for name, expected in manifest['files'].items():
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise ValueError('release path escapes plugin: ' + name)
        if (root / name).is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            bad.append(name)
    if bad:
        raise RuntimeError('local release mismatch: ' + ', '.join(bad))
    return dict(status='PASS', files_checked=len(manifest['files']))


def verify_upstream(root, source_root=None):
    manifest = upstream_manifest(root)
    pins = json.loads(manifest.read_text(encoding='utf-8'))
    if source_root is None:
        return dict(status='NOT_AVAILABLE', files_checked=0, manifest_entries=len(pins),
                    reason='historical upstream tree is not shipped; supply --upstream-root to verify it')
    source_root = Path(source_root).resolve()
    bad = []
    for name, expected in pins.items():
        path = (source_root / name).resolve()
        if not path.is_relative_to(source_root):
            raise ValueError('upstream path escapes source root: ' + name)
        if not path.is_file() or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            bad.append(name)
    if bad:
        raise RuntimeError('upstream missing or modified: ' + ', '.join(bad[:10]))
    return dict(status='PASS', files_checked=len(pins), manifest_entries=len(pins))

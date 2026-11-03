"""Non-destructive release packaging; no output path is ever deleted or replaced."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED = {'results', '.git', '.pytest_cache', 'node_modules', 'work'}
GENERATED_FILES = {'.wlf', '.vcd', '.qdb', '.qtl', '.qpg', '.obj', '.o', '.exe', '.dll'}

def source_files(root):
    root = Path(root).resolve()
    for p in sorted(root.rglob('*')):
        rel = p.relative_to(root)
        if not p.is_file() or any(x in GENERATED for x in rel.parts):
            continue
        if rel.parts[:2] in (('mimic_plugin', 'build'), ('aihw_plugin', 'reports')):
            continue
        if (p.suffix.lower() in GENERATED_FILES and not (rel.parts[0]=='evidence' and p.suffix.lower()=='.wlf')) or p.name == 'MANIFEST.sha256':
            continue
        if p.is_symlink():
            raise ValueError('release symlink: ' + str(rel))
        # Existing pyc files are allowed but never needed to execute the sources.
        yield p

def inventory(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in source_files(root)}

def write_manifest(root):
    root = Path(root).resolve()
    rows = inventory(root)
    (root / 'MANIFEST.sha256').write_text(
        ''.join(h + '  ' + name + '\n' for name, h in rows.items()), encoding='utf-8')
    return rows

def validate_output(root, output):
    root = Path(root).resolve()
    output = Path(output).resolve()
    if output == root or output.is_relative_to(root) or root.is_relative_to(output):
        raise ValueError('Output must be outside the source tree and cannot be its ancestor')
    if output.exists():
        raise FileExistsError('Existing output is never replaced: ' + str(output))
    return output

def zip_files(root, output, files, prefix=''):
    root = Path(root).resolve()
    output = validate_output(root, output)
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    # Exclusive creation is the final race-safe no-overwrite guard.
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for p in files:
            p = Path(p).resolve()
            if not p.is_relative_to(root) or p.is_symlink():
                raise ValueError('Input outside selected source: ' + str(p))
            rel = p.relative_to(root).as_posix()
            archive.write(p, prefix + rel)
            rows.append(rel)
    return rows

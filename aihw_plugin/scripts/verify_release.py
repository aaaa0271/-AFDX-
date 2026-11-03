#!/usr/bin/env python3
"""Verify frozen source/data/evidence; runtime reports are intentionally mutable."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from afdx_ai_hw.fixed import read_json,sha


def main():
    manifest=read_json(ROOT/'RELEASE_MANIFEST.json')
    bad=[]
    for relative,expected in manifest['files'].items():
        p=ROOT/relative
        if p.is_symlink() or not p.is_file() or sha(p)!=expected:bad.append(relative)
    if bad:raise RuntimeError('release integrity mismatch: '+','.join(bad))
    print('RELEASE_INTEGRITY_PASS',len(manifest['files']))


if __name__=='__main__':main()

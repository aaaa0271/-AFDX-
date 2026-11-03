"""Fail-closed document/evidence gate; never issues an ARINC certificate.

This validates traceability artifacts, not the truth of normative interpretation.
Source text and applicability review must be supplied and reviewed before closure.
Functional regression success alone is deliberately insufficient.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
STATES = {'OPEN', 'IMPLEMENTED', 'TESTED', 'VERIFIED', 'NOT_APPLICABLE'}
PINNED = {'ARINC664P7-1','ARINC664P2-3','ARINC664P3-2','ARINC664P4-2','ARINC615A-4','ARINC665-5'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local_path(root, name):
    if not isinstance(name, str) or not name:
        raise ValueError('missing artifact path')
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('artifact outside project')
    if not path.is_file():
        raise ValueError('artifact not found: ' + name)
    return path


def artifact(root, entry):
    if not isinstance(entry, dict):
        raise ValueError('missing hashed evidence record')
    path = local_path(root, entry.get('path'))
    expected = entry.get('sha256', '')
    if not re.fullmatch('[0-9a-f]{64}', expected) or digest(path) != expected:
        raise ValueError('artifact hash mismatch: ' + str(entry.get('path')))
    return path


def evaluate(root, baseline, requirements):
    root = Path(root)
    issues, invalid = [], []
    def check(condition, message):
        if not condition:
            issues.append(message)
    def review(record, label):
        try:
            if not isinstance(record, dict) or record.get('status') != 'APPROVED' or not record.get('reviewer'):
                raise ValueError('approval/reviewer missing')
            artifact(root, record.get('evidence'))
        except (ValueError, TypeError, OSError) as exc:
            issues.append(label + ': ' + str(exc))
    if not isinstance(baseline, dict) or not isinstance(requirements, list):
        return dict(status='INVALID', conformance_pass=False, formal_certificate_issued=False,
                    issues=['baseline must be an object; requirements must be a list'])
    standards = baseline.get('standards', [])
    if not isinstance(standards, list) or not standards or not all(isinstance(s, dict) and s.get('id') for s in standards):
        invalid.append('standards must be nonempty identified records')
        standards = []
    ids = [s['id'] for s in standards]
    if len(ids) != len(set(ids)):
        invalid.append('duplicate standard identifiers')
    if baseline.get('core_standard') != 'ARINC664P7-1' or 'ARINC664P7-1' not in ids:
        invalid.append('selected AFDX core missing or silently changed')
    if set(ids) != PINNED:
        invalid.append('selected formal standard set changed; revise the controlled gate and baseline together')
    known = set(ids) | set(baseline.get('supplementary_reference_ids', []))
    check(baseline.get('normative_inventory_complete') is True, 'normative clause inventory is incomplete')
    review(baseline.get('inventory_review'), 'normative inventory review')
    review(baseline.get('cross_revision_review'), 'cross-edition compatibility review')
    for standard in standards:
        try:
            if standard.get('full_text_available') is not True:
                raise ValueError('normative full text not available')
            artifact(root, dict(path=standard.get('full_text_path'), sha256=standard.get('full_text_sha256')))
        except (ValueError, TypeError, OSError) as exc:
            issues.append(standard['id'] + ': ' + str(exc))
    if not requirements:
        invalid.append('empty requirements inventory cannot pass')
    req_ids = []
    rtl = {p.relative_to(root).as_posix(): digest(p) for p in sorted((root/'rtl').rglob('*.v'))}
    check(bool(rtl), 'no current RTL inputs')
    for row in requirements:
        if not isinstance(row, dict) or not row.get('id'):
            invalid.append('unidentified requirement')
            continue
        name = row['id']; req_ids.append(name)
        sources = row.get('source_ids')
        if not isinstance(sources, list) or not sources or any(s not in known for s in sources):
            invalid.append(name + ': unknown/missing standard reference')
        state = row.get('status')
        if state not in STATES:
            invalid.append(name + ': unknown status')
        if state not in {'VERIFIED', 'NOT_APPLICABLE'}:
            issues.append(name + ': not closed (' + str(state) + ')')
            continue
        check(row.get('locator_verified') is True and bool(row.get('source_locator')),
              name + ': missing reviewed normative locator')
        review(row.get('applicability_review'), name + ' applicability review')
        if state == 'NOT_APPLICABLE':
            check(bool(row.get('not_applicable_reason')), name + ': missing exclusion rationale')
            continue
        evidence = row.get('test_evidence', [])
        check(bool(evidence), name + ': no passing evidence')
        for item in evidence:
            try:
                result = json.loads(artifact(root, item).read_text(encoding='utf-8-sig'))
                if result.get('requirement_id') != name or result.get('verdict') != 'PASS':
                    raise ValueError('evidence does not pass this requirement')
                if result.get('source_hashes') != rtl:
                    raise ValueError('evidence does not match the complete current RTL set')
                artifact(root, result.get('raw_log'))
            except (ValueError, TypeError, OSError) as exc:
                issues.append(name + ': ' + str(exc))
    if len(req_ids) != len(set(req_ids)):
        invalid.append('duplicate requirement identifiers')
    return dict(status='INVALID' if invalid else 'INCOMPLETE' if issues else 'DIGITAL_CONFORMANCE_RECORDS_COMPLETE',
                conformance_pass=not issues and not invalid, formal_certificate_issued=False,
                scope='reviewed applicable digital end-system requirements only',
                normative_inventory_complete=baseline.get('normative_inventory_complete') is True,
                requirement_families_or_clauses=len(requirements), closed=sum(isinstance(r,dict) and r.get('status') in {'VERIFIED','NOT_APPLICABLE'} for r in requirements),
                current_rtl_files=len(rtl), issues=invalid + issues)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    docs = ROOT/'docs'
    try:
        result = evaluate(ROOT, json.loads((docs/'baseline.json').read_text(encoding='utf-8-sig')),
                          json.loads((docs/'requirements.json').read_text(encoding='utf-8-sig')))
    except (ValueError, OSError, TypeError) as exc:
        result = dict(status='INVALID', conformance_pass=False, formal_certificate_issued=False, issues=[str(exc)])
    result['checked_at'] = datetime.now(timezone(timedelta(hours=8))).isoformat()
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print('CONFORMANCE_RECORD_GATE', result['status'])
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result['conformance_pass'] else 2 if result['status']=='INVALID' else 1


if __name__ == '__main__':
    raise SystemExit(main())
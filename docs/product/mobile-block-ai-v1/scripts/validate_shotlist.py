#!/usr/bin/env python3
"""Check declared screenshot checkpoints and embedded report images.

Python 3.10+, standard library only. Run validate_evidence.py separately first.
This script cannot certify the visual truth of screenshots or runtime behavior.
"""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote
from validate_evidence import qualifies, safe_file

STAGES = ('S1', 'S2', 'S3', 'S4')
SHOT_ID = re.compile(r'^S[1-4]-T\d{2}-F\d{2}$')
HEADING = re.compile(r'(?m)^###\s+(S[1-4]-T\d{2})\b[^\n]*$')
IMAGE = re.compile(r'!\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)')

def platform_matches(actual: str, required: str) -> bool:
    return required == 'any' or actual in required.split('_or_')

def report_sections(text: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    headings = list(HEADING.finditer(text))
    for i, heading in enumerate(headings):
        key = heading.group(1)
        if key in sections:
            raise ValueError(f'duplicate case section: {key}')
        sections[key] = text[heading.end():headings[i+1].start() if i+1 < len(headings) else len(text)]
    return sections

def validate_shots(manifest: dict[str, Any], shotplan: dict[str, Any],
                   root: Path, gate: str | None = None,
                   check_reports: bool = False) -> list[str]:
    errors: list[str] = []
    shots = shotplan.get('shots')
    cases = manifest.get('cases')
    if not isinstance(shots, list) or not isinstance(cases, list):
        return ['shots and cases must be arrays']
    expected: dict[str, dict[str, Any]] = {}
    for shot in shots:
        if not isinstance(shot, dict):
            errors.append('invalid shot definition'); continue
        sid = shot.get('id')
        if not isinstance(sid, str) or not SHOT_ID.fullmatch(sid):
            errors.append('invalid shot id'); continue
        if sid in expected:
            errors.append(f'duplicate shot definition: {sid}')
        if sid.rsplit('-F', 1)[0] != shot.get('case_id'):
            errors.append(f'{sid}: case identity mismatch')
        expected[sid] = shot
    planned_cases = set(shotplan.get('cases', []))
    if planned_cases != {s['case_id'] for s in expected.values()}:
        errors.append('shotplan case coverage differs from shot definitions')
    actual_cases = {c.get('id'): c for c in cases if isinstance(c, dict)}
    if len(actual_cases) != len(cases) or set(actual_cases) != planned_cases:
        errors.append('manifest case coverage differs from shotplan')
    envs = {e.get('id'): e for e in manifest.get('environments', []) if isinstance(e, dict)}
    required_stages = set(STAGES[:STAGES.index(gate)+1]) if gate else set()
    reports: dict[str, dict[str, str]] = {}
    for cid, case in actual_cases.items():
        if not isinstance(cid, str):
            errors.append('case id must be a string'); continue
        is_required = cid.split('-')[0] in required_stages
        if is_required and case.get('status') != 'passed':
            errors.append(f'{cid}: gated case is not passed')
        if case.get('status') != 'passed':
            continue
        wanted = {sid: x for sid,x in expected.items() if x['case_id'] == cid}
        covered: dict[str, dict[str, Any]] = {}
        artifacts = case.get('artifacts', [])
        if not isinstance(artifacts, list):
            errors.append(f'{cid}: artifacts must be an array'); continue
        for artifact in artifacts:
            if not isinstance(artifact, dict) or artifact.get('kind') != 'screenshot':
                continue
            ids = artifact.get('shot_ids', [])
            if not isinstance(ids, list) or any(not isinstance(x,str) for x in ids):
                errors.append(f'{cid}: shot_ids must be an array of strings'); continue
            if len(set(ids)) != len(ids):
                errors.append(f'{cid}: duplicate shot_ids within screenshot')
            for sid in ids:
                if sid not in wanted:
                    errors.append(f'{cid}: unknown or cross-case shot {sid}'); continue
                if sid in covered:
                    errors.append(f'{sid}: choose one canonical screenshot per checkpoint'); continue
                try:
                    path = safe_file(root, artifact.get('path'))
                except ValueError as exc:
                    errors.append(f'{sid}: {exc}'); continue
                if not str(artifact.get('path', '')).startswith('evidence/') or 'design' in path.parts:
                    errors.append(f'{sid}: only evidence original files count'); continue
                if artifact.get('role') != 'after' or artifact.get('modified') is not False:
                    errors.append(f'{sid}: requires unmodified after capture'); continue
                env = envs.get(artifact.get('environment_id'), {})
                spec = wanted[sid]
                minimum = spec['minimum_capture_class']
                actual_class = env.get('capture_class', '')
                valid_class = actual_class in {'app_desktop','app_simulator','app_physical'} if minimum == 'app_any' else qualifies(actual_class, minimum)
                if not valid_class or not platform_matches(env.get('platform',''), spec['platform']):
                    errors.append(f'{sid}: incompatible capture class/platform'); continue
                if actual_class == 'app_physical' and env.get('is_physical') is not True:
                    errors.append(f'{sid}: physical-device declaration missing'); continue
                mismatch = False
                for field in ('theme','orientation','keyboard'):
                    required = spec.get(field)
                    if required and artifact.get(field) != required:
                        errors.append(f'{sid}: requires {field}={required}'); mismatch = True
                if mismatch:
                    continue
                if len(ids) > 1 and not artifact.get('reuse_reason'):
                    errors.append(f'{sid}: multiple checkpoints on one image need reuse_reason'); continue
                covered[sid] = artifact
        missing = sorted(set(wanted)-set(covered))
        if missing:
            errors.append(f'{cid}: missing checkpoints: {", ".join(missing)}')
        if check_reports:
            stage = cid.split('-')[0]
            if stage not in reports:
                try:
                    report = safe_file(root, f'results/{stage}.md')
                    reports[stage] = report_sections(report.read_text(encoding='utf-8'))
                except (ValueError, OSError) as exc:
                    errors.append(f'{stage}: {exc}'); reports[stage] = {}
            section = reports[stage].get(cid)
            if section is None:
                errors.append(f'{cid}: missing level-3 case heading in results/{stage}.md')
            else:
                embedded: set[Path] = set()
                for raw in IMAGE.findall(section):
                    if re.match(r'^[a-zA-Z]+:',raw):
                        continue
                    embedded.add((root/'results'/unquote(raw.split('#')[0])).resolve())
                for sid, artifact in covered.items():
                    target = (root/artifact['path']).resolve()
                    if target not in embedded:
                        errors.append(f'{sid}: original screenshot is not embedded in its report section')
    return errors

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    p.add_argument('--root', type=Path)
    p.add_argument('--shotlist', type=Path)
    p.add_argument('--gate', choices=STAGES)
    p.add_argument('--check-reports', action='store_true', help='Require embedded images; implicit with --gate')
    args = p.parse_args()
    root = (args.root or Path(__file__).resolve().parents[1]).resolve()
    try:
        manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
        shotplan = json.loads((args.shotlist or root/'shotlist.json').read_text(encoding='utf-8'))
        errors = validate_shots(manifest,shotplan,root,args.gate,bool(args.gate) or args.check_reports)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f'INVALID INPUT: {exc}',file=sys.stderr); return 2
    for error in errors:
        print('ERROR:', error,file=sys.stderr)
    print('NOTICE: Declaration/embedding checks only; not visual or behavioral certification.')
    if errors:
        print(f'REJECTED: {len(errors)} issue(s).',file=sys.stderr); return 1
    print('SHOT COVERAGE/EMBEDDING CHECK PASSED.' if args.gate or args.check_reports else 'SHOTLIST STRUCTURE CHECK PASSED; unrun cases are not certified.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

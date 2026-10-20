#!/usr/bin/env python3
"""Validate the desktop PRD evidence contract (metadata, not product truth).

No network requests, subprocess execution, or mutations are performed.
Run from any directory; --root overrides the PRD directory for isolated tests.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import struct
import sys
from typing import Any

CASE_STATUS = {'not_run', 'blocked', 'failed', 'passed'}
STAGE_STATUS = {'planned', 'in_progress', 'implemented_unverified', 'blocked', 'failed', 'verified'}
KINDS = {'screenshot', 'video', 'log', 'metrics', 'trace', 'semantic_tree'}
COMMIT = re.compile(r'^[0-9a-f]{40}$')
SHA256 = re.compile(r'^[0-9a-f]{64}$')


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def safe_path(root: Path, value: Any, evidence: bool = False) -> Path:
    if not isinstance(value, str) or not value or '\\' in value or '\x00' in value:
        raise ValueError('path must be a nonempty POSIX relative path')
    p = PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or ':' in p.parts[0]:
        raise ValueError('absolute paths, schemes and parent traversal are forbidden')
    if evidence and (not p.parts or p.parts[0] != 'evidence'):
        raise ValueError('formal evidence must be under evidence/')
    target = (root / value).resolve()
    if evidence and not target.is_relative_to((root / 'evidence').resolve()):
        raise ValueError('formal evidence symlink leaves evidence/')
    if not target.is_relative_to(root.resolve()):
        raise ValueError('path/symlink escapes the PRD root')
    return target


def png_size(path: Path) -> list[int]:
    with path.open('rb') as stream:
        head = stream.read(24)
    if len(head) != 24 or head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        raise ValueError('not a PNG with an IHDR header')
    width, height = struct.unpack('>II', head[16:24])
    if width < 1 or height < 1:
        raise ValueError('invalid PNG dimensions')
    return [width, height]


def timestamp(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return dt.tzinfo is not None and dt.utcoffset() is not None
    except ValueError:
        return False


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _index(rows: Any, label: str, errors: list[str]) -> dict[str, dict]:
    if not isinstance(rows, list):
        errors.append(f'{label}: expected list')
        return {}
    out: dict[str, dict] = {}
    for row in rows:
        if not isinstance(row, dict) or not nonempty(row.get('id')):
            errors.append(f'{label}: each item needs a string id')
            continue
        key = row['id']
        if key in out:
            errors.append(f'{label}: duplicate id {key}')
        out[key] = row
    return out


def validate(root: Path, manifest: dict, gate: str | None = None) -> list[str]:
    """Return all discoverable contract violations; never mark tests passed."""
    errors: list[str] = []
    root = root.resolve()
    if not isinstance(manifest, dict):
        return ['manifest must be a JSON object']
    try:
        plan = json.loads((root / 'plan.json').read_text(encoding='utf-8'))
        shots = _index(json.loads((root / 'shotlist.json').read_text(encoding='utf-8'))['shots'], 'shotlist', errors)
    except (OSError, ValueError, KeyError) as exc:
        return [f'cannot load plan/shotlist: {exc}']
    stage_plan = {s['id']: s for s in plan['stages']}
    case_plan = {c['id']: c for s in stage_plan.values() for c in s['cases']}
    if gate is not None and gate not in {*stage_plan, 'final'}:
        return ['unknown gate']
    if manifest.get('schema_version') != '1.0' or manifest.get('product') != plan['product']:
        errors.append('schema_version/product mismatch')
    cases = _index(manifest.get('cases'), 'cases', errors)
    stages = _index(manifest.get('stages'), 'stages', errors)
    envs = _index(manifest.get('environments'), 'environments', errors)
    artifacts = _index(manifest.get('artifacts'), 'artifacts', errors)
    if set(cases) != set(case_plan):
        errors.append('case coverage differs from plan (missing or unknown case ids)')
    if set(stages) != set(stage_plan):
        errors.append('stage coverage differs from plan')
    selected = set(case_plan) if gate == 'final' else {c for c in case_plan if c.startswith(gate + '-')} if gate else set()
    phase_commits: dict[str, str] = {}
    for sid, stage in stages.items():
        if stage.get('status') not in STAGE_STATUS:
            errors.append(f'{sid}: invalid stage status')
        if (gate == 'final' or gate == sid) and stage.get('status') != 'verified':
            errors.append(f'{sid}: required stage is not verified')
        if stage.get('implementation_commit'):
            phase_commits[sid] = stage['implementation_commit']
            if not COMMIT.fullmatch(str(stage['implementation_commit'])):
                errors.append(f'{sid}: invalid implementation commit')
        if stage.get('status') == 'verified':
            if sid not in phase_commits:
                errors.append(f'{sid}: verified stage requires implementation_commit')
            if any(cases.get(cid, {}).get('status') != 'passed' for cid in case_plan if cid.startswith(sid+'-')):
                errors.append(f'{sid}: verified stage contains unpassed cases')
    final_commit = manifest.get('implementation_commit')
    if gate == 'final' and not COMMIT.fullmatch(str(final_commit or '')):
        errors.append('final gate requires a full implementation_commit')
    # Referenced environments must identify the native build and capture context.
    for eid, env in envs.items():
        for key in ('platform', 'os_version', 'device', 'architecture', 'flutter_version', 'dart_version',
                    'build_mode', 'bundle_id', 'capture_method', 'capture_class'):
            if not nonempty(env.get(key)):
                errors.append(f'{eid}: missing environment {key}')
        if env.get('build_mode') not in {'debug', 'profile', 'release'}:
            errors.append(f'{eid}: invalid build_mode')
        if not isinstance(env.get('is_native_app'), bool) or not isinstance(env.get('is_vm'), bool):
            errors.append(f'{eid}: is_native_app/is_vm must be booleans')
        if not COMMIT.fullmatch(str(env.get('build_commit', ''))):
            errors.append(f'{eid}: invalid build_commit')
        if not SHA256.fullmatch(str(env.get('binary_sha256', ''))):
            errors.append(f'{eid}: invalid binary_sha256')
    by_path: dict[str, dict] = {}
    artifact_paths: dict[str, Path] = {}
    for aid, art in artifacts.items():
        kind = art.get('kind')
        if kind not in KINDS:
            errors.append(f'{aid}: invalid artifact kind')
        pathval = art.get('path')
        try:
            path = safe_path(root, pathval, evidence=True)
            artifact_paths[aid] = path
            if not path.is_file():
                raise ValueError('file does not exist')
            if path.stat().st_size == 0:
                raise ValueError('file is empty')
            if not SHA256.fullmatch(str(art.get('sha256', ''))) or sha256_file(path) != art['sha256']:
                errors.append(f'{aid}: sha256 mismatch')
            if pathval in by_path:
                errors.append(f'{aid}: artifact path has multiple records; reuse one artifact id')
            by_path[pathval] = art
        except (OSError, ValueError) as exc:
            errors.append(f'{aid}: {exc}')
            continue
        if not timestamp(art.get('captured_at')):
            errors.append(f'{aid}: captured_at must include timezone')
        if not COMMIT.fullmatch(str(art.get('implementation_commit', ''))):
            errors.append(f'{aid}: invalid commit')
        env = envs.get(art.get('environment_id'))
        if env is None:
            errors.append(f'{aid}: missing environment')
        elif env.get('build_commit') != art.get('implementation_commit'):
            errors.append(f'{aid}: environment/build commit mismatch')
        if kind == 'screenshot':
            if art.get('role') not in {'before', 'after', 'supporting'}:
                errors.append(f'{aid}: missing screenshot role')
            for key in ('description', 'theme', 'locale', 'window_state', 'active_pane', 'capture_scope'):
                if not nonempty(art.get(key)):
                    errors.append(f'{aid}: missing screenshot {key}')
            if art.get('theme') not in {'light', 'dark', 'high_contrast_light', 'high_contrast_dark'}:
                errors.append(f'{aid}: unknown theme')
            try:
                if png_size(path) != art.get('pixel_size'):
                    errors.append(f'{aid}: PNG pixel dimensions mismatch')
            except (OSError, ValueError) as exc:
                errors.append(f'{aid}: {exc}')
            view = art.get('viewport_logical')
            if not isinstance(view, list) or len(view) != 2 or not all(isinstance(n, (int, float)) and not isinstance(n,bool) and math.isfinite(n) and n > 0 for n in view):
                errors.append(f'{aid}: invalid logical viewport')
            for key in ('pixel_ratio', 'font_scale'):
                if not isinstance(art.get(key), (int,float)) or isinstance(art.get(key),bool) or not math.isfinite(art[key]) or art[key] <= 0:
                    errors.append(f'{aid}: invalid {key}')
            shot_ids = art.get('shot_ids')
            if not isinstance(shot_ids, list) or any(not isinstance(x,str) for x in shot_ids):
                errors.append(f'{aid}: shot_ids must be an array of strings')
                shot_ids = []
            if len(shot_ids) != len(set(shot_ids)):
                errors.append(f'{aid}: duplicate shot_ids')
            if len(shot_ids) > 1 and not nonempty(art.get('reuse_reason')):
                errors.append(f'{aid}: multiple shot_ids require reuse_reason')
            for shot_id in shot_ids:
                shot = shots.get(shot_id)
                if shot is None:
                    errors.append(f'{aid}: unknown shot id {shot_id}')
                else:
                    if shot.get('theme') and art.get('theme') != shot['theme']:
                        errors.append(f'{aid}: shot theme mismatch')
                    if shot.get('required_view') == 'full_app_window' and art.get('capture_scope') != 'full_app_window':
                        errors.append(f'{aid}: this shot needs the full App window')
            if art.get('capture_scope') != 'full_app_window' and not art.get('anchor_artifact_id'):
                errors.append(f'{aid}: detail needs a full-window anchor')
    # Each passed case must have files and human-readable, source-grounded results.
    for cid, case in cases.items():
        if cid not in case_plan:
            continue
        spec = case_plan[cid]
        if case.get('status') not in CASE_STATUS:
            errors.append(f'{cid}: invalid case status')
        if case.get('requirement_ids') != spec['requirement_ids']:
            errors.append(f'{cid}: requirement mapping mismatch')
        if cid in selected and case.get('status') != 'passed':
            errors.append(f'{cid}: required case not passed')
        if case.get('status') != 'passed':
            if case.get('status') in {'blocked','failed'} and not nonempty(case.get('reason')):
                errors.append(f'{cid}: blocked/failed needs reason')
            continue
        commit = case.get('implementation_commit')
        if not COMMIT.fullmatch(str(commit or '')):
            errors.append(f'{cid}: passed case needs commit')
        expected_commit = final_commit if gate == 'final' else phase_commits.get(cid[:2])
        if (cid in selected or expected_commit) and commit != expected_commit:
            errors.append(f'{cid}: passed case differs from required implementation commit')
        for key in ('actual_steps', 'observed_result'):
            if not nonempty(case.get(key)):
                errors.append(f'{cid}: missing {key}')
        if not isinstance(case.get('implementation_paths'),list) or not case['implementation_paths']:
            errors.append(f'{cid}: implementation_paths required')
        for imp in case.get('implementation_paths',[]):
            if not isinstance(imp,str) or imp.startswith(('/', 'http:', 'https:')) or '..' in PurePosixPath(imp).parts:
                errors.append(f'{cid}: implementation path must be repository-relative')
        ids = case.get('artifact_ids',[])
        if not isinstance(ids,list) or any(not isinstance(x,str) for x in ids):
            errors.append(f'{cid}: artifact_ids must be strings'); ids=[]
        if len(ids) != len(set(ids)):
            errors.append(f'{cid}: duplicate artifact_ids')
        assigned = []
        for aid in ids:
            art = artifacts.get(aid)
            if art is None:
                errors.append(f'{cid}: unknown artifact {aid}')
            else:
                assigned.append(art)
                if art.get('role') != 'before' and art.get('implementation_commit') != commit:
                    errors.append(f'{cid}: evidence commit differs from case')
        formal = [a for a in assigned if a.get('kind')=='screenshot' and a.get('role')=='after']
        covered: set[str] = set()
        for art in formal:
            aid = art['id']; env=envs.get(art.get('environment_id'),{})
            if art.get('modified') is not False:
                errors.append(f'{cid}/{aid}: formal after image must be unmodified')
            if env.get('platform') != spec['platform'] or env.get('capture_class') != spec['minimum_capture_class'] or env.get('is_native_app') is not True:
                errors.append(f'{cid}/{aid}: requires native macOS App evidence, not designs/widget images')
            for sh in art.get('shot_ids',[]):
                if shots.get(sh,{}).get('case_id') != cid:
                    errors.append(f'{cid}/{aid}: shot belongs to a different case')
                if sh in covered:
                    errors.append(f'{cid}: duplicate canonical shot coverage {sh}')
                covered.add(sh)
            if art.get('capture_scope') != 'full_app_window':
                anchor=artifacts.get(art.get('anchor_artifact_id'),{})
                if anchor.get('id') not in ids or anchor.get('capture_scope')!='full_app_window' or anchor.get('environment_id')!=art.get('environment_id'):
                    errors.append(f'{cid}/{aid}: invalid full-window anchor')
        expected_shots={key for key,shot in shots.items() if shot['case_id']==cid}
        if covered != expected_shots:
            errors.append(f'{cid}: incomplete screenshot checkpoints')
        logs=[a for a in assigned if a.get('kind') in {'log','metrics','trace','semantic_tree'}]
        if not logs:
            errors.append(f'{cid}: behavioral log/metric proof required')
        if spec.get('video_required') and not any(a.get('kind')=='video' and a.get('continuous') is True and a.get('modified') is False for a in assigned):
            errors.append(f'{cid}: continuous unmodified video required')
        assertions=case.get('assertions')
        if not isinstance(assertions,list) or not assertions:
            errors.append(f'{cid}: assertions required'); assertions=[]
        for assertion in assertions:
            if not isinstance(assertion,dict) or assertion.get('passed') is not True or not all(nonempty(assertion.get(k)) for k in ('name','expected','actual')):
                errors.append(f'{cid}: invalid/unpassed assertion'); continue
            if assertion.get('proof_artifact_id') not in {a['id'] for a in logs}:
                errors.append(f'{cid}: assertion proof must refer to its log/metric artifact')
        try:
            report=safe_path(root,case.get('result_path'))
            text=report.read_text(encoding='utf-8')
            text=re.sub(r'^```[^\n]*\n.*?^```\s*$', '', text, flags=re.S|re.M)
            text=re.sub(r'^~~~[^\n]*\n.*?^~~~\s*$', '', text, flags=re.S|re.M)
            match=re.search(r'^###\s+'+re.escape(cid)+r'\b[^\n]*\n(.*?)(?=^###\s+|\Z)',text,re.S|re.M)
            if not match:
                raise ValueError('report lacks case-specific level-3 heading')
            embedded=set()
            for target in re.findall(r'!\[[^\]]*\]\(([^)]+)\)',match.group(1)):
                # Raw Markdown links only; file references remain inside the PRD root.
                path=(report.parent/target).resolve()
                if path.is_relative_to(root): embedded.add(path)
            for art in formal:
                if artifact_paths.get(art['id']) not in embedded:
                    errors.append(f'{cid}: original screenshot not embedded in its report section')
        except (OSError,ValueError) as exc:
            errors.append(f'{cid}: {exc}')
    return errors


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--gate',choices=['D1','D2','D3','D4','final'])
    args=parser.parse_args()
    try:
        obj=json.loads(args.manifest.read_text(encoding='utf-8'))
        errors=validate(args.root,obj,args.gate)
    except (OSError,ValueError,TypeError,KeyError) as exc:
        print(f'INVALID: {exc}',file=sys.stderr); return 2
    if errors:
        for err in errors: print('FAIL:',err)
        print(f'{len(errors)} contract violations. Product completion is NOT certified.')
        return 1
    print('PASS: metadata/file contract only; native authenticity, visuals and behavior require human review.')
    if not args.gate: print('No stage gate requested. not_run cases remain NOT VERIFIED.')
    return 0

if __name__=='__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate PRD evidence coverage and file integrity; never certifies UI truth.

Python 3.10+, standard library only. Paths in manifests are relative to the PRD
root (directory containing plan.json), not the current working directory.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

STAGES = ('S1', 'S2', 'S3', 'S4')
CASE_STATUS = {'not_run', 'blocked', 'failed', 'passed'}
STAGE_STATUS = {'planned', 'in_progress', 'implemented_unverified', 'blocked', 'failed', 'verified'}
CAPTURE = {'widget_golden', 'app_simulator', 'app_physical', 'app_desktop'}
KINDS = {'screenshot', 'video', 'log', 'trace', 'metrics', 'semantic_tree'}
SHA40 = re.compile(r'^[0-9a-f]{40}$')
SHA64 = re.compile(r'^[0-9a-f]{64}$')

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def utc_time(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).tzinfo is not None
    except ValueError:
        return False

def safe_file(root: Path, relative: Any) -> Path:
    if not isinstance(relative, str) or not relative or '\\' in relative:
        raise ValueError('path must be a nonempty POSIX relative path')
    rel = Path(relative)
    if rel.is_absolute() or '..' in rel.parts or relative.startswith(('http:', 'https:', 'sandbox:')):
        raise ValueError('external or parent paths are not allowed')
    result = (root / rel).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError('path or symlink escapes PRD root')
    if not result.is_file():
        raise ValueError(f'missing file: {relative}')
    return result

def qualifies(actual: str, minimum: str) -> bool:
    if minimum == 'widget_golden':
        return actual in CAPTURE
    if minimum == 'app_simulator':
        return actual in {'app_simulator', 'app_physical'}
    return actual == minimum

def expected_platform(case_id: str) -> str | None:
    if case_id.startswith('S1-'):
        return 'ios'
    if case_id.startswith('S2-'):
        return 'macos' if case_id == 'S2-T12' else 'ipados' if case_id == 'S2-T11' else 'ios'
    if case_id == 'S3-T07' or case_id == 'S3-T08':
        return 'ios'
    if case_id == 'S3-T10':
        return 'macos'
    if case_id.startswith('S4-'):
        return 'ipados' if case_id == 'S4-T11' else 'macos' if case_id in {'S4-T12', 'S4-T14'} else 'ios'
    return None

def validate(manifest: dict[str, Any], plan: dict[str, Any], root: Path,
             gate: str | None = None, repo_root: Path | None = None) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    def err(message: str) -> None:
        errors.append(message)
    if manifest.get('schema_version') != '1.0':
        err('schema_version must be 1.0')
    planned = {c['id']: c for stage in plan.get('stages', []) for c in stage.get('cases', [])}
    rows = manifest.get('cases', [])
    if not isinstance(rows, list):
        return ['cases must be an array'], warnings
    actual = {r.get('id'): r for r in rows if isinstance(r, dict)}
    if len(actual) != len(rows):
        err('duplicate case IDs or invalid case objects')
    if set(actual) != set(planned):
        err(f'case coverage differs: missing={sorted(set(planned)-set(actual))}, extra={sorted(set(actual)-set(planned), key=str)}')
    impl = manifest.get('implementation_commit')
    any_passed = any(r.get('status') == 'passed' for r in actual.values())
    if (gate or any_passed) and not SHA40.fullmatch(str(impl)):
        err('passed evidence requires a full implementation_commit')
    if not SHA40.fullmatch(str(manifest.get('baseline_commit'))):
        err('baseline_commit must be a full commit SHA')
    env_list = manifest.get('environments', [])
    if not isinstance(env_list, list):
        return errors + ['environments must be an array'], warnings
    envs = {e.get('id'): e for e in env_list if isinstance(e, dict)}
    if len(envs) != len(env_list):
        err('duplicate/invalid environment IDs')
    for key, env in envs.items():
        if not key or env.get('capture_class') not in CAPTURE:
            err(f'environment {key}: invalid identity/capture class')
        for field in ('platform', 'device_model', 'os_version', 'flutter_version', 'build_mode', 'build_id'):
            if not isinstance(env.get(field), str) or not env[field].strip():
                err(f'environment {key}: missing {field}')
        if env.get('build_commit') != impl:
            err(f'environment {key}: build_commit differs from implementation_commit')
        cls = env.get('capture_class')
        if cls != 'widget_golden' and not SHA64.fullmatch(str(env.get('binary_sha256'))):
            err(f'environment {key}: missing tested binary_sha256')
        if cls == 'app_physical' and (env.get('is_physical') is not True or env.get('platform') not in {'ios', 'ipados'}):
            err(f'environment {key}: physical capture must be actual iPhone/iPad')
        if cls == 'app_simulator' and (env.get('is_physical') is not False or env.get('platform') not in {'ios', 'ipados'}):
            err(f'environment {key}: simulator capture must be iOS/iPadOS simulator')
        if cls == 'app_desktop' and env.get('platform') != 'macos':
            err(f'environment {key}: this PRD desktop gate targets macOS')
    def check_artifact(a: Any, case_id: str) -> dict[str, Any] | None:
        if not isinstance(a, dict):
            err(f'{case_id}: artifact must be an object'); return None
        kind = a.get('kind')
        if kind not in KINDS:
            err(f'{case_id}: invalid artifact kind {kind}')
        relative = a.get('path')
        try:
            path = safe_file(root, relative)
        except ValueError as exc:
            err(f'{case_id}: {exc}'); return None
        if 'design' in Path(relative).parts or 'templates' in Path(relative).parts:
            err(f'{case_id}: design/template files cannot count as evidence')
        if Path(relative).parts[0] != 'evidence':
            err(f'{case_id}: required evidence must be under evidence/')
        if not SHA64.fullmatch(str(a.get('sha256'))) or sha256(path) != a.get('sha256'):
            err(f'{case_id}: SHA-256 mismatch: {relative}')
        if path.stat().st_size == 0:
            err(f'{case_id}: empty artifact: {relative}')
        if a.get('implementation_commit') != impl:
            err(f'{case_id}: artifact not from final implementation: {relative}')
        if not utc_time(a.get('captured_at')):
            err(f'{case_id}: captured_at needs timestamp with timezone: {relative}')
        if kind in {'screenshot', 'video'}:
            env = envs.get(a.get('environment_id'))
            if env is None:
                err(f'{case_id}: unknown environment: {relative}')
            if a.get('role') != 'after' or a.get('modified') is not False:
                err(f'{case_id}: only unmodified after captures count: {relative}')
        if kind == 'screenshot':
            with path.open('rb') as stream:
                head = stream.read(24)
            if path.suffix.lower() != '.png' or len(head) < 24 or head[:8] != b'\x89PNG\r\n\x1a\n':
                err(f'{case_id}: screenshot must be raw PNG: {relative}')
            else:
                dims = struct.unpack('>II', head[16:24])
                if tuple(a.get('pixel_size', [])) != dims:
                    err(f'{case_id}: recorded dimensions differ from PNG: {relative}')
            for key in ('orientation', 'locale', 'theme', 'font_policy', 'keyboard', 'description'):
                if not isinstance(a.get(key), str) or not a[key].strip():
                    err(f'{case_id}: missing screenshot {key}: {relative}')
            viewport = a.get('viewport_logical', [])
            if not isinstance(viewport, list) or len(viewport) != 2 or any(not isinstance(v,(int,float)) or v <= 0 for v in viewport):
                err(f'{case_id}: invalid logical viewport')
            if not isinstance(a.get('pixel_ratio'), (int,float)) or a['pixel_ratio'] <= 0:
                err(f'{case_id}: invalid pixel_ratio')
        if kind == 'video' and path.suffix.lower() not in {'.mp4', '.mov', '.webm'}:
            err(f'{case_id}: unsupported video suffix: {relative}')
        return a
    for case_id, row in actual.items():
        if row.get('status') not in CASE_STATUS:
            err(f'{case_id}: invalid case status')
        want = planned.get(case_id)
        if not want:
            continue
        if set(row.get('requirement_ids', [])) != set(want['requirement_ids']):
            err(f'{case_id}: requirement mapping changed')
        artifacts = row.get('artifacts', [])
        if not isinstance(artifacts, list):
            err(f'{case_id}: artifacts must be an array'); continue
        checked = [r for a in artifacts if (r := check_artifact(a, case_id)) is not None]
        if row.get('status') in {'failed', 'blocked'} and not row.get('notes'):
            err(f'{case_id}: failed/blocked needs a reason')
        if row.get('status') != 'passed':
            continue
        screenshots = [a for a in checked if a.get('kind') == 'screenshot']
        qualified = []
        for a in screenshots:
            env = envs.get(a.get('environment_id'), {})
            platform = expected_platform(case_id)
            # Hardware keyboard S2 may be demonstrated on iPad at this stage.
            platform_ok = env.get('platform') == platform or platform is None or (case_id=='S2-T10' and env.get('platform')=='ipados')
            if platform_ok and qualifies(env.get('capture_class',''), want['minimum_capture_class']):
                qualified.append(a)
        if not qualified:
            err(f'{case_id}: no qualified screenshot for {want["minimum_capture_class"]} / {expected_platform(case_id)}')
        logs = {a['path'] for a in checked if a.get('kind') == 'log'}
        if not logs:
            err(f'{case_id}: missing behavioral/test log')
        assertions = row.get('assertions', [])
        if not isinstance(assertions, list) or not assertions:
            err(f'{case_id}: passed case requires assertions')
        else:
            for assertion in assertions:
                if not isinstance(assertion,dict) or assertion.get('passed') is not True or not all(assertion.get(k) for k in ('name','expected','actual')) or assertion.get('proof_path') not in logs:
                    err(f'{case_id}: assertion lacks result or a corresponding log')
        if want.get('video_required') and not any(a.get('kind')=='video' for a in checked):
            err(f'{case_id}: continuous video required')
        if not isinstance(row.get('steps'),list) or not row['steps'] or not row.get('observed_result'):
            err(f'{case_id}: missing actual steps or observation')
    stages = manifest.get('stages', {})
    if not isinstance(stages,dict) or set(stages) != set(STAGES):
        err('stages must contain S1 through S4'); stages = {}
    for stage, status in stages.items():
        if status not in STAGE_STATUS:
            err(f'{stage}: invalid stage status')
        if status == 'verified' and any(actual.get(k,{}).get('status')!='passed' for k in planned if k.startswith(stage+'-')):
            err(f'{stage}: verified with non-passed cases')
    for a in manifest.get('shared_artifacts', []):
        check_artifact(a, 'shared')
    if gate:
        required = STAGES[:STAGES.index(gate)+1]
        for stage in required:
            if stages.get(stage) != 'verified':
                err(f'{stage}: gate requires verified stage')
            for case_id in planned:
                if case_id.startswith(stage+'-') and actual.get(case_id,{}).get('status')!='passed':
                    err(f'{case_id}: not passed')
        for issue in manifest.get('open_issues', []):
            if issue.get('severity')=='P0' or (issue.get('severity')=='P1' and issue.get('core_flow') is not False):
                err(f'open blocking issue: {issue.get("id", "unknown")}')
        if not manifest.get('source_hashes'):
            err('gated validation requires source_hashes')
        roles={a.get('role') for a in manifest.get('shared_artifacts',[]) if a.get('kind')=='log'}
        if 'build' not in roles:
            err('missing shared build log')
        if gate=='S4':
            if 'repo_verify' not in roles:
                err('S4 requires complete repository verify log')
            if repo_root is None:
                err('S4 requires --repo-root for implementation/source verification')
            for rel in ['STATUS.md','results/S1.md','results/S2.md','results/S3.md','results/S4.md','results/FINAL_REVIEW.md']:
                try: safe_file(root,rel)
                except ValueError as exc: err(str(exc))
    if repo_root is not None and SHA40.fullmatch(str(impl)):
        try:
            subprocess.run(['git','-C',str(repo_root),'cat-file','-e',f'{impl}^{{commit}}'],check=True,capture_output=True)
            for rel, digest in manifest.get('source_hashes',{}).items():
                if not SHA64.fullmatch(str(digest)) or Path(rel).is_absolute() or '..' in Path(rel).parts:
                    err(f'invalid source hash entry: {rel}'); continue
                data=subprocess.run(['git','-C',str(repo_root),'show',f'{impl}:{rel}'],check=True,capture_output=True).stdout
                if hashlib.sha256(data).hexdigest()!=digest:
                    err(f'source hash differs at implementation commit: {rel}')
                work=(repo_root/rel).resolve()
                if not work.is_relative_to(repo_root.resolve()) or not work.is_file() or sha256(work)!=digest:
                    err(f'current source differs from captured implementation: {rel}')
        except (subprocess.CalledProcessError,OSError) as exc:
            err(f'git source verification failed: {exc}')
    elif gate and repo_root is None:
        warnings.append('No --repo-root: source/commit correspondence not verified.')
    warnings.append('Integrity checks do not certify screenshot authenticity, UI behavior, accessibility or runtime safety.')
    return errors,warnings

def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('manifest',type=Path)
    ap.add_argument('--root',type=Path,help='PRD root; defaults to scripts parent')
    ap.add_argument('--plan',type=Path,help='coverage plan; defaults to ROOT/plan.json')
    group=ap.add_mutually_exclusive_group()
    group.add_argument('--gate',choices=STAGES,help='require passed stages up to this stage')
    group.add_argument('--structure-only',action='store_true',help='validate template/integrity, without stage completion gate')
    ap.add_argument('--repo-root',type=Path)
    args=ap.parse_args()
    root=(args.root or Path(__file__).resolve().parents[1]).resolve()
    try:
        manifest=json.loads(args.manifest.read_text(encoding='utf-8'))
        plan=json.loads((args.plan or root/'plan.json').read_text(encoding='utf-8'))
        errors,warnings=validate(manifest,plan,root,args.gate,args.repo_root)
    except (OSError,ValueError,TypeError,KeyError) as exc:
        print(f'Invalid input: {exc}',file=sys.stderr); return 2
    for w in warnings: print('WARNING:',w)
    for e in errors: print('ERROR:',e,file=sys.stderr)
    if errors:
        print(f'REJECTED: {len(errors)} issue(s).',file=sys.stderr); return 1
    print('STRUCTURE/INTEGRITY CHECK PASSED.' if not args.gate else f'{args.gate} evidence gate satisfied; human review still required.')
    return 0

if __name__=='__main__':
    raise SystemExit(main())

"""Record a manually observed UI completion and its passive inference audit.

This never operates the application, approves an action or solves a task.
Call only after observing completion (or failure) in the real Trail UI.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'tmp/terminal-bench/ui-2-1'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('job')
    parser.add_argument('--start', required=True)
    parser.add_argument('--end')
    parser.add_argument('--mode', choices=['normal', 'blocks'], required=True)
    parser.add_argument('--approvals', type=int, required=True)
    parser.add_argument('--result', required=True)
    parser.add_argument('--classification')
    parser.add_argument('--reason')
    parser.add_argument('--followup', action='append', default=[])
    args = parser.parse_args()
    start = datetime.fromisoformat(args.start)
    end = datetime.fromisoformat(args.end) if args.end else datetime.now(timezone.utc)
    if start.tzinfo is None or end.tzinfo is None or end < start:
        parser.error('Explicit timezone and ordered timestamps required')
    job = BASE / 'jobs' / args.job
    config = json.loads((job / 'config.json').read_text())
    model = config['agents'][0]['model_name']
    agent, = job.glob('*/agent')
    evidence = BASE / 'evidence' / args.job
    if not evidence.is_dir() or not list(evidence.glob('*.png')):
        parser.error('Completion requires retained real UI screenshots')
    rows = [json.loads(line) for line in (BASE / 'inference.jsonl').read_text().splitlines()]
    rows = [r for r in rows if start <= datetime.fromisoformat(r['started_at']) <= end
            and r['requested_model'] == model]
    record = dict(
        source='trail-real-ui', platform='macos', os='27.0.1 (26A434)',
        terminal_mode=args.mode, requested_model=model,
        response_models=sorted(set(r.get('response_model', 'unknown') for r in rows)),
        model_identity_verified=bool(rows) and all(r.get('response_model') == model for r in rows),
        ui_started_at=start.isoformat(), completed_at=end.isoformat(),
        approvals=args.approvals, requests=len(rows), evidence=str(evidence.relative_to(ROOT)),
        ui_result=args.result, followups=args.followup,
        instruction_verified='Official original prompt entered through UI; app trims surrounding whitespace.',
    )
    for key, field in [('input_tokens', 'prompt_tokens'), ('output_tokens', 'completion_tokens')]:
        record[key] = sum(r.get('usage', {}).get(field, 0) for r in rows) if rows else None
    record['cached_tokens'] = sum(r.get('usage', {}).get('prompt_tokens_details', {}).get('cached_tokens', 0)
                                  for r in rows) if rows else None
    if args.classification:
        record['classification'] = args.classification
    if args.reason:
        record['reason'] = args.reason
    (evidence / 'inference.json').write_text(json.dumps(rows, indent=2) + '\n')
    output = agent / 'ui-complete.json'
    if output.exists():
        parser.error('Completion already recorded; preserve the original attempt')
    output.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({k: record[k] for k in ['requests', 'response_models', 'input_tokens', 'output_tokens', 'cached_tokens']}))


if __name__ == '__main__':
    main()

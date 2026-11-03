#!/usr/bin/env python3
"""Summarize actual recording-run evidence; partial/probe runs never pass duration.

Performance values are observations, not self-selected product thresholds.
Input-to-frame is runtime echo dispatch, not physical keyboard latency. CPU
intervals crossing workload boundaries are omitted from per-phase comparisons.
"""
import argparse
import json
import math
import statistics
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def utc(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


def cpu_seconds(value):
    token = value.split()[0]
    days = 0
    if '-' in token:
        day, token = token.split('-', 1)
        days = int(day)
    fields = [float(part) for part in token.split(':')]
    if len(fields) not in (2, 3):
        raise ValueError('Unexpected ps CPU time')
    total = 0.0
    for field in fields:
        total = total * 60 + field
    return days * 86400 + total


def stats(values):
    if not values:
        return {'count': 0}
    ordered = sorted(values)
    return {'count': len(values), 'min': ordered[0],
            'median': statistics.median(ordered),
            'p95': ordered[math.ceil(len(ordered) * .95) - 1],
            'max': ordered[-1]}


def histogram(value):
    bounds, buckets = value['upper_bounds_micros'], value['buckets']
    count = value['count']
    if (len(buckets) != len(bounds) + 1 or sum(buckets) != count or
            any(n < 0 for n in buckets) or bounds != sorted(set(bounds))):
        raise ValueError('Invalid histogram')
    out = {'count': count, 'mean_micros': value['sum_micros'] / count if count else None,
           'max_micros': value['max_micros']}
    for q in (.5, .95, .99):
        upper = None
        accumulated = 0
        if count:
            for i, n in enumerate(buckets):
                accumulated += n
                if accumulated >= math.ceil(count * q):
                    upper = bounds[i] if i < len(bounds) else value['max_micros']
                    break
        out[f'p{round(q * 100)}_upper_micros'] = upper
    return out


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def review(directory):
    directory = directory.resolve()
    runner = read_json(directory / 'runner.json')
    result = read_json(directory / 'result.json')
    reopened = read_json(directory / 'reopen-result.json')
    path = directory / 'metrics.jsonl'
    raw = path.read_text() if path.exists() else ''
    lines = raw.splitlines(keepends=True)
    partial_line = bool(lines and not lines[-1].endswith('\n'))
    if partial_line:
        lines.pop()
    samples = [json.loads(line) for line in lines]
    errors = []
    groups = defaultdict(lambda: {'rss_bytes': [], 'cpu_percent_one_core': [], 'library_bytes': []})
    hourly = defaultdict(list)
    previous = None
    captures = {}
    ids = None
    gaps, recording_samples = [], []
    for sample in samples:
        phase = sample['phase']
        group = groups[phase]
        group['rss_bytes'].append(sample['rss_bytes'])
        group['library_bytes'].append(sample['library_bytes'])
        cpu = cpu_seconds(sample['ps_time_rss_kib_cpu_percent'])
        if previous:
            elapsed = (sample['elapsed_micros'] - previous['elapsed_micros']) / 1e6
            wall = (utc(sample['utc']) - utc(previous['utc'])).total_seconds()
            if elapsed <= 0 or wall <= 0:
                errors.append('non-monotonic sample clock')
            if sample['pid'] != previous['pid']:
                errors.append('recording PID changed within metrics')
            delta_cpu = cpu - cpu_seconds(previous['ps_time_rss_kib_cpu_percent'])
            if delta_cpu < 0:
                errors.append('cumulative CPU time decreased')
            if previous['phase'].startswith('recording/') and phase.startswith('recording/'):
                gaps.append(max(elapsed, wall))
            if phase == previous['phase'] and elapsed > 0:
                group['cpu_percent_one_core'].append(delta_cpu / elapsed * 100)
        if phase.startswith('recording/'):
            recording_samples.append(sample)
            current_ids = {c['capture_id'] for c in sample['captures']}
            if len(current_ids) != 2:
                errors.append('recording sample does not contain two writers')
            if ids is None:
                ids = current_ids
            elif ids != current_ids:
                errors.append('capture identity changed')
            hour = (sample['elapsed_micros'] - recording_samples[0]['elapsed_micros']) // 3600000000
            hourly[hour].append(sample['rss_bytes'])
            for capture in sample['captures']:
                if capture['committed_records'] > capture['written_records']:
                    errors.append('acknowledged records exceed written records')
                if capture['committed_duration_micros'] > capture['written_duration_micros']:
                    errors.append('acknowledged timeline exceeds written timeline')
                old = captures.get(capture['capture_id'])
                if old and any(capture[k] < old[k] for k in ('written_records', 'committed_records', 'written_duration_micros', 'committed_duration_micros')):
                    errors.append('writer progress went backwards')
                captures[capture['capture_id']] = capture
        previous = sample
    if any(gap >= 120 for gap in gaps):
        errors.append('recording continuity gap reached two minutes')
    if partial_line and runner.get('phase') == 'finished':
        errors.append('completed run has a partial final metric')
    recordings = result.get('recordings', [])
    requested = result.get('requested_seconds', 0)
    duration = result.get('capture_elapsed_micros', 0) / 1e6
    wall_duration = None
    if result.get('capture_started_utc') and result.get('capture_ended_utc'):
        wall_duration = (utc(result['capture_ended_utc']) - utc(result['capture_started_utc'])).total_seconds()
    metric_span = 0
    coverage = False
    if len(recording_samples) >= 2:
        first, last = recording_samples[0], recording_samples[-1]
        metric_span = (last['elapsed_micros'] - first['elapsed_micros']) / 1e6
        if wall_duration is not None:
            leading = (utc(first['utc']) - utc(result['capture_started_utc'])).total_seconds()
            trailing = (utc(result['capture_ended_utc']) - utc(last['utc'])).total_seconds()
            coverage = 0 <= leading < 30 and 0 <= trailing < 30
    checks = {
        'runner_finished_successfully': runner.get('phase') == 'finished' and runner.get('passed') is True,
        'not_probe_or_superseded': runner.get('probe') is False and not (directory / 'superseded.json').exists(),
        'actual_release_capture_over_24h': result.get('release_mode') is True and duration > 86400 and requested > 86400,
        'utc_and_monotonic_agree': wall_duration is not None and abs(wall_duration - duration) < 5,
        'application_and_shutdown_passed': result.get('passed') is True and result.get('safe_to_terminate') is True,
        'two_full_duration_recordings': len(recordings) == 2 and {r['name'] for r in recordings} == {'local', 'ssh'} and all(r['duration_micros'] >= requested * 1000000 for r in recordings),
        'continuous_metrics_cover_run': metric_span > 86400 and coverage and not errors,
        'metrics_match_application_and_files': bool(recording_samples) and
            all(s['pid'] == result.get('pid') for s in recording_samples) and
            ids == {r['id'] for r in recordings},
        'new_process_reopen_passed': runner.get('reopen_passed') is True and reopened.get('passed') is True and reopened.get('safe_to_terminate') is True and reopened.get('previous_pid') == result.get('pid') and reopened.get('pid') != result.get('pid'),
        'matching_revision': bool(runner.get('revision')) and runner.get('revision') == result.get('revision') == reopened.get('revision'),
        'primary_hashes_reported_unchanged': len(runner.get('primary_files_unchanged', {})) == 2,
        'owned_fixture_cleanup_complete': runner.get('fixture_cleanup_complete') is True,
    }
    latency = {}
    for name in ('frame_build', 'frame_raster', 'input_to_frame', 'workload_completion'):
        latency[name] = {phase: histogram(h) for phase, h in result.get(name, {}).items()}
    return {
        'directory': str(directory), 'revision': runner.get('revision'),
        'duration_and_continuity_verified': all(checks.values()),
        'checks': checks, 'integrity_errors': sorted(set(errors)),
        'performance_acceptance': 'requires review; no universal thresholds inferred',
        'sample_count': len(samples), 'partial_metric_ignored': partial_line,
        'capture_seconds': duration, 'capture_utc_seconds': wall_duration,
        'recording_metric_span_seconds': metric_span,
        'maximum_recording_metric_gap_seconds': max(gaps, default=None),
        'minimum_free_disk_bytes': min((s['available_disk_kib'] * 1024 for s in samples), default=None),
        'by_phase': {phase: {key: stats(values) for key, values in group.items()} for phase, group in sorted(groups.items())},
        'rss_by_recording_hour': {str(hour): stats(values) for hour, values in sorted(hourly.items())},
        'latency_histogram_upper_bounds': latency,
        'file_latency_micros': [{'name': r['name'], 'duration_micros': r['duration_micros'], 'source_bytes': r['source_bytes'], 'open': r['open_micros'], 'seek': stats(r['seek_micros']), 'command_search': stats(r['command_search_micros'])} for r in recordings],
        'limits': ['CPU is percent of one logical core, per-phase intervals omit transitions.', 'Histogram quantiles are bucket upper bounds, not exact quantiles.', 'Input timing is runtime echo dispatch to frame with 20 ms readiness polling.', 'File timing does not establish an OS-cold disk cache.', 'Partial runs provide observations only and cannot satisfy duration acceptance.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--require-duration', action='store_true',
                        help='Exit nonzero unless duration/continuity evidence passes; performance still needs review')
    args = parser.parse_args()
    report = review(args.directory)
    print(json.dumps(report, indent=2))
    return 1 if args.require_duration and not report['duration_and_continuity_verified'] else 0


if __name__ == '__main__':
    sys.exit(main())

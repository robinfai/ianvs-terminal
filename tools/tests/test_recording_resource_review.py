import importlib.util
import json
import subprocess
import sys
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

spec = importlib.util.spec_from_file_location('review', Path(__file__).resolve().parents[1] / 'recording_bench' / 'review-soak.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EvidenceReviewTest(unittest.TestCase):
    def test_cpu_and_histogram_units(self):
        self.assertEqual(module.cpu_seconds('2:03.25 12 0.0'), 123.25)
        self.assertEqual(module.cpu_seconds('1:02:03.25 12 0.0'), 3723.25)
        self.assertEqual(module.cpu_seconds('1-01:02:03.25 12 0.0'), 90123.25)
        h = {'count': 100, 'sum_micros': 1500, 'max_micros': 31,
             'upper_bounds_micros': [10, 20], 'buckets': [50, 44, 6]}
        out = module.histogram(h)
        self.assertEqual(out['p50_upper_micros'], 10)
        self.assertEqual(out['p95_upper_micros'], 31)
        self.assertEqual(out['mean_micros'], 15)
        with self.assertRaises(ValueError):
            module.histogram({**h, 'count': 101})

    def test_required_duration_cli_rejects_missing_evidence(self):
        with TemporaryDirectory(prefix='recording-review-unit-') as tmp:
            process = subprocess.run(
                [sys.executable, '-B', spec.origin, tmp, '--require-duration'],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(process.returncode, 1)
            self.assertFalse(json.loads(process.stdout)['duration_and_continuity_verified'])

    def test_incomplete_directory_never_passes(self):
        with TemporaryDirectory(prefix='recording-review-unit-') as tmp:
            self.assertFalse(module.review(Path(tmp))['duration_and_continuity_verified'])

    def test_synthetic_complete_evidence_requires_every_gate(self):
        # Fabricated unit-test data exercise the reviewer, never establish a run.
        started = datetime(2020, 1, 1, tzinfo=timezone.utc)
        runner = dict(phase='finished', passed=True, probe=False, revision='fixture',
                      reopen_passed=True, fixture_cleanup_complete=True,
                      primary_files_unchanged={'one': 'a', 'two': 'b'})
        result = dict(requested_seconds=90000, capture_elapsed_micros=90000_000000,
                      capture_started_utc=started.isoformat(),
                      capture_ended_utc=(started+timedelta(seconds=90000)).isoformat(),
                      release_mode=True, passed=True, safe_to_terminate=True,
                      revision='fixture', pid=123, recordings=[])
        for name in ('local', 'ssh'):
            result['recordings'].append(dict(name=name, id=name, duration_micros=90000_000000,
                                             source_bytes=1, open_micros=1,
                                             seek_micros=[1], command_search_micros=[1]))
        reopened = dict(passed=True, safe_to_terminate=True, revision='fixture', previous_pid=123, pid=456)
        samples = []
        for seconds in range(0, 90001, 60):
            samples.append(dict(phase='recording/shell', pid=123, elapsed_micros=seconds*1000000,
                                utc=(started+timedelta(seconds=seconds)).isoformat(),
                                rss_bytes=100, library_bytes=seconds,
                                ps_time_rss_kib_cpu_percent=f'{seconds//60}:00.00 1 100.0',
                                available_disk_kib=10000000,
                                captures=[dict(capture_id=name, written_records=seconds,
                                               committed_records=seconds,
                                               written_duration_micros=seconds*1000000,
                                               committed_duration_micros=seconds*1000000)
                                          for name in ('local', 'ssh')]))
        with TemporaryDirectory(prefix='recording-review-unit-') as tmp:
            directory=Path(tmp)
            def write(runner_value=runner, result_value=result, reopen_value=reopened, metric_value=samples):
                for name, value in [('runner', runner_value), ('result', result_value), ('reopen-result', reopen_value)]:
                    (directory/f'{name}.json').write_text(json.dumps(value))
                (directory/'metrics.jsonl').write_text(''.join(json.dumps(s)+'\n' for s in metric_value))
            write()
            self.assertTrue(module.review(directory)['duration_and_continuity_verified'])
            for patch in ({'probe': True}, {'passed': False}, {'phase': 'running'}, {'fixture_cleanup_complete': False}):
                write(runner_value={**runner, **patch})
                self.assertFalse(module.review(directory)['duration_and_continuity_verified'], patch)
            write(result_value={**result, 'capture_elapsed_micros': 86400_000000})
            self.assertFalse(module.review(directory)['duration_and_continuity_verified'])
            write(reopen_value={**reopened, 'pid': 123})
            self.assertFalse(module.review(directory)['duration_and_continuity_verified'])
            for kind in ('gap', 'backwards', 'pid', 'identity'):
                damaged=deepcopy(samples)
                if kind == 'gap': damaged.pop(20)
                elif kind == 'backwards': damaged[20]['captures'][0]['committed_records']=0
                elif kind == 'pid': damaged[20]['pid']=321
                else: damaged[20]['captures'][0]['capture_id']='replacement'
                write(metric_value=damaged)
                self.assertFalse(module.review(directory)['duration_and_continuity_verified'], kind)
            write()
            (directory/'superseded.json').write_text('{}')
            self.assertFalse(module.review(directory)['duration_and_continuity_verified'])


if __name__ == '__main__':
    unittest.main()

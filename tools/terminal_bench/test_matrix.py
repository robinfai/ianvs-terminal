import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from run_matrix import collect, fits_resources, harbor_pid, recover_completed, unavailable


class MatrixTests(unittest.TestCase):
    def test_resources_are_not_silently_reduced(self):
        base = {"cpus": 2, "memory_mb": 4096, "storage_mb": 10240, "gpus": 0}
        self.assertEqual(unavailable(base), [])
        self.assertEqual(unavailable({**base, "gpus": 1}), ["requires_H100"])
        self.assertEqual(unavailable({**base, "cpus": 16}), ["requires_more_than_10_cpus"])

    def test_parallel_admission_respects_cpu_memory_storage_and_slots(self):
        small = {"cpus": 2, "memory_mb": 4096, "storage_mb": 10240}
        self.assertTrue(fits_resources(small, [small]))
        self.assertFalse(fits_resources(small, [small, small]))
        self.assertFalse(fits_resources({**small, "cpus": 9}, [small]))
        large = {**small, "memory_mb": 16384}
        self.assertFalse(fits_resources(large, [large]))
        self.assertFalse(fits_resources({**small, "storage_mb": 51200}, [small]))
        self.assertTrue(fits_resources({**small, "storage_mb": 51200}, []))

    def test_adoption_matches_live_command_and_exact_job_directory(self):
        job = Path('/tmp/trail-test-matrix/task-model-1')
        listing = ('100 python /venv/bin/harbor run -o /tmp/unrelated --job-name task-model-1\n'
                   '200 python /venv/bin/harbor run -o /tmp/trail-test-matrix --job-name task-model-1\n')
        with patch('run_matrix.command', return_value=listing):
            self.assertEqual(harbor_pid(job), 200)
        with patch('run_matrix.command', return_value=''):
            self.assertIsNone(harbor_pid(job))

    def test_official_rewards_and_environment_errors_are_distinct(self):
        with tempfile.TemporaryDirectory() as temp:
            job = Path(temp)
            trial = job / "trial"
            trial.mkdir()
            path = trial / "result.json"
            path.write_text(json.dumps({"verifier_result": {"rewards": {"reward": 0.0}}}))
            self.assertEqual(collect(job)["status"], "failed")
            path.write_text(json.dumps({"verifier_result": {"rewards": {"reward": 1.0}}}))
            self.assertEqual(collect(job)["status"], "passed")
            path.write_text(json.dumps({"exception_info": {"exception_type": "RuntimeError"},
                                        "agent_setup": None}))
            self.assertEqual(collect(job)["status"], "environment_error")
            path.write_text(json.dumps({"agent_setup": {}, "verifier_result": {}}))
            self.assertEqual(collect(job)["status"], "missing_reward")

    def test_resume_recovers_a_finished_trial_without_rerunning_model(self):
        with tempfile.TemporaryDirectory() as temp:
            job = Path(temp)
            (job / "trial").mkdir()
            (job / "trial/result.json").write_text(json.dumps({
                "started_at": "2026-10-01T00:00:00", "finished_at": "2026-10-01T00:01:00",
                "verifier_result": {"rewards": {"reward": 1.0}},
            }))
            saved = {"status": "running", "job": str(job), "attempt": 1}
            recovered = recover_completed(saved)
            self.assertEqual(recovered["status"], "passed")
            self.assertEqual(recovered["attempt"], 1)
            self.assertEqual(recovered["elapsed_sec"], 60)


if __name__ == "__main__":
    unittest.main()

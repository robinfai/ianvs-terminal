"""Non-invasive measurement attribution; fixtures never invoke Cargo/Flutter."""
import contextlib
from datetime import datetime, timezone, timedelta
import io
import json
import os
from pathlib import Path
import subprocess
import shlex
import shutil
import tempfile
import unittest
from unittest import mock

import native_phase_metrics as metrics
import time_command


class PhaseMetricsTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.output = self.root / "records"
        self.path = self.root / ".dart_tool/hooks_runner/shared/pty/build/ianvs-cargo-build.json"
        self.path.parent.mkdir(parents=True)
        self.silence = contextlib.redirect_stdout(io.StringIO())
        self.silence.__enter__()
        self.addCleanup(self.silence.__exit__, None, None, None)

    def write(self, path=None, source="canonical", **changes):
        manifest = "native/core/Cargo.toml" if source == "canonical" else "packages/ianvs_terminal_core/native/core/Cargo.toml"
        data = {"schema_version": 1, "exit_code": 0, "elapsed_ms": 0,
                "started_at": datetime.now(timezone.utc).isoformat(),
                "manifest_path": str(self.root / manifest), "target": "aarch64-apple-darwin",
                "profile": "release", "target_directory": str(self.path.parent / "cargo-target"),
                "build_environment": {"SECRET": "never-copy-me", "CARGO_BUILD_JOBS": "2"}}
        data.update(changes)
        (path or self.path).write_text(json.dumps(data))

    def start(self, label="test"):
        return metrics.begin(label, self.root, self.output)

    def test_changed_measurement_is_attributed_once_and_sanitized(self):
        state = self.start()
        self.write()
        result = metrics.finish(state, 0)
        self.assertEqual(result["hook_build_count"], 1)
        self.assertEqual(result["hooks"][0]["source"], "canonical")
        self.assertNotIn("never-copy-me", json.dumps(result))
        self.assertEqual(result["hooks"][0]["cache_status"], "unknown")
        self.assertEqual(metrics.finish(self.start(), 0)["hook_build_count"], 0)

    def test_old_file_is_not_a_new_build(self):
        self.write()
        result = metrics.finish(self.start(), 0)
        self.assertEqual(result["hook_build_count"], 0)
        self.assertEqual(result["unchanged_metrics"], 1)

    def test_new_file_with_old_timestamp_is_not_attributed(self):
        state = self.start()
        self.write(started_at=(datetime.now(timezone.utc) - timedelta(days=1)).isoformat())
        result = metrics.finish(state, 0)
        self.assertEqual(result["hook_build_count"], 0)
        self.assertEqual(result["out_of_window_metrics"], 1)

    def test_failed_packaged_build_is_preserved(self):
        state = self.start()
        self.write(source="packaged", exit_code=101)
        result = metrics.finish(state, 1)
        self.assertEqual(result["exit_code"], 1)
        self.assertEqual(result["hooks"][0]["source"], "packaged")
        self.assertEqual(result["hooks"][0]["exit_code"], 101)

    def test_invalid_metric_is_reported_not_silently_zero(self):
        for changes in ({"elapsed_ms": True}, {"schema_version": 99}, {"started_at": "bad"}, {"manifest_path": "/outside/Cargo.toml"}):
            state = self.start()
            self.write(**changes)
            result = metrics.finish(state, 0)
            self.assertTrue(result["collection_errors"])
            self.assertEqual(result["hook_build_count"], 0)

    def test_malformed_and_missing_metrics_are_diagnostics(self):
        self.path.write_text("{")
        state = self.start()
        self.path.unlink()
        result = metrics.finish(state, 7)
        self.assertTrue(result["collection_errors"])
        self.assertEqual(result["exit_code"], 7)

    def test_parent_does_not_double_count_child_measurements(self):
        parent = self.start("repository")
        child = self.start("PTY")
        self.write()
        leaf = metrics.finish(child, 0)
        top = metrics.finish(parent, 0)
        self.assertEqual((leaf["hook_build_count"], top["hook_build_count"]), (1, 0))
        self.assertIn(leaf["id"], top["nested_phase_ids"])
        self.assertIsNone(top["unattributed_seconds"])

    def test_discovery_skips_cargo_targets_and_symlinks(self):
        excluded = self.path.parent / "cargo-target/nested"
        excluded.mkdir(parents=True)
        self.write(path=excluded / metrics.METRIC_NAME)
        link = self.path.parent / "link"
        link.symlink_to(excluded, target_is_directory=True)
        self.assertEqual(metrics.discover(self.root), [])

    def test_overlap_uses_union_not_sum_for_wall_time(self):
        self.assertEqual(metrics.union_seconds([(0, 3), (1, 5), (6, 8)]), 7)

    def test_time_wrapper_does_not_retry_or_change_failure(self):
        with mock.patch.dict(os.environ, {"IANVS_CI_NATIVE_METRICS": "1"}), \
             mock.patch.object(time_command.native_phase_metrics, "begin", return_value=Path("fixture")), \
             mock.patch.object(time_command.native_phase_metrics, "finish") as finish, \
             mock.patch.object(time_command.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)) as run:
            self.assertEqual(time_command.main(["test", "--", "fixture"]), 7)
            run.assert_called_once_with(["fixture"], check=False)
            finish.assert_called_once_with(Path("fixture"), 7)

    def test_shell_exit_trap_records_failure_without_suppressing_errexit(self):
        tools = self.root / "tools/ci"
        tools.mkdir(parents=True)
        shutil.copy2(Path(metrics.__file__), tools / "native_phase_metrics.py")
        source = (metrics.ROOT / "tools/verify_flutter_terminal.sh").read_text()
        function = source.split("ci_begin_phase() {", 1)[1].split("\n}\n", 1)[0]
        script = ("set -euo pipefail\nROOT_DIR=" + shlex.quote(str(self.root)) +
                  "\nci_begin_phase() {" + function + "\n}\n" +
                  '( ci_begin_phase "fixture failure"; false; echo UNREACHABLE )')
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                                env=dict(os.environ, IANVS_CI_NATIVE_METRICS="1"), timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("UNREACHABLE", result.stdout)
        records = [json.loads(p.read_text()) for p in (self.root / "build/ci/native-phases").glob("*.json")
                   if not p.name.endswith(".start.json")]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["exit_code"], 1)

    def test_workflow_retains_strict_gates_and_uploads_measurements(self):
        text = (metrics.ROOT / ".github/workflows/verify.yml").read_text()
        for name in ("flutter-native-phase-diagnostics", "example-native-phase-diagnostics"):
            self.assertIn("name: " + name, text)
        self.assertEqual(text.count("path: build/ci/native-phases/"), 2)
        self.assertIn('test "$EXAMPLE_RESULT" = success', text)
        self.assertIn('test "$FLUTTER_RESULT" = success', text)
        self.assertNotIn("continue-on-error", text)


if __name__ == "__main__":
    unittest.main()

"""Dependency-free regression tests for preparation and the real runner driver."""
import contextlib
import io
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import prepare_example_dependencies as deps
import run_example_parallel as runner

ROOT = Path(__file__).resolve().parents[2]


def result(code, text=""):
    return subprocess.CompletedProcess([], code, text)


class DependencyTests(unittest.TestCase):
    def call_fetch(self, responses):
        with mock.patch.object(deps.subprocess, "run", side_effect=responses) as run, \
             mock.patch.object(deps.time, "sleep") as sleep, contextlib.redirect_stdout(io.StringIO()):
            code = deps.fetch(Path("/fixture/native/core/Cargo.toml"), "aarch64-apple-darwin")
        return code, run.call_args_list, sleep.call_args_list

    def test_complete_cache_never_needs_network(self):
        code, calls, sleeps = self.call_fetch([result(0)])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("--offline", calls[0].args[0])
        self.assertEqual(sleeps, [])

    def test_incomplete_cache_fetches_locked_host_dependencies(self):
        code, calls, _ = self.call_fetch([result(101, "missing crate"), result(0)])
        self.assertEqual(code, 0)
        self.assertNotIn("--offline", calls[1].args[0])
        for call in calls:
            self.assertIn("--locked", call.args[0])
            self.assertIn("aarch64-apple-darwin", call.args[0])
            self.assertEqual(call.kwargs["timeout"], 120)
            self.assertNotIn("CARGO_NET_OFFLINE", call.kwargs["env"])
            self.assertNotIn("CARGO_HTTP_SSL_VERIFY", call.kwargs["env"])

    def test_dns_failure_retries_only_download(self):
        code, calls, sleeps = self.call_fetch([result(101), result(101, "Could not resolve host: index.crates.io"), result(0)])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 3)
        self.assertEqual(sleeps, [mock.call(5)])
        self.assertTrue(all(c.args[0][:2] == ["cargo", "fetch"] for c in calls))

    def test_transient_failure_has_a_hard_attempt_limit(self):
        code, calls, sleeps = self.call_fetch([result(101)] + [result(101, "HTTP response: 503")] * 3)
        self.assertEqual(code, 101)
        self.assertEqual(len(calls), 4)  # offline plus at most three online attempts
        self.assertEqual(sleeps, [mock.call(5), mock.call(10)])

    def test_fetch_timeout_is_bounded(self):
        code, calls, _ = self.call_fetch([result(101)] + [subprocess.TimeoutExpired("cargo", 120)] * 3)
        self.assertEqual(code, 124)
        self.assertEqual(len(calls), 4)

    def test_permanent_failures_are_not_retried(self):
        for text in ("failed to parse manifest", "lock file needs to be updated", "checksum mismatch", "SSL certificate problem", "unknown error"):
            with self.subTest(text=text):
                code, calls, sleeps = self.call_fetch([result(101), result(101, text)])
                self.assertEqual(code, 101)
                self.assertEqual(len(calls), 2)
                self.assertEqual(sleeps, [])

    def test_tls_error_not_retried_even_with_http_503_text(self):
        code, calls, _ = self.call_fetch([result(101), result(101, "HTTP 503: certificate problem")])
        self.assertEqual((code, len(calls)), (101, 2))

    def test_missing_lockfile_fails_before_fetch(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(deps, "ROOT", Path(tmp)), \
             mock.patch.object(deps.subprocess, "check_output", return_value="host: aarch64-apple-darwin\n"), \
             mock.patch.object(deps, "fetch") as fetch:
            with self.assertRaises(ValueError):
                deps.main()
            fetch.assert_not_called()

    def test_second_manifest_failure_is_propagated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for relative in deps.MANIFESTS:
                manifest = root / relative
                manifest.parent.mkdir(parents=True)
                manifest.touch()
                manifest.with_name("Cargo.lock").touch()
            with mock.patch.object(deps, "ROOT", root), \
                 mock.patch.object(deps.subprocess, "check_output", return_value="host: aarch64-apple-darwin\n"), \
                 mock.patch.object(deps, "fetch", side_effect=[0, 101]) as fetch:
                self.assertEqual(deps.main(), 101)
                self.assertEqual(fetch.call_count, 2)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.example = self.root / "example"
        self.example.mkdir()
        self.output = self.root / "diagnostics"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.invocations = self.root / "invocations.jsonl"
        env = mock.patch.dict(os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ["PATH"]})
        env.start()
        self.addCleanup(env.stop)

    def stub_flutter(self, code=0):
        source = f'''#!{sys.executable}
import json, sys
from pathlib import Path
with Path({str(self.invocations)!r}).open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
print("first-output", flush=True)
print("x" * 20000, flush=True)
print("last-output", flush=True)
sys.exit({code})
'''
        executable = self.bin / "flutter"
        executable.write_text(source)
        executable.chmod(0o755)

    def test_discovery_matches_canonical_exclusions_and_new_files(self):
        names = ["test/design/a_test.dart", "test/benchmarks/cat_log_benchmark_test.dart",
                 "test/designated_test.dart", "test/new/中文 with spaces_test.dart",
                 "test/benchmarks/other_test.dart", "test/new/multi\nline_test.dart"]
        for name in names:
            path = self.example / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        self.assertEqual(runner.discover(self.example), sorted(names[2:]))

    def test_single_flutter_invocation_owns_concurrency_and_all_files(self):
        self.stub_flutter()
        tests = ["test/a_test.dart", "test/name with spaces_test.dart", "test/中文_test.dart"]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.run_tests(self.example, tests, 2, self.output), 0)
        calls = [json.loads(line) for line in self.invocations.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0], ["test", "--no-pub", "--reporter=expanded", "--concurrency=2", *tests])
        self.assertEqual(json.loads((self.output / "test-files.json").read_text()), tests)

    def test_full_log_is_persistent_not_tail_only(self):
        self.stub_flutter()
        with contextlib.redirect_stdout(io.StringIO()):
            runner.run_tests(self.example, ["test/a_test.dart"], 1, self.output)
        log = (self.output / "flutter.log").read_text()
        self.assertGreater(len(log), 20000)
        self.assertIn("first-output", log)
        self.assertIn("last-output", log)
        self.assertEqual(json.loads((self.output / "summary.json").read_text())["concurrency"], 1)

    def test_test_failure_code_preserved_without_retry(self):
        self.stub_flutter(7)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.run_tests(self.example, ["test/a_test.dart"], 2, self.output), 7)
        self.assertEqual(len(self.invocations.read_text().splitlines()), 1)
        self.assertEqual(json.loads((self.output / "summary.json").read_text())["exit_code"], 7)

    def test_invalid_or_duplicate_suite_does_not_launch_flutter(self):
        for tests, workers in (([], 2), (["a", "a"], 2), (["a"], 0), (["a"], 3)):
            with self.subTest(tests=tests, workers=workers), self.assertRaises(ValueError):
                runner.run_tests(self.example, tests, workers, self.output)
        self.assertFalse(self.invocations.exists())

    def test_launch_failure_leaves_failure_summary(self):
        with mock.patch.object(runner.subprocess, "Popen", side_effect=FileNotFoundError("flutter")), \
             contextlib.redirect_stdout(io.StringIO()), self.assertRaises(FileNotFoundError):
            runner.run_tests(self.example, ["test/a_test.dart"], 2, self.output)
        self.assertEqual(json.loads((self.output / "summary.json").read_text())["exit_code"], 1)

    def test_sigterm_stops_launcher_and_descendant(self):
        pidfile = self.root / "pids.json"
        executable = self.bin / "flutter"
        executable.write_text(f'''#!{sys.executable}
import os, json, subprocess, sys, time
from pathlib import Path
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
Path({str(pidfile)!r}).write_text(json.dumps([os.getpid(), child.pid]))
time.sleep(60)
''')
        executable.chmod(0o755)
        command = [sys.executable, "-c", f"import sys; sys.path.insert(0, {str(ROOT / 'tools/ci')!r}); from run_example_parallel import run_tests; from pathlib import Path; sys.exit(run_tests(Path({str(self.example)!r}), ['test/a_test.dart'], 2, Path({str(self.output)!r})))"]
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not pidfile.exists() and time.monotonic() < deadline and proc.poll() is None:
                time.sleep(0.02)
            self.assertTrue(pidfile.exists(), "fixture did not start")
            pids = json.loads(pidfile.read_text())
            proc.send_signal(signal.SIGTERM)
            stdout, stderr = proc.communicate(timeout=8)
            self.assertEqual(proc.returncode, 143, stdout + stderr)
            self.assertEqual(json.loads((self.output / "summary.json").read_text())["exit_code"], 143)
            for pid in pids:
                state = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True).stdout.strip()
                self.assertTrue(not state or state.startswith("Z"), f"process {pid} still running: {state}")
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.communicate(timeout=5)
            if pidfile.exists():
                for pid in json.loads(pidfile.read_text()):
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass


class WorkflowTests(unittest.TestCase):
    def test_dependency_preparation_precedes_offline_build_and_test(self):
        workflow = (ROOT / ".github/workflows/verify.yml").read_text()
        job = workflow.split("  example-checks:\n", 1)[1].split("  native-checks:\n", 1)[0]
        self.assertNotIn("matrix:", job)
        names = ("Cache Rust dependencies", "Prepare locked Example native dependencies",
                 "Build Example native debug library", "Run Example widget tests with bounded in-job concurrency")
        positions = [job.index("- name: " + name) for name in names]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(job.count('CARGO_NET_OFFLINE: "true"'), 2)
        self.assertNotIn("continue-on-error", job)
        self.assertIn("if: always()", job)
        self.assertIn("path: build/ci/example/", job)
        self.assertIn("test \"$EXAMPLE_RESULT\" = success", workflow)


if __name__ == "__main__":
    unittest.main()

"""Cancellation regressions: real POSIX processes plus deterministic OS races."""
import contextlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import run_example_parallel as runner


class GroupTests(unittest.TestCase):
    def test_snapshot_excludes_zombies_but_includes_stopped_processes(self):
        snapshot = " 41 40 S\n42 40 Z+\n43 40 T\n44 90 R\n"
        with mock.patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, snapshot)):
            self.assertEqual(runner.live_group_members(40), [41, 43])

    def test_snapshot_error_is_not_an_empty_group(self):
        with mock.patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("ps", 2)):
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.live_group_members(40)

    def test_malformed_snapshot_fails_closed(self):
        with mock.patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "bad output")):
            with self.assertRaises(RuntimeError):
                runner.live_group_members(40)

    def test_eperm_race_requires_a_fresh_empty_snapshot(self):
        for error in (PermissionError(1, "not permitted"), ProcessLookupError(3, "gone")):
            with self.subTest(error=type(error).__name__), \
                 mock.patch.object(runner.os, "killpg", side_effect=error), \
                 mock.patch.object(runner, "live_group_members", return_value=[]) as snapshot:
                runner.signal_live_group(400, signal.SIGKILL)
                snapshot.assert_called_once_with(400)

    def test_eperm_with_live_process_is_not_ignored(self):
        with mock.patch.object(runner.os, "killpg", side_effect=PermissionError(1, "not permitted")), \
             mock.patch.object(runner, "live_group_members", return_value=[401]):
            with self.assertRaises(PermissionError):
                runner.signal_live_group(400, signal.SIGKILL)

    def test_eperm_with_uninspectable_group_fails_closed(self):
        with mock.patch.object(runner.os, "killpg", side_effect=PermissionError(1, "not permitted")), \
             mock.patch.object(runner, "live_group_members", side_effect=RuntimeError("ps failed")):
            with self.assertRaises(RuntimeError):
                runner.signal_live_group(400, signal.SIGKILL)

    def test_already_exited_group_is_idempotent_without_signals(self):
        proc = mock.Mock(pid=999999)
        with mock.patch.object(runner, "live_group_members", return_value=[]), \
             mock.patch.object(runner.os, "killpg") as kill:
            runner.stop_process_group(proc)
            runner.stop_process_group(proc)
        kill.assert_not_called()

    def test_our_process_group_is_never_signalled(self):
        with self.assertRaises(RuntimeError):
            runner.stop_process_group(mock.Mock(pid=os.getpgrp()))

    def test_live_descendant_after_leader_exit_gets_kill(self):
        proc = mock.Mock(pid=999999, returncode=0)
        # TERM probe, wait probe, KILL probe, wait probe, final verification.
        with mock.patch.object(runner, "live_group_members", side_effect=[[2], [2], [2], [], []]), \
             mock.patch.object(runner, "signal_live_group") as send:
            runner.stop_process_group(proc, grace=0, kill_grace=0)
        self.assertEqual(send.call_args_list, [mock.call(proc.pid, signal.SIGTERM), mock.call(proc.pid, signal.SIGKILL)])

    def test_survivor_after_kill_fails_with_bounded_wait(self):
        with mock.patch.object(runner, "live_group_members", return_value=[2]), \
             mock.patch.object(runner, "signal_live_group"):
            with self.assertRaisesRegex(RuntimeError, "Live processes remain"):
                runner.stop_process_group(mock.Mock(pid=999999), grace=0, kill_grace=0)


class DriverTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.example = self.root / "example"
        self.example.mkdir()
        self.output = self.root / "output"
        patch = mock.patch.dict(os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ["PATH"]})
        patch.start()
        self.addCleanup(patch.stop)

    def stub(self, source):
        path = self.bin / "flutter"
        path.write_text(f"#!{sys.executable}\n" + source)
        path.chmod(0o755)

    def run_fixture(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.run_tests(self.example, ["test/a_test.dart"], 2, self.output)

    def summary(self):
        return json.loads((self.output / "summary.json").read_text())

    def test_success_preserves_full_log_and_one_invocation(self):
        calls = self.root / "calls"
        self.stub(f"import sys\nfrom pathlib import Path\nPath({str(calls)!r}).write_text(repr(sys.argv[1:]))\nprint('中文' + 'x' * 200000 + 'TAIL', flush=True)\n")
        self.assertEqual(self.run_fixture(), 0)
        self.assertIn("--concurrency=2", calls.read_text())
        self.assertTrue((self.output / "flutter.log").read_text().endswith("TAIL\n"))
        self.assertEqual(self.summary()["cleanup_status"], "success")

    def test_failure_exit_code_is_preserved(self):
        self.stub("import sys\nsys.exit(7)\n")
        self.assertEqual(self.run_fixture(), 7)
        self.assertEqual(self.summary()["exit_code"], 7)

    def test_signal_exit_code_is_normalized(self):
        self.stub("import os, signal\nos.kill(os.getpid(), signal.SIGTERM)\n")
        self.assertEqual(self.run_fixture(), 143)

    def test_launch_failure_still_writes_summary(self):
        with mock.patch.object(runner.subprocess, "Popen", side_effect=FileNotFoundError("flutter")):
            with self.assertRaises(FileNotFoundError):
                self.run_fixture()
        self.assertEqual(self.summary()["exit_code"], 1)

    def test_real_cleanup_error_cannot_turn_success_green_or_hide_failure(self):
        for status in (0, 7):
            self.stub(f"import sys\nsys.exit({status})\n")
            with self.subTest(status=status), \
                 mock.patch.object(runner, "stop_process_group", side_effect=PermissionError(1, "live fixture")), \
                 contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.run_fixture(), status or 1)
                self.assertEqual(self.summary()["command_exit_code"], status)
                self.assertEqual(self.summary()["cleanup_status"], "failed")

    def test_cancel_during_spawn_retains_child_handle_and_first_signal(self):
        self.stub("import time\ntime.sleep(60)\n")
        real_popen = subprocess.Popen

        def spawn(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            if args[0][0] == "flutter":
                os.kill(os.getpid(), signal.SIGTERM)
                os.kill(os.getpid(), signal.SIGINT)
            return child

        before = signal.getsignal(signal.SIGTERM)
        with mock.patch.object(runner.subprocess, "Popen", side_effect=spawn):
            self.assertEqual(self.run_fixture(), 143)
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)
        self.assertEqual(self.summary()["cleanup_status"], "success")

    def test_cancelled_cleanup_error_preserves_143_and_failure_diagnostic(self):
        self.stub("import sys\nsys.exit(0)\n")

        def cleanup(_proc):
            os.kill(os.getpid(), signal.SIGTERM)
            raise PermissionError(1, "live fixture")

        with mock.patch.object(runner, "stop_process_group", side_effect=cleanup), \
             contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.run_fixture(), 143)
        self.assertEqual(self.summary()["cleanup_status"], "failed")
        self.assertIn("PermissionError", self.summary()["cleanup_error"])

    def test_exited_launcher_cannot_hang_on_inherited_stdout(self):
        pidfile = self.root / "child.pid"
        self.stub(f"import subprocess, sys\nfrom pathlib import Path\nc = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\nPath({str(pidfile)!r}).write_text(str(c.pid))\n")
        start = time.monotonic()
        try:
            self.assertEqual(self.run_fixture(), 0)
            self.assertLess(time.monotonic() - start, 10)
            self.assertEqual(self.summary()["cleanup_status"], "success")
            child = int(pidfile.read_text())
            state = subprocess.run(["ps", "-p", str(child), "-o", "stat="], capture_output=True, text=True).stdout.strip()
            self.assertTrue(not state or state.startswith("Z"), state)
        finally:
            if pidfile.exists():
                try:
                    os.kill(int(pidfile.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_real_term_resistant_group_is_killed_and_cleanup_repeatable(self):
        ready = self.root / "ready"
        source = f"import signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nPath({str(ready)!r}).touch()\ntime.sleep(60)\n"
        proc = subprocess.Popen([sys.executable, "-c", source], start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            runner.stop_process_group(proc, grace=0.1, kill_grace=1)
            runner.stop_process_group(proc, grace=0.1, kill_grace=1)
            self.assertEqual(proc.returncode, -signal.SIGKILL)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()

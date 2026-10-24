#!/usr/bin/env python3
"""One Flutter invocation, bounded concurrent tests, persistent diagnostics.

Flutter owns scheduling and native-asset preparation. Never launch multiple
Flutter commands against the same .dart_tool/build directory.
"""
from __future__ import annotations

import argparse
import codecs
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import native_phase_metrics

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
EXCLUDED = "test/benchmarks/cat_log_benchmark_test.dart"


def discover(example: Path) -> list[str]:
    files = sorted(p.relative_to(example).as_posix()
                   for p in (example / "test").rglob("*_test.dart")
                   if p.is_file() and not p.is_symlink())
    return [f for f in files if f != EXCLUDED and not f.startswith("test/design/")]


def live_group_members(pgid: int) -> list[int]:
    """Inspect only PID/group/state; never log commands or environment secrets.

    killpg(pgid, 0) cannot distinguish live processes from zombies. Use the
    portable macOS/Linux ps columns and fail closed if inspection fails.
    """
    result = subprocess.run(["ps", "-axo", "pid=,pgid=,stat="],
                            capture_output=True, text=True, timeout=2, check=True)
    members = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) != 3 or not fields[0].isdigit() or not fields[1].isdigit():
            raise RuntimeError("Cannot parse process group snapshot")
        pid, group = int(fields[0]), int(fields[1])
        if group == pgid and not fields[2].startswith("Z"):
            members.append(pid)
    return members


def signal_live_group(pgid: int, signum: int) -> None:
    try:
        os.killpg(pgid, signum)
    except (ProcessLookupError, PermissionError):
        # Darwin may reject a group whose last live process just exited.
        # Only a fresh, successful empty snapshot permits this race; a live
        # or uninspectable group is a real cleanup failure, never ignored.
        if live_group_members(pgid):
            raise


def stop_process_group(proc: subprocess.Popen, grace: float = 5.0,
                       kill_grace: float = 2.0) -> None:
    """Idempotent, bounded TERM -> live-group wait -> KILL -> verification."""
    pgid = proc.pid  # start_new_session=True establishes this owned group.
    if pgid <= 1 or pgid == os.getpgrp():
        raise RuntimeError("Refusing to signal an unowned process group")
    for signum, budget in ((signal.SIGTERM, grace), (signal.SIGKILL, kill_grace)):
        if not live_group_members(pgid):
            break
        signal_live_group(pgid, signum)
        deadline = time.monotonic() + budget
        while True:
            proc.poll()  # reap the launcher, but do not mistake it for the group
            if not live_group_members(pgid):
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(0.05, remaining))
    remaining = live_group_members(pgid)
    if remaining:
        raise RuntimeError(f"Live processes remain in group {pgid}: {remaining}")
    proc.wait(timeout=kill_grace)


def run_tests(example: Path, tests: list[str], workers: int, output: Path) -> int:
    if not tests or len(tests) != len(set(tests)) or workers not in (1, 2):
        raise ValueError("Expected a nonempty unique test list and 1 or 2 workers")
    output.mkdir(parents=True, exist_ok=True)
    command = ["flutter", "test", "--no-pub", "--reporter=expanded", f"--concurrency={workers}", *tests]
    (output / "test-files.json").write_text(json.dumps(tests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    started = time.monotonic()
    proc = None
    code = 1
    cancellation = None
    cleanup_error = None
    previous = {}

    def cancel(signum, _frame):
        # Do not raise through Popen: cancellation during process creation
        # must still leave an assigned child handle for cleanup. First wins.
        nonlocal cancellation
        if cancellation is None:
            cancellation = signum

    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, cancel)
        log_path = output / "flutter.log"
        with log_path.open("wb") as log, log_path.open("rb") as reader:
            if cancellation is None:
                proc = subprocess.Popen(command, cwd=example, start_new_session=True,
                                        stdout=log, stderr=subprocess.STDOUT)
                decoder = codecs.getincrementaldecoder("utf-8")("replace")
                # Tail the durable log rather than blocking on an inherited
                # pipe: an exited launcher with a quiet descendant must not hang.
                while True:
                    chunk = reader.read(65536)
                    if chunk:
                        print(decoder.decode(chunk), end="", flush=True)
                    if cancellation is not None:
                        break
                    result = proc.poll()
                    if result is not None:
                        result = proc.wait()  # poll already confirmed exit; cannot block
                        code = result if result >= 0 else 128 - result
                        print(decoder.decode(reader.read(), final=True), end="", flush=True)
                        break
                    if not chunk:
                        time.sleep(0.05)
    finally:
        try:
            if proc is not None:
                stop_process_group(proc)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            cleanup_error = f"{type(error).__name__}: {error}"
            print(f"Example process cleanup failed: {cleanup_error}", file=sys.stderr, flush=True)
        finally:
            if cancellation is not None:
                code = 128 + cancellation
            command_code = code
            if cleanup_error and code == 0:
                code = 1  # cleanup cannot turn a failed command into success
            try:
                summary = {"schema_version": 2, "files": len(tests), "concurrency": workers,
                           "command_exit_code": command_code, "exit_code": code,
                           "cleanup_status": "failed" if cleanup_error else "success",
                           "cleanup_error": cleanup_error,
                           "elapsed_seconds": round(time.monotonic() - started, 3)}
                (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
                print("EXAMPLE_TEST_SUMMARY=" + json.dumps(summary), flush=True)
            finally:
                for signum, handler in previous.items():
                    signal.signal(signum, handler)
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    tests = discover(EXAMPLE)
    if not tests:
        parser.error("No Example widget tests discovered")
    print(f"Example: {len(tests)} files; one Flutter invocation, concurrency={args.workers}", flush=True)
    state = None
    if os.environ.get("IANVS_CI_NATIVE_METRICS") == "1":
        try:
            state = native_phase_metrics.begin("Example widget tests")
        except (OSError, ValueError) as error:
            print(f"Native phase measurement unavailable: {error}", file=sys.stderr)
    code = 1
    try:
        code = run_tests(EXAMPLE, tests, args.workers, ROOT / "build/ci/example")
        return code
    finally:
        if state is not None:
            try:
                native_phase_metrics.finish(state, code)
            except (OSError, ValueError) as error:
                print(f"Native phase measurement incomplete: {error}", file=sys.stderr)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"Example runner failed: {error}", file=sys.stderr)
        sys.exit(1)

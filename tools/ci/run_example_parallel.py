#!/usr/bin/env python3
"""One Flutter invocation, bounded concurrent test processes, persistent diagnostics.

Flutter owns test scheduling and native-asset preparation. Do not launch multiple
Flutter commands in the same workspace: TMPDIR does not isolate .dart_tool/build.
The separate visual gate owns test/design; local full-suite entrypoints are unchanged.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
EXCLUDED = "test/benchmarks/cat_log_benchmark_test.dart"


def discover(example: Path) -> list[str]:
    files = sorted(p.relative_to(example).as_posix()
                   for p in (example / "test").rglob("*_test.dart")
                   if p.is_file() and not p.is_symlink())
    return [f for f in files if f != EXCLUDED and not f.startswith("test/design/")]


class Cancelled(Exception):
    def __init__(self, signum: int):
        self.signum = signum


def run_tests(example: Path, tests: list[str], workers: int, output: Path) -> int:
    if not tests or len(tests) != len(set(tests)) or workers not in (1, 2):
        raise ValueError("Expected a nonempty unique test list and 1 or 2 workers")
    output.mkdir(parents=True, exist_ok=True)
    command = ["flutter", "test", "--no-pub", "--reporter=expanded", f"--concurrency={workers}", *tests]
    # No test retries and no fail-fast: collect all failures in this one invocation.
    (output / "test-files.json").write_text(json.dumps(tests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    started = time.monotonic()
    proc = None
    code = 1
    previous = {}

    def cancel(signum, _frame):
        raise Cancelled(signum)

    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, cancel)
        with (output / "flutter.log").open("w", encoding="utf-8") as log:
            proc = subprocess.Popen(command, cwd=example, start_new_session=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, encoding="utf-8", errors="replace")
            assert proc.stdout is not None
            for line in proc.stdout:
                log.write(line)
                log.flush()
                print(line, end="", flush=True)
            code = proc.wait()
            if code < 0:
                code = 128 - code
    except Cancelled as error:
        code = 128 + error.signum
    finally:
        # Kill the process group as well as the launcher on cancellation/error.
        for signum in previous:
            signal.signal(signum, signal.SIG_IGN)
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                # Also reap orphaned Flutter/Cargo/test descendants if the launcher exited.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
            except ProcessLookupError:
                proc.wait()
            if proc.stdout is not None:
                proc.stdout.close()
        for signum, handler in previous.items():
            signal.signal(signum, handler)
        summary = {"schema_version": 1, "files": len(tests), "concurrency": workers,
                   "exit_code": code, "elapsed_seconds": round(time.monotonic() - started, 3)}
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print("EXAMPLE_TEST_SUMMARY=" + json.dumps(summary), flush=True)
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    tests = discover(EXAMPLE)
    if not tests:
        parser.error("No Example widget tests discovered")
    print(f"Example: {len(tests)} files; one Flutter invocation, concurrency={args.workers}", flush=True)
    return run_tests(EXAMPLE, tests, args.workers, ROOT / "build/ci/example")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"Example runner failed: {error}", file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Run one command in a bounded process group and clean up every group member."""

import os
import signal
import subprocess
import sys
import time


def main() -> int:
    if len(sys.argv) < 5:
        print(
            "usage: run_process_group_with_timeout.py "
            "TIMEOUT_SECONDS STDOUT_LOG STDERR_LOG COMMAND [ARG ...]",
            file=sys.stderr,
        )
        return 2

    timeout_seconds = int(sys.argv[1])
    stdout_path = sys.argv[2]
    stderr_path = sys.argv[3]
    command = sys.argv[4:]
    process = None
    process_group_id = None

    def process_group_exists() -> bool:
        if process_group_id is None:
            return False
        try:
            os.killpg(process_group_id, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def terminate_process_group() -> None:
        if not process_group_exists():
            return
        try:
            os.killpg(process_group_id, signal.SIGTERM)
        except ProcessLookupError:
            return

        deadline = time.monotonic() + 5
        while process_group_exists() and time.monotonic() < deadline:
            if process is not None:
                process.poll()
            time.sleep(0.05)

        if process_group_exists():
            try:
                os.killpg(process_group_id, signal.SIGKILL)
            except ProcessLookupError:
                pass

        if process is not None and process.poll() is None:
            process.wait()

    def handle_signal(signum: int, _frame: object) -> None:
        terminate_process_group()
        raise SystemExit(128 + signum)

    for handled_signal in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(handled_signal, handle_signal)

    with open(stdout_path, "wb") as stdout_log, open(
        stderr_path, "wb"
    ) as stderr_log:
        process = subprocess.Popen(
            command,
            stdout=stdout_log,
            stderr=stderr_log,
            start_new_session=True,
        )
        process_group_id = process.pid
        try:
            exit_code = process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            terminate_process_group()
            print(
                f"process group timed out after {timeout_seconds}s",
                file=sys.stderr,
            )
            return 124

    terminate_process_group()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())

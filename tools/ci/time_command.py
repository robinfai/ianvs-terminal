#!/usr/bin/env python3
"""Time CI phases without changing exit status, stdout, or test coverage."""
import argparse
import datetime
import json
import os
import subprocess
import sys
import time

import native_phase_metrics


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("phase")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        parser.error("missing command")
    state = None
    if os.environ.get("IANVS_CI_NATIVE_METRICS") == "1":
        try:
            state = native_phase_metrics.begin(args.phase)
        except (OSError, ValueError) as exc:
            print(f"Native phase measurement unavailable: {exc}", file=sys.stderr)
    start = time.monotonic()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        result = subprocess.run(cmd, check=False).returncode
    except FileNotFoundError:
        result = 127
    except OSError as exc:
        print(f"Cannot execute {cmd[0]}: {exc}", file=sys.stderr, flush=True)
        result = 126
    elapsed = round(time.monotonic() - start, 3)
    record = {"phase": args.phase, "started_utc": started,
              "seconds": elapsed, "exit_code": result}
    print("CI_TIMING=" + json.dumps(record, ensure_ascii=False), flush=True)
    if state is not None:
        try:
            native_phase_metrics.finish(state, result if result >= 0 else 128 - result)
        except (OSError, ValueError) as exc:
            print(f"Native phase measurement incomplete: {exc}", file=sys.stderr)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as out:
            out.write(f"| {args.phase.replace('|', '/')} | {elapsed:.1f} | {result} |\n")
    return result if result >= 0 else 128 - result


if __name__ == "__main__":
    sys.exit(main())

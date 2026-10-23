#!/usr/bin/env python3
"""Time CI phases without changing exit status, stdout, or test coverage."""
import argparse
import datetime
import json
import os
import subprocess
import sys
import time

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("phase")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        parser.error("missing command")
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
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as out:
            out.write(f"| {args.phase.replace('|', '/')} | {elapsed:.1f} | {result} |\n")
    return result if result >= 0 else 128 - result

if __name__ == "__main__":
    sys.exit(main())

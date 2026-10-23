#!/usr/bin/env python3
"""Run the canonical Example suite on one macOS runner with bounded concurrency.

Each file runs exactly once; keep native setup outside this driver. Independent
Flutter processes report failures without cancelling the other shard.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
EXCLUDED = "test/benchmarks/cat_log_benchmark_test.dart"

def discover():
    files = sorted(p.relative_to(EXAMPLE).as_posix() for p in (EXAMPLE / "test").rglob("*_test.dart"))
    return [f for f in files if f != EXCLUDED and not f.startswith("test/design/")]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    tests = discover()
    if not tests:
        parser.error("No Example widget tests discovered")
    buckets = [tests[i::args.workers] for i in range(args.workers)]
    if sorted(x for bucket in buckets for x in bucket) != tests:
        parser.error("Incomplete or overlapping Example partition")
    print(f"Example: {len(tests)} files in {args.workers} workers: "
          + ", ".join(str(len(x)) for x in buckets), flush=True)
    processes = []
    with tempfile.TemporaryDirectory(prefix="ianvs-example-") as tmp:
        for i, bucket in enumerate(buckets):
            log_path = Path(tmp) / f"worker-{i}.log"
            log = log_path.open("w")
            # Separate Dart/Flutter temp state; keep Cargo shared under its lock.
            env = dict(os.environ, TMPDIR=str(Path(tmp) / f"tmp-{i}"))
            Path(env["TMPDIR"]).mkdir()
            command = ["flutter", "test", "--concurrency=2", *bucket]
            try:
                process = subprocess.Popen(command, cwd=EXAMPLE, env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
            except BaseException:
                log.close()
                for prev, _, _ in processes:
                    prev.terminate()
                for prev, _, _ in processes:
                    prev.wait()
                raise
            processes.append((process, log, log_path))
        failures = []
        for i, (proc, log, log_path) in enumerate(processes):
            code = proc.wait()
            log.close()
            print(f"Example worker {i}: exit={code}", flush=True)
            print(log_path.read_text(errors="replace")[-12000:], flush=True)
            if code:
                failures.append(i)
    if failures:
        print(f"Example workers failed: {failures}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())

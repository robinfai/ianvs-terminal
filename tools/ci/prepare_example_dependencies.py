#!/usr/bin/env python3
"""Prepare locked Cargo dependencies; retry downloads, never builds or tests."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = ("native/core/Cargo.toml", "packages/ianvs_terminal_core/native/core/Cargo.toml")
# Retry only network failures. Lockfile, manifest and checksum errors fail closed.
TRANSIENT = re.compile(
    r"could(?:n't| not) resolve (?:host|proxy)|temporary failure in name resolution|"
    r"connection (?:reset|timed out|refused)|operation timed out|timeout was reached|"
    r"failed to connect|(?:http|response|status)[^\n]*(?:429|500|502|503|504)\b",
    re.IGNORECASE,
)
PERMANENT = re.compile(r"checksum|certificate|lock file.*(?:needs|changed|update)|failed to parse", re.I)


def fetch(manifest: Path, target: str, *, attempts: int = 3) -> int:
    command = ["cargo", "fetch", "--locked", "--manifest-path", str(manifest), "--target", target]
    # A successful restore is not proof of completeness. Validate it without DNS.
    env = dict(os.environ, CARGO_NET_RETRY="1", CARGO_HTTP_TIMEOUT="30", CARGO_TERM_COLOR="never")
    env.pop("CARGO_NET_OFFLINE", None)
    for attempt in range(attempts + 1):
        offline = attempt == 0
        argv = command + ["--offline"] if offline else command
        print(f"Cargo dependency check: {manifest} ({'offline' if offline else f'fetch {attempt}/{attempts}'})", flush=True)
        try:
            result = subprocess.run(argv, cwd=manifest.parent, env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=120)
            output, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired:
            output, code = "Dependency fetch exceeded the 120-second limit.\n", 124
        print(output, end="" if output.endswith("\n") else "\n", flush=True)
        if code == 0:
            return 0
        if offline:
            continue
        if PERMANENT.search(output) or (code != 124 and not TRANSIENT.search(output)):
            return code
        if attempt < attempts:
            delay = 5 * attempt
            print(f"Transient dependency download failure; retrying in {delay}s.", flush=True)
            time.sleep(delay)
    return code


def main() -> int:
    # Explicit host triples work with the pinned Rust 1.88; do not use newer aliases.
    info = subprocess.check_output(["rustc", "-vV"], text=True, timeout=15)
    target = next((line[6:].strip() for line in info.splitlines() if line.startswith("host: ")), "")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", target):
        raise ValueError("Cannot determine the Rust host target")
    for relative in MANIFESTS:
        manifest = ROOT / relative
        if not manifest.is_file() or not manifest.with_name("Cargo.lock").is_file():
            raise ValueError(f"Missing manifest or committed lockfile: {relative}")
        status = fetch(manifest, target)
        if status:
            return status
    print("Cargo dependency preparation passed. Subsequent Example builds use offline mode.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Dependency preparation failed: {error}", file=sys.stderr)
        sys.exit(1)

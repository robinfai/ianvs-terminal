#!/usr/bin/env python3
"""Conservatively select Apple checks from the actual PR merge diff.

No API token, third-party action or truncated REST file listing is needed.
Unknown events, checkout shapes and paths always receive full verification.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from typing import Mapping

ROOT = Path(__file__).resolve().parents[2]
DOC_FILES = {"README.md", "README.zh-CN.md", "LICENSE", "LICENSE.md", "CONTRIBUTING.md"}


def classify(paths: list[str], platform: str) -> str:
    """Return skip, debug or full; only known low-risk paths are optimized."""
    if platform not in {"macos", "ios"}:
        raise ValueError("unsupported Apple platform")
    if not paths:
        return "full"
    mode = "skip"
    other = "ios" if platform == "macos" else "macos"
    for path in paths:
        if path in DOC_FILES or path.startswith("docs/"):
            continue
        if path.startswith(f"example/{other}/"):
            continue
        if path.startswith(f"example/{platform}/"):
            return "full"
        if (
            (path.startswith("example/lib/") and path.endswith(".dart"))
            or path.startswith(("example/test/", "example/integration_test/",
                                "example/test_driver/", "example/test_http/", "backend/"))
        ):
            mode = "debug"
            continue
        # Includes native/**, packages/**, dependencies, assets, build tools,
        # workflow changes, root configuration and every unrecognized path.
        return "full"
    return mode


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(
        ["git", *args], cwd=repo, stderr=subprocess.PIPE, timeout=30
    )


def changed_paths(repo: Path, event: dict) -> list[str]:
    """Validate both parents before comparing the tested merge to its base.

    --no-renames retains both paths for moves (including native -> docs), and
    NUL delimiters handle whitespace/newlines without shell interpolation.
    checkout fetch-depth: 2 supplies the merge tree and both parent trees.
    """
    pr = event["pull_request"]
    base, head = pr["base"]["sha"], pr["head"]["sha"]
    if not all(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha)
               for sha in (base, head)):
        raise ValueError("invalid PR revisions")
    parents = git(repo, "rev-parse", "HEAD^1", "HEAD^2").decode("ascii").splitlines()
    if parents != [base, head]:
        raise ValueError("checkout does not match the PR merge parents")
    data = git(repo, "diff", "--no-renames", "--name-only", "-z", "HEAD^1", "HEAD", "--")
    return [path.decode("utf-8", errors="surrogateescape") for path in data.split(b"\0") if path]


def choose(platform: str, env: Mapping[str, str], repo: Path = ROOT) -> tuple[str, str]:
    if env.get("GITHUB_EVENT_NAME") != "pull_request":
        return "full", "Non-PR invocation: full verification."
    try:
        event = json.loads(Path(env["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        paths = changed_paths(repo, event)
        return classify(paths, platform), f"Classified {len(paths)} changed paths in the tested merge."
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        # Missing history or malformed context must increase, not reduce, coverage.
        return "full", "PR diff unavailable or untrusted: full verification."


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("macos", "ios"))
    args = parser.parse_args()
    mode, reason = choose(args.platform, os.environ)
    print(f"Apple verification ({args.platform}): {mode}. {reason}")
    output = f"run={'false' if mode == 'skip' else 'true'}\nfull={'1' if mode == 'full' else '0'}\n"
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(output)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(f"### Apple verification: {args.platform}\n\nMode: **{mode}**. {reason}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Attribute existing Hook measurements to phases; never build, replay or clean.

Only changed measurements started inside a phase count. Nested phase records
own their observations so parent/child summaries cannot double-count them.
Unattributed wall time is NOT asserted to be test execution time.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
METRIC_NAME = "ianvs-cargo-build.json"


def discover(root: Path) -> list[Path]:
    found = set()
    projects = [root, root / "example", *sorted((root / "packages").glob("*"))]
    for project in projects:
        if project.is_symlink():
            continue
        for name in ("hooks_runner", "native_assets_builder"):
            directory = project / ".dart_tool" / name
            if directory.is_symlink() or not directory.is_dir():
                continue
            for current, children, files in os.walk(directory, followlinks=False):
                children[:] = [name for name in children if name != "cargo-target"
                               and not (Path(current) / name).is_symlink()]
                path = Path(current) / METRIC_NAME
                if METRIC_NAME in files and not path.is_symlink():
                    found.add(path)
    return sorted(found)


def snapshot(root: Path) -> tuple[dict, list[str]]:
    records, errors = {}, []
    for path in discover(root):
        relative = str(path.relative_to(root))
        try:
            if path.stat().st_size > 65536:
                raise ValueError("measurement exceeds 64 KiB")
            raw = path.read_bytes()
            records[relative] = {"digest": hashlib.sha256(raw).hexdigest(),
                                 "metric": json.loads(raw)}
        except (OSError, ValueError) as error:
            errors.append(f"{relative}: {type(error).__name__}")
    return records, errors


def timestamp(value: str) -> float:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("measurement has no timezone")
    return parsed.timestamp()


def union_seconds(intervals: list[tuple[float, float]]) -> float:
    total, end = 0.0, float("-inf")
    for left, right in sorted(intervals):
        total += max(0.0, right - max(left, end))
        end = max(end, right)
    return total


def compiler_cache_snapshot() -> dict | None:
    if os.environ.get("IANVS_CI_NATIVE_COMPILER_CACHE") != "1":
        return None
    try:
        from native_hook_cache import cache_snapshot
        return cache_snapshot()
    except ImportError:
        # Standalone diagnostic fixtures may intentionally copy only this file.
        return {"available": False, "error_type": "ImportError"}


def begin(phase: str, root: Path = ROOT, output: Path | None = None) -> Path:
    root = root.resolve()
    output = output or root / "build/ci/native-phases"
    output.mkdir(parents=True, exist_ok=True)
    before, errors = snapshot(root)
    cache_before = compiler_cache_snapshot()
    identifier = uuid.uuid4().hex
    state = {"schema_version": 1, "id": identifier, "phase": phase,
             "root": str(root), "started_utc": datetime.now(timezone.utc).isoformat(),
             "monotonic_start": time.monotonic(),
             "before": {name: item["digest"] for name, item in before.items()},
             "prior_records": [p.name for p in output.glob("*.json")],
             "collection_errors": errors, "compiler_cache_before": cache_before}
    path = output / f"{identifier}.start.json"
    path.write_text(json.dumps(state, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def finish(state_path: Path, exit_code: int) -> dict:
    # Stop the measured clock before diagnostics collection adds its own cost.
    finished_at, monotonic_end = datetime.now(timezone.utc), time.monotonic()
    state = json.loads(state_path.read_text(encoding="utf-8"))
    root = Path(state["root"])
    elapsed = max(0.0, monotonic_end - state["monotonic_start"])
    start, end = timestamp(state["started_utc"]), finished_at.timestamp()
    records, errors = snapshot(root)
    errors = state["collection_errors"] + errors
    claimed, children = set(), []
    for path in sorted(state_path.parent.glob("*.json")):
        if path.name.endswith(".start.json") or path.name in state["prior_records"]:
            continue
        child = json.loads(path.read_text(encoding="utf-8"))
        if child.get("schema_version") == 1 and child.get("id") != state["id"]:
            claimed.update(child.get("claimed_hook_ids", []))
            children.append(child["id"])
    hooks, stale, outside, intervals = [], 0, 0, []
    for name, item in records.items():
        if state["before"].get(name) == item["digest"]:
            stale += 1
            continue
        identity = hashlib.sha256((name + ":" + item["digest"]).encode()).hexdigest()
        if identity in claimed:
            continue
        try:
            metric = item["metric"]
            if metric.get("schema_version") != 1:
                raise ValueError("unsupported schema")
            ms = metric["elapsed_ms"]
            if isinstance(ms, bool) or not isinstance(ms, int) or ms < 0:
                raise ValueError("invalid duration")
            hook_start = timestamp(metric["started_at"])
            hook_end = hook_start + ms / 1000
            if not math.isfinite(hook_end) or hook_start < start or hook_end > end:
                outside += 1
                continue
            manifest = Path(metric["manifest_path"]).resolve()
            sources = {(root / "native/core/Cargo.toml").resolve(): "canonical",
                       (root / "packages/ianvs_terminal_core/native/core/Cargo.toml").resolve(): "packaged"}
            if manifest not in sources:
                raise ValueError("unexpected source manifest")
            code = metric["exit_code"]
            if isinstance(code, bool) or not isinstance(code, int):
                raise ValueError("invalid exit code")
            # Explicit fields only: do not copy arbitrary environment or argv.
            hook = {"id": identity, "metric_path": name, "source": sources[manifest],
                    "started_at": metric["started_at"], "elapsed_ms": ms,
                    "exit_code": code, "manifest_path": str(manifest),
                    "cache_status": "unknown"}
            for key in ("target", "profile", "target_directory"):
                value = metric[key]
                if not isinstance(value, str) or len(value) > 4096:
                    raise ValueError("invalid build configuration")
                hook[key] = value
            env = metric.get("build_environment", {})
            hook["build_environment"] = {
                key: env[key] for key in ("CARGO_BUILD_JOBS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET")
                if isinstance(env.get(key), str) and len(env[key]) <= 4096}
            hooks.append(hook)
            intervals.append((hook_start, hook_end))
            claimed.add(identity)
        except (KeyError, TypeError, ValueError, AttributeError):
            errors.append(f"{name}: invalid measurement")
    work = sum(hook["elapsed_ms"] for hook in hooks) / 1000
    wall = union_seconds(intervals)
    record = {"schema_version": 1, "id": state["id"], "phase": state["phase"],
              "started_utc": state["started_utc"], "finished_utc": finished_at.isoformat(),
              "elapsed_seconds": round(elapsed, 3), "exit_code": exit_code,
              "hook_build_count": len(hooks), "hook_work_seconds": round(work, 3),
              "hook_wall_seconds": round(wall, 3),
              "unattributed_seconds": None if children else round(max(0, elapsed - wall), 3),
              "unchanged_metrics": stale, "out_of_window_metrics": outside,
              "removed_metrics": sorted(set(state["before"]) - set(records)),
              "nested_phase_ids": children, "claimed_hook_ids": sorted(claimed),
              "hooks": hooks, "collection_errors": errors,
              "note": "No metric is not proof of no build; unmeasured time includes preparation and tests. Cache hits are not inferred."}
    if os.environ.get("IANVS_CI_NATIVE_COMPILER_CACHE") == "1":
        record["compiler_cache"] = {
            "before": state.get("compiler_cache_before"),
            "after": compiler_cache_snapshot(),
            "note": "Process-wide counter snapshots; nested phases overlap. Do not sum parent and child deltas or infer per-Hook hits.",
        }
    destination = state_path.with_name(f"{state['id']}.json")
    destination.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("CI_NATIVE_PHASE=" + json.dumps(record, ensure_ascii=False), flush=True)
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    start = commands.add_parser("begin")
    start.add_argument("phase")
    stop = commands.add_parser("finish")
    stop.add_argument("state", type=Path)
    stop.add_argument("exit_code", type=int)
    args = parser.parse_args()
    if args.command == "begin":
        print(begin(args.phase))
    else:
        if not re.fullmatch(r"[0-9a-f]{32}\.start\.json", args.state.name):
            parser.error("invalid phase state file")
        finish(args.state, args.exit_code)
    return 0


if __name__ == "__main__":
    sys.exit(main())

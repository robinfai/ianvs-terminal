#!/usr/bin/env python3
"""Measure hook Cargo time, then optionally replay a dependency-only warm build.

This is an on-runner experiment, NOT proof of a cross-run Actions cache hit.
It never changes sources, test selection, Cargo flags or compilation parallelism.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

METRIC_NAME = "ianvs-cargo-build.json"
TARGETS = {"aarch64-apple-darwin", "x86_64-apple-darwin"}
BASE_ENV = {
    "PATH", "HOME", "USERPROFILE", "SYSTEMDRIVE", "SYSTEMROOT", "WINDIR",
    "PROGRAMDATA", "TEMP", "TMP", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY",
    "NO_PROXY", "LIBCLANG_PATH", "ANDROID_HOME", "ANDROID_NDK",
    "ANDROID_NDK_HOME", "ANDROID_NDK_LATEST_HOME", "ANDROID_NDK_ROOT",
}
BUILD_ENV = {
    "CARGO_BUILD_JOBS", "CARGO_TARGET_DIR", "CARGO_HOME", "RUSTUP_HOME",
    "MACOSX_DEPLOYMENT_TARGET", "SDKROOT", "HOST_CC", "HOST_AR",
}


def inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def discover(root: Path) -> list[Path]:
    """Do not traverse Cargo target trees or the entire checkout."""
    projects = [root, root / "example"]
    projects.extend((root / "packages").glob("*"))
    found: set[Path] = set()
    for project in projects:
        for runner in ("hooks_runner", "native_assets_builder"):
            directory = project / ".dart_tool" / runner
            if not directory.is_dir():
                continue
            for current, children, files in os.walk(directory, followlinks=False):
                children[:] = [
                    name for name in children
                    if name != "cargo-target"
                    and not (Path(current) / name).is_symlink()
                ]
                if METRIC_NAME in files:
                    found.add((Path(current) / METRIC_NAME).resolve())
    return sorted(found)


def load_metric(path: Path, root: Path) -> dict:
    metric = json.loads(path.read_text())
    if metric.get("schema_version") != 1 or metric.get("exit_code") != 0:
        raise ValueError(f"Not a successful v1 Cargo measurement: {path}")
    target = metric.get("target")
    if target not in TARGETS or metric.get("profile") != "release":
        raise ValueError("Unsupported target/profile in Cargo measurement")
    # Example uses ianvs_pty -> native/core. The standalone published hook
    # mirrors it but builds its own packaged sources. Replay the measured
    # manifest, never silently substitute the other source tree.
    manifests = {
        (root / "native/core/Cargo.toml").resolve(),
        (root / "packages/ianvs_terminal_core/native/core/Cargo.toml").resolve(),
    }
    manifest = Path(metric["manifest_path"]).resolve()
    if manifest not in manifests or not inside(manifest, root):
        raise ValueError("Probe may only build the canonical or packaged terminal core")
    if Path(metric["working_directory"]).resolve() != manifest.parent:
        raise ValueError("Unexpected Cargo working directory")
    target_dir = Path(metric["target_directory"])
    if (
        target_dir.is_symlink()
        or target_dir.resolve() != (path.parent / "cargo-target").resolve()
        or not inside(target_dir, root)
        or ".dart_tool" not in target_dir.relative_to(root).parts
    ):
        raise ValueError("Refusing to clean outside the hook's private cargo-target")
    expected_args = [
        "build", "--locked", "--release", "--manifest-path",
        metric["manifest_path"], "--target", target,
    ]
    if metric.get("arguments") != expected_args:
        raise ValueError("Probe requires the original locked release build arguments")
    elapsed = metric.get("elapsed_ms")
    if isinstance(elapsed, bool) or not isinstance(elapsed, int) or elapsed < 0:
        raise ValueError("Invalid Cargo duration")
    env = metric.get("build_environment", {})
    cargo_key = target.upper().replace("-", "_")
    cc_key = target.replace("-", "_")
    allowed = BUILD_ENV | {
        f"CARGO_TARGET_{cargo_key}_LINKER", f"CC_{cc_key}", f"AR_{cc_key}",
    }
    if set(env) - allowed or any(not isinstance(value, str) for value in env.values()):
        raise ValueError("Unexpected build environment keys or values")
    if env.get("CARGO_BUILD_JOBS") != "2":
        raise ValueError("Probe must preserve the two-job native build limit")
    if Path(env.get("CARGO_TARGET_DIR", "")).resolve() != target_dir.resolve():
        raise ValueError("Cargo target environment does not match the measured path")
    return metric


def replay_environment(metric: dict, parent: dict[str, str]) -> dict[str, str]:
    # Match hooks' semi-hermetic environment. Do not accidentally introduce the
    # CI shell's RUSTFLAGS, CARGO_PROFILE_* or credentials into a replay.
    env = {
        key: value for key, value in parent.items()
        if key in BASE_ENV or key.startswith(("NIX_", "CCACHE_"))
    }
    env.update(metric["build_environment"])
    return env


def local_packages(metadata: dict, root: Path) -> list[str]:
    packages = []
    for package in metadata["packages"]:
        if package.get("source") is None:
            if not inside(Path(package["manifest_path"]), root):
                raise ValueError("Refusing to clean a local crate outside the checkout")
            packages.append(package["id"])
    if not packages:
        raise ValueError("No local Cargo packages were found; warm probe is invalid")
    return sorted(set(packages))


def run_cargo(arguments: list[str], metric: dict, env: dict[str, str],
              *, quiet: bool = False) -> tuple[subprocess.CompletedProcess, int]:
    started = time.monotonic_ns()
    result = subprocess.run(
        ["cargo", *arguments], cwd=metric["working_directory"], env=env,
        text=True, capture_output=True, timeout=900, check=False,
    )
    elapsed_ms = (time.monotonic_ns() - started) // 1_000_000
    if not quiet or result.returncode:
        if result.stdout:
            print(result.stdout, end="", flush=True)
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, result.args)
    return result, elapsed_ms


def probe(metric: dict, root: Path, parent: dict[str, str]) -> dict:
    """Full warm, then remove ONLY local crates and rebuild with dependencies."""
    env = replay_environment(metric, parent)
    _, full_warm_ms = run_cargo(metric["arguments"], metric, env)
    metadata, _ = run_cargo([
        "metadata", "--format-version", "1", "--locked", "--filter-platform",
        metric["target"], "--manifest-path", metric["manifest_path"],
    ], metric, env, quiet=True)
    packages = local_packages(json.loads(metadata.stdout), root)
    clean_args = [
        "clean", "--release", "--target", metric["target"],
        "--manifest-path", metric["manifest_path"],
    ]
    for package in packages:
        clean_args.extend(["--package", package])
    run_cargo(clean_args, metric, env)
    _, dependencies_warm_ms = run_cargo(metric["arguments"], metric, env)
    library = Path(metric["target_directory"]) / metric["target"] / "release/libianvs_core.dylib"
    if not library.is_file():
        raise ValueError("Dependency-warm rebuild did not produce the native library")
    return {
        "full_warm_ms": full_warm_ms,
        "dependencies_warm_ms": dependencies_warm_ms,
        "cleaned_local_packages": packages,
        "interpretation": (
            "Same runner/configuration; all local path crates cleaned before "
            "the dependency-warm rebuild. This is not an Actions cache restore "
            "measurement, and not a test-suite or end-to-end CI speedup."
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--replay", action="store_true")
    options = parser.parse_args(argv)
    root = options.root.resolve()
    paths = discover(root)
    if not paths:
        raise ValueError("No native hook measurements found; do not infer a zero build cost")
    metrics = [load_metric(path, root) for path in paths]
    selected = max(metrics, key=lambda item: item["started_at"])
    report = {
        "schema_version": 1,
        "commit": os.environ.get("GITHUB_SHA"),
        "shard": os.environ.get("VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD", "all"),
        "initial_builds": [
            {key: metric[key] for key in (
                "started_at", "elapsed_ms", "target", "profile", "target_directory",
                "manifest_path",
            )} for metric in metrics
        ],
        "selected_manifest_path": selected["manifest_path"],
        "manifest_sha256": hashlib.sha256(Path(selected["manifest_path"]).read_bytes()).hexdigest(),
        "lock_sha256": hashlib.sha256(
            Path(selected["working_directory"], "Cargo.lock").read_bytes()
        ).hexdigest(),
    }
    for metric in metrics:
        print(f"Native hook initial Cargo build: {metric['elapsed_ms']} ms "
              f"({metric['target']}, release); manifest={metric['manifest_path']}; "
              f"{metric['target_directory']}", flush=True)
    print("CI phase: Native cache probe (separate from Example test duration)", flush=True)
    try:
        if options.replay:
            report["replay"] = probe(selected, root, dict(os.environ))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["probe_error"] = str(error)
        raise
    finally:
        destination = root / ".dart_tool/ci/native-hook-probe.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, indent=2) + "\n")
        print("NATIVE_HOOK_PROBE=" + json.dumps(report, separators=(",", ":")), flush=True)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as output:
                output.write("\n## Native hook build experiment\n\n```json\n")
                output.write(json.dumps(report, indent=2))
                output.write("\n```\n\nProbe time is not included in the Example test phase.\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Native hook probe failed: {error}", file=sys.stderr)
        sys.exit(1)

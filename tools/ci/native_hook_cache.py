#!/usr/bin/env python3
"""Opt-in compiler caching for registry rlibs in macOS Native Hooks only.

Cargo, build scripts, path dependencies, final libraries and tests still run.
This module never moves Cargo outputs or restores Flutter Hook state.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ACTION_SHA = "fc920bf0ec8de6ee65d409111f7ec508035751ba"
SCCACHE_VERSION = "v0.16.0"
FLAG = "IANVS_CI_NATIVE_COMPILER_CACHE"
EPOCH = "IANVS_CI_NATIVE_CACHE_EPOCH"
CONTEXT = "CARGO_IANVS_NATIVE_CACHE_CONTEXT"
HOOK_PATH = re.compile(
    r"(?:(?:example|packages/[^/]+)/)?\.dart_tool/hooks_runner/shared/"
    r"(?P<package>ianvs_pty|ianvs_terminal_core)/build/"
    r"(?P<configuration>[0-9a-f]+)/cargo-target"
)
COUNTERS = (
    "compile_requests", "requests_executed", "cache_hits", "cache_misses",
    "cache_errors", "cache_read_errors", "cache_write_errors",
    "non_cacheable_compilations", "non_cacheable_calls", "compilation_failures",
)


def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def hook_scope(environment: dict[str, str], root: Path) -> dict[str, str] | None:
    """Unrecognized or incomplete configurations always use the real compiler."""
    if (environment.get(FLAG) != "1"
            or environment.get("GITHUB_ACTIONS") != "true"
            or environment.get("GITHUB_JOB") != "flutter-checks"
            or not re.fullmatch(r"[0-9a-f]{64}", environment.get(EPOCH, ""))):
        return None
    if not all(environment.get(key) for key in (
        "CARGO_TARGET_DIR", "CARGO_MANIFEST_DIR", "CARGO_HOME",
        "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "SCCACHE_PATH",
    )):
        return None
    try:
        target = Path(environment["CARGO_TARGET_DIR"])
        manifest = Path(environment["CARGO_MANIFEST_DIR"])
        cargo_home = Path(environment["CARGO_HOME"])
        if not all(p.is_absolute() for p in (target, manifest, cargo_home)):
            return None
        relative = target.resolve().relative_to(root.resolve()).as_posix()
        match = HOOK_PATH.fullmatch(relative)
        registry = (cargo_home / "registry/src").resolve()
        # Path/vendored/git crates are deliberately excluded from this pilot.
        dependency = manifest.resolve().relative_to(registry)
        if not match or len(dependency.parts) != 2 or not manifest.is_dir():
            return None
        return match.groupdict()
    except (ValueError, OSError, RuntimeError):
        return None


def crate_types(arguments: list[str]) -> set[str]:
    result: set[str] = set()
    for index, argument in enumerate(arguments):
        if argument.startswith("@"):
            return set()  # Do not reinterpret rustc response files.
        if argument == "--crate-type":
            if index + 1 == len(arguments):
                return set()
            result.update(arguments[index + 1].split(","))
        elif argument.startswith("--crate-type="):
            result.update(argument.split("=", 1)[1].split(","))
    return result


def compiler_command(arguments: list[str], environment: dict[str, str],
                     root: Path = ROOT) -> tuple[list[str], dict[str, str]]:
    if not arguments:
        raise ValueError("missing rustc executable")
    env = dict(environment)
    scope = hook_scope(env, root)
    kinds = crate_types(arguments[1:])
    if (scope is None or not kinds or not kinds <= {"lib", "rlib"}
            or Path(arguments[0]).name not in {"rustc", "rustc.exe"}):
        return arguments, env
    build_environment = {
        key: value for key, value in env.items()
        if key.startswith(("CC", "CFLAGS", "CXX", "AR_", "HOST_"))
        or key in {"SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET"}
    }
    # sccache v0.16 hashes CARGO_* variables for Rust. The C-only custom
    # cache-buster is NOT sufficient here. Keep source/config/SDK boundaries.
    env[CONTEXT] = digest({"epoch": env[EPOCH], "scope": scope,
                           "build_environment": build_environment})
    return [env["SCCACHE_PATH"], *arguments], env


def command_output(arguments: list[str]) -> str:
    return subprocess.run(arguments, check=True, capture_output=True, text=True,
                          timeout=30).stdout.strip()


def configure(root: Path = ROOT) -> dict[str, str]:
    if (os.environ.get("GITHUB_ACTIONS") != "true"
            or os.environ.get("GITHUB_JOB") != "flutter-checks"
            or platform.system() != "Darwin"):
        raise RuntimeError("this pilot is restricted to the macOS flutter-checks job")
    if os.environ.get("RUSTC_WRAPPER") or os.environ.get("RUSTC_WORKSPACE_WRAPPER"):
        raise RuntimeError("refusing to replace an existing compiler wrapper")
    sccache = Path(os.environ["SCCACHE_PATH"])
    version = command_output([str(sccache), "--version"])
    if version != f"sccache {SCCACHE_VERSION.removeprefix('v')}":
        raise RuntimeError("unexpected sccache version")
    tools = {
        "rustc": command_output(["rustc", "-vV"]),
        "cargo": command_output(["cargo", "-V"]),
        "flutter": command_output(["flutter", "--version", "--machine"]),
        "xcode": command_output(["xcodebuild", "-version"]),
        "sdk_path": command_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"]),
        "sdk_version": command_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
        "clang": command_output(["xcrun", "--sdk", "macosx", "clang", "--version"]),
        "sccache": version, "architecture": platform.machine(),
    }
    if any(not value for value in tools.values()):
        raise RuntimeError("incomplete compiler/toolchain identity")
    # An explicit epoch prevents reuse across untracked Hook implementation changes.
    files = ["pubspec.lock", "tools/ci/native_hook_cache.py"]
    for package in ("ianvs_pty", "ianvs_terminal_core"):
        files += [f"packages/{package}/hook/build.dart",
                  f"packages/{package}/hook/native_dependencies.dart"]
    epoch = digest({"schema": 1, "tools": tools, "files": {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files
    }})
    wrapper = Path(os.environ["RUNNER_TEMP"]) / "ianvs-native-hook-rustc"
    module = root / "tools/ci/native_hook_cache.py"
    # Avoid Python startup overhead for the unchanged native/clean ABI builds.
    wrapper.write_text(
        '#!/bin/sh\ncase "${CARGO_TARGET_DIR-}" in\n'
        '  */.dart_tool/hooks_runner/shared/*/build/*/cargo-target|'
        '*/.dart_tool/hooks_runner/shared/*/build/*/cargo-target/)\n'
        '    exec ' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(module)) +
        ' rustc "$@" ;;\n  *) exec "$@" ;;\nesac\n', encoding="utf-8")
    wrapper.chmod(0o700)
    exports = {
        FLAG: "1", EPOCH: epoch, "RUSTC_WRAPPER": str(wrapper),
        "CARGO_INCREMENTAL": "0", "SCCACHE_GHA_ENABLED": "true",
        "SCCACHE_GHA_VERSION": "ianvs-flutter-native-v1-" + epoch,
        # Only server I/O failure may fall back; compilation errors are never retried.
        "SCCACHE_IGNORE_SERVER_IO_ERROR": "1",
    }
    if any("\n" in value or "\r" in value for value in exports.values()):
        raise ValueError("invalid multiline environment value")
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for key, value in exports.items():
            output.write(f"{key}={value}\n")
    diagnostics = root / "build/ci/native-phases/compiler-cache"
    diagnostics.mkdir(parents=True, exist_ok=True)
    (diagnostics / "configuration.json").write_text(json.dumps({
        "schema_version": 1, "epoch": epoch, "tools": tools,
        "scope": "registry lib/rlib only, Native Hooks only, flutter-checks only",
        "final_libraries_cached": False,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Native Hook compiler-cache pilot enabled: {version}; epoch={epoch}")
    return exports


def numeric_tree(value: object, depth: int = 0) -> object:
    if type(value) is int and value >= 0:
        return value
    if isinstance(value, dict) and depth < 4 and len(value) < 64:
        return {key: numeric_tree(item, depth + 1) for key, item in value.items()
                if isinstance(key, str) and re.fullmatch(r"[A-Za-z0-9_+ .-]{1,80}", key)}
    return None


def cache_snapshot() -> dict | None:
    """Read bounded, numeric counters only; unavailable is not a cache miss."""
    if os.environ.get(FLAG) != "1":
        return None
    try:
        result = subprocess.run(
            [os.environ["SCCACHE_PATH"], "--show-stats", "--stats-format=json"],
            check=True, capture_output=True, text=True, timeout=3,
        )
        if len(result.stdout) > 65536:
            raise ValueError("oversized cache statistics")
        payload = json.loads(result.stdout)
        stats = payload.get("stats", payload)
        counters = {name: numeric_tree(stats[name]) for name in COUNTERS if name in stats}
        if not counters:
            raise ValueError("missing cache counters")
        return {"available": True, "counters": counters}
    except (KeyError, AttributeError, TypeError, ValueError, OSError, subprocess.SubprocessError) as error:
        return {"available": False, "error_type": type(error).__name__}


def main(arguments: list[str]) -> int:
    if arguments == ["configure"]:
        configure()
        return 0
    if len(arguments) >= 2 and arguments[0] == "rustc":
        command, environment = compiler_command(arguments[1:], dict(os.environ))
        # exec preserves rustc's exit status, stdout/stderr and cancellation signals.
        os.execvpe(command[0], command, environment)
    raise ValueError("usage: native_hook_cache.py configure | rustc <compiler> <args...>")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

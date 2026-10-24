#!/usr/bin/env python3
"""Bridge the pinned Dart Hook environment through its supported PATH boundary.

Only CI-generated, non-secret settings are restored, and only for recognized
Hook Cargo targets. Admission stays in native_hook_cache.compiler_command.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys

import native_hook_cache as cache

ROOT = cache.ROOT
SAFE_SETTINGS = frozenset({
    cache.FLAG, cache.EPOCH, "GITHUB_ACTIONS", "GITHUB_JOB", "RUSTC_WRAPPER",
    "SCCACHE_PATH", "SCCACHE_GHA_ENABLED", "SCCACHE_GHA_VERSION",
    "SCCACHE_IGNORE_SERVER_IO_ERROR", "SCCACHE_IDLE_TIMEOUT", "CARGO_INCREMENTAL",
    "CARGO_HOME", "RUSTUP_HOME", "SCCACHE_SERVER_UDS",
})
PRESENCE_KEYS = (cache.FLAG, cache.EPOCH, "RUSTC_WRAPPER", "SCCACHE_PATH", "GITHUB_JOB")
REQUIRED_COMPILER_KEYS = (
    *PRESENCE_KEYS, "GITHUB_ACTIONS", "CARGO_TARGET_DIR", "CARGO_MANIFEST_DIR",
    "CARGO_HOME", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET",
)
PACKAGES = ("ianvs_pty", "ianvs_terminal_core")


def diagnostics(root: Path = ROOT) -> Path:
    return root / "build/ci/native-phases/compiler-cache"


def target_scope(environment: dict[str, str], root: Path = ROOT) -> dict | None:
    try:
        path = Path(environment.get("CARGO_TARGET_DIR", ""))
        if not path.is_absolute():
            return None
        relative = path.resolve().relative_to(root.resolve()).as_posix()
        match = cache.HOOK_PATH.fullmatch(relative)
        return match.groupdict() if match else None
    except (ValueError, OSError, RuntimeError):
        return None


def append_event(event: dict, root: Path = ROOT) -> None:
    """One small append per invocation; never log arguments or environment values."""
    directory = diagnostics(root)
    directory.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(event, sort_keys=True) + "\n").encode()
    if len(data) > 4096:
        raise ValueError("oversized compiler-cache event")
    fd = os.open(directory / "bridge-events.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        if os.write(fd, data) != len(data):
            raise OSError("incomplete compiler-cache diagnostic write")
    finally:
        os.close(fd)


def read_runtime(path: Path, root: Path = ROOT) -> dict:
    if path.stat().st_size > 16384:
        raise ValueError("oversized compiler-cache runtime configuration")
    data = json.loads(path.read_text(encoding="utf-8"))
    settings = data["environment"]
    if (data.get("schema_version") != 1 or data.get("root") != str(root.resolve())
            or not isinstance(settings, dict) or not set(settings) <= SAFE_SETTINGS
            or any(not isinstance(value, str) or len(value) > 4096
                   or "\n" in value or "\r" in value for value in settings.values())
            or settings.get(cache.FLAG) != "1"
            or settings.get("GITHUB_ACTIONS") != "true"
            or settings.get("GITHUB_JOB") != "flutter-checks"
            or not re.fullmatch(r"[0-9a-f]{64}", settings.get(cache.EPOCH, ""))):
        raise ValueError("invalid compiler-cache runtime configuration")
    for value in (data["cargo"], settings["RUSTC_WRAPPER"], settings["SCCACHE_PATH"]):
        if not isinstance(value, str) or not Path(value).is_absolute():
            raise ValueError("compiler-cache tool path is not absolute")
    return data


def cargo_command(arguments: list[str], environment: dict[str, str], runtime: dict,
                  root: Path = ROOT) -> tuple[list[str], dict[str, str], dict | None]:
    command = [runtime["cargo"], *arguments]
    env = dict(environment)
    scope = target_scope(env, root)
    # An explicitly disabled or differently scoped caller is never re-enabled.
    if (scope is None or env.get(cache.FLAG, "1") != "1"
            or env.get("GITHUB_ACTIONS", "true") != "true"
            or env.get("GITHUB_JOB", "flutter-checks") != "flutter-checks"):
        return command, env, None
    settings = runtime["environment"]
    if (env.get("RUSTC_WORKSPACE_WRAPPER")
            or env.get("RUSTC_WRAPPER", settings["RUSTC_WRAPPER"]) != settings["RUSTC_WRAPPER"]):
        raise RuntimeError("refusing to replace a compiler wrapper at the Hook boundary")
    present = {key: bool(env.get(key)) for key in PRESENCE_KEYS}
    for key, value in settings.items():
        # The Hook may already have located a nondefault toolchain home.
        if key in {"CARGO_HOME", "RUSTUP_HOME"}:
            env.setdefault(key, value)
        else:
            env[key] = value
    return command, env, {"kind": "cargo", "decision": "bridge", "scope": scope,
                          "inherited_settings_present": present}


def rustc_command(arguments: list[str], environment: dict[str, str],
                  root: Path = ROOT) -> tuple[list[str], dict[str, str], dict]:
    command, env = cache.compiler_command(arguments, environment, root)
    scope = target_scope(environment, root)
    if command != arguments:
        decision = "eligible_registry_rlib"
    elif not cache.crate_types(arguments[1:]):
        decision = "compiler_probe_or_response_file"
    elif not cache.crate_types(arguments[1:]) <= {"lib", "rlib"}:
        decision = "excluded_crate_type"
    elif Path(arguments[0]).name not in {"rustc", "rustc.exe"}:
        decision = "nested_compiler_wrapper"
    else:
        decision = "scope_or_source_rejected"
    event = {"kind": "rustc", "decision": decision, "scope": scope,
             "missing_settings": [key for key in REQUIRED_COMPILER_KEYS
                                  if not environment.get(key)]}
    return command, env, event


def _server_output(arguments: list[str], environment: dict[str, str]) -> str:
    result = subprocess.run([environment["SCCACHE_PATH"], *arguments],
                            env=environment, check=True, capture_output=True,
                            text=True, timeout=30)
    if len(result.stdout) > 65536:
        raise ValueError("oversized sccache setup response")
    return result.stdout


def start_server(environment: dict[str, str]) -> None:
    # A job-private socket avoids stopping/resetting an unrelated daemon.
    # --show-stats alone does NOT start a server in sccache v0.16.0.
    # Credentials stay in this parent daemon, never in the Hook's runtime file.
    socket_path = Path(environment["SCCACHE_SERVER_UDS"])
    if not socket_path.is_absolute() or os.path.lexists(socket_path):
        raise RuntimeError("refusing to reuse an existing sccache server socket")
    _server_output(["--start-server"], environment)
    if not socket_path.is_socket():
        raise RuntimeError("sccache did not create its job-private server socket")
    payload = json.loads(_server_output(["--show-stats", "--stats-format=json"], environment))
    requests = payload.get("stats", payload).get("compile_requests")
    if type(requests) is not int or requests != 0:
        raise RuntimeError("new sccache daemon has unexpected or unavailable statistics")


def configure(root: Path = ROOT) -> None:
    if (platform.system() != "Darwin" or os.environ.get(cache.FLAG) != "1"
            or os.environ.get("GITHUB_ACTIONS") != "true"
            or os.environ.get("GITHUB_JOB") != "flutter-checks"):
        raise RuntimeError("Hook bridge requires the configured macOS flutter-checks pilot")
    temporary = Path(os.environ["RUNNER_TEMP"]).resolve()
    original_wrapper = temporary / "ianvs-native-hook-rustc"
    if (Path(os.environ.get("RUSTC_WRAPPER", "")).resolve() != original_wrapper
            or os.environ.get("RUSTC_WORKSPACE_WRAPPER")):
        raise RuntimeError("unexpected compiler wrapper before Hook bridge setup")
    real_cargo = shutil.which("cargo")
    if not real_cargo or not Path(real_cargo).is_absolute():
        raise RuntimeError("cannot locate the original Cargo executable")
    # Do NOT resolve this executable's symlink: Cargo is often a rustup proxy.
    module = root / "tools/ci/native_hook_cache_bridge.py"
    epoch = cache.digest({"base_epoch": os.environ[cache.EPOCH], "bridge_schema": 1,
                          "bridge_sha256": hashlib.sha256(module.read_bytes()).hexdigest()})
    directory = temporary / "ianvs-native-hook-bridge"
    directory.mkdir(mode=0o700)  # Refuse to overwrite unknown or stale runtime state.
    binary = directory / "bin"
    binary.mkdir(mode=0o700)
    wrapper = directory / "rustc-wrapper"
    runtime_path = directory / "runtime.json"
    settings = {
        cache.FLAG: "1", cache.EPOCH: epoch, "GITHUB_ACTIONS": "true",
        "GITHUB_JOB": "flutter-checks", "RUSTC_WRAPPER": str(wrapper),
        "SCCACHE_PATH": os.environ["SCCACHE_PATH"], "CARGO_INCREMENTAL": "0",
        "SCCACHE_GHA_ENABLED": "true", "SCCACHE_GHA_VERSION": "ianvs-flutter-native-v2-" + epoch,
        "SCCACHE_IGNORE_SERVER_IO_ERROR": "1", "SCCACHE_IDLE_TIMEOUT": "0",
        "SCCACHE_SERVER_UDS": str(temporary / "ianvs-hook-cache.sock"),
        "CARGO_HOME": os.environ.get("CARGO_HOME") or str(Path.home() / ".cargo"),
        "RUSTUP_HOME": os.environ.get("RUSTUP_HOME") or str(Path.home() / ".rustup"),
    }
    runtime = {"schema_version": 1, "root": str(root.resolve()),
               "cargo": real_cargo, "environment": settings}
    runtime_path.write_text(json.dumps(runtime) + "\n", encoding="utf-8")
    runtime_path.chmod(0o600)
    read_runtime(runtime_path, root)
    python = shlex.quote(sys.executable) + " " + shlex.quote(str(module))
    selector = ('#!/bin/sh\ncase "${CARGO_TARGET_DIR-}" in\n'
                '  */.dart_tool/hooks_runner/shared/*/build/*/cargo-target|'
                '*/.dart_tool/hooks_runner/shared/*/build/*/cargo-target/)\n')
    wrapper.write_text(selector + '    exec ' + python + ' rustc "$@" ;;\n'
                       '  *) exec "$@" ;;\nesac\n', encoding="utf-8")
    shim = binary / "cargo"
    shim.write_text(selector + '    exec ' + python + ' cargo ' + shlex.quote(str(runtime_path)) +
                    ' "$@" ;;\n  *) exec ' + shlex.quote(real_cargo) + ' "$@" ;;\nesac\n', encoding="utf-8")
    for executable in (wrapper, shim):
        executable.chmod(0o700)
    start_server(dict(os.environ, **settings))
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for key, value in settings.items():
            output.write(f"{key}={value}\n")
    with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as output:
        output.write(str(binary) + "\n")
    config_path = diagnostics(root) / "configuration.json"
    configuration = json.loads(config_path.read_text(encoding="utf-8"))
    configuration.update(epoch=epoch, transport="scoped PATH Cargo bridge",
                         bridge_schema=1, credentials_forwarded=False)
    config_path.write_text(json.dumps(configuration, indent=2) + "\n", encoding="utf-8")
    print("Native Hook PATH bridge configured; cache credentials remain in the parent daemon.")


def rust_count(value: object) -> int | None:
    if isinstance(value, dict):
        counts = value.get("counts", {})
        value = counts.get("Rust", 0) if isinstance(counts, dict) else None
    return value if type(value) is int and value >= 0 else None


def usage_summary(root: Path = ROOT) -> dict:
    path = diagnostics(root) / "bridge-events.jsonl"
    counts: Counter[str] = Counter()
    eligible: Counter[str] = Counter()
    bridged: Counter[str] = Counter()
    errors = []
    try:
        if path.stat().st_size > 8 * 1024 * 1024:
            raise ValueError("oversized event log")
        with path.open(encoding="utf-8") as source:
            for line in source:
                if len(line) > 4096:
                    raise ValueError("oversized event")
                event = json.loads(line)
                kind, decision = event["kind"], event["decision"]
                if not re.fullmatch(r"[a-z_]{1,64}", decision):
                    raise ValueError("invalid decision")
                counts[decision] += 1
                package = (event.get("scope") or {}).get("package")
                if package in PACKAGES:
                    if kind == "cargo" and decision == "bridge":
                        bridged[package] += 1
                    if kind == "rustc" and decision == "eligible_registry_rlib":
                        eligible[package] += 1
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        errors.append("missing_or_invalid_bridge_events")
    for package in PACKAGES:
        if bridged[package] == 0 or eligible[package] == 0:
            errors.append("no_real_compiler_routing_for_" + package)
    snapshot = cache.cache_snapshot()
    counters = snapshot.get("counters", {}) if snapshot and snapshot.get("available") else {}
    for key in ("compile_requests", "requests_executed"):
        value = counters.get(key)
        if type(value) is not int or value <= 0:
            errors.append("missing_or_zero_" + key)
    hits = rust_count(counters.get("cache_hits"))
    misses = rust_count(counters.get("cache_misses"))
    if hits is None or misses is None or hits + misses <= 0:
        errors.append("no_cacheable_rust_requests")
    return {"schema_version": 1, "passed": not errors, "errors": errors,
            "decisions": dict(counts), "cargo_invocations": dict(bridged),
            "eligible_requests": dict(eligible), "compiler_cache": snapshot,
            "note": "Routing evidence only; cold/warm speedup is not established."}


def main(arguments: list[str]) -> int:
    if arguments == ["bootstrap"]:
        os.environ.update(cache.configure())
        configure()
        return 0
    if arguments == ["configure"]:
        configure()
        return 0
    if arguments == ["verify"]:
        if os.environ.get(cache.FLAG) != "1" or os.environ.get("GITHUB_JOB") != "flutter-checks":
            raise RuntimeError("cache usage gate invoked without its configured pilot")
        result = usage_summary()
        diagnostics().mkdir(parents=True, exist_ok=True)
        (diagnostics() / "usage.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return 0 if result["passed"] else 1
    if len(arguments) >= 2 and arguments[0] == "cargo":
        runtime = read_runtime(Path(arguments[1]))
        command, environment, event = cargo_command(arguments[2:], dict(os.environ), runtime)
    elif len(arguments) >= 2 and arguments[0] == "rustc":
        command, environment, event = rustc_command(arguments[1:], dict(os.environ))
    else:
        raise ValueError("usage: native_hook_cache_bridge.py bootstrap | configure | verify | cargo <config> ... | rustc ...")
    if event is not None:
        append_event(event)
    # No shell interpolation, retries, output capture or cancellation re-parenting.
    os.execvpe(command[0], command, environment)
    return 1  # exec never returns on success.


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Real macOS rebuild checks; temporary product sources, never cached dylibs.

This is correctness acceptance, not a performance benchmark or a Flutter test
replacement. The ordinary Verify workflow must also pass on the same PR head.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
SYMBOL = "ianvs_ci_cache_acceptance_probe"
CFG = "ianvs_ci_cache_probe"
CASES = (("cache_off", 101, False, False, 101),
         ("cache_populate", 101, True, False, 101),
         ("source_changed", 202, True, False, 202),
         ("config_changed", 202, True, True, 1202))
PACKAGES = (("ianvs_pty", "native/core"),
            ("ianvs_terminal_core", "packages/ianvs_terminal_core/native/core"))


def probe_source(original: str, value: int) -> str:
    if SYMBOL in original:
        raise ValueError("probe symbol already exists in product sources")
    return original + (f"\n#[unsafe(no_mangle)]\npub extern \"C\" fn {SYMBOL}() -> i32 {{\n"
                       f"    {value} + if cfg!({CFG}) {{ 1000 }} else {{ 0 }}\n}}\n")


def counter(snapshot: dict, name: str, rust: bool = False) -> int:
    if not snapshot or snapshot.get("available") is not True:
        raise ValueError("compiler-cache statistics unavailable")
    value = snapshot["counters"].get(name)
    if rust:
        if not isinstance(value, dict) or not isinstance(value.get("counts"), dict):
            raise ValueError(f"missing typed cache counter: {name}")
        value = value["counts"].get("Rust", 0)
    if type(value) is not int or value < 0:
        raise ValueError(f"invalid cache counter: {name}")
    return value


def delta(before: dict, after: dict) -> dict:
    result = {}
    for name in ("compile_requests", "cache_hits", "cache_misses",
                 "cache_read_errors", "cache_write_errors", "cache_errors"):
        typed = name in {"cache_hits", "cache_misses", "cache_errors"}
        difference = counter(after, name, typed) - counter(before, name, typed)
        if difference < 0:
            raise ValueError("cache counters reset during acceptance")
        result[name] = difference
    return result


def check_case(name: str, counts: dict, observed: int, expected: int) -> None:
    if observed != expected:
        raise RuntimeError(f"{name}: loaded stale/incorrect native library: {observed} != {expected}")
    if counts["cache_read_errors"] or counts["cache_write_errors"] or counts["cache_errors"]:
        raise RuntimeError(f"{name}: cache I/O error makes this sample invalid")
    if name == "cache_off" and counts["compile_requests"] != 0:
        raise RuntimeError("disabled build unexpectedly used compiler cache")
    if name != "cache_off" and counts["compile_requests"] <= 0:
        raise RuntimeError("enabled build did not route real compiler-cache requests")
    if name == "source_changed" and counts["cache_hits"] <= 0:
        raise RuntimeError("source-change sample did not exercise a warm dependency cache")
    if name == "config_changed" and counts["cache_misses"] <= 0:
        raise RuntimeError("changed compiler flags did not cause any cache misses")


def command_output(args: list[str], *, cwd: Path = ROOT) -> str:
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE, timeout=60).stdout.strip()


def build(args: list[str], cwd: Path, environment: dict[str, str], log: Path) -> None:
    # A private process group bounds cleanup on timeout/interruption. Output goes
    # directly to a file: descendants cannot hold a captured stdout pipe open.
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(args, cwd=cwd, env=environment,
                                   stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=900)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=10)
            raise
    if code:
        print(log.read_text(errors="replace")[-12000:], file=sys.stderr)
        raise subprocess.CalledProcessError(code, args)


def load_probe(library: Path) -> int:
    # Each load is a new process, so dyld cannot reuse a previously loaded image.
    script = ("import ctypes,sys; lib=ctypes.CDLL(sys.argv[1]); "
              f"fn=getattr(lib,{SYMBOL!r}); fn.restype=ctypes.c_int32; "
              "fn.argtypes=[]; print(fn())")
    return int(command_output([sys.executable, "-c", script, str(library)]))


def main() -> int:
    import native_hook_cache as cache

    if platform.system() != "Darwin" or os.environ.get(cache.FLAG) != "1":
        raise RuntimeError("real acceptance requires macOS and the configured cache bridge")
    if os.environ.get("GITHUB_JOB") != "flutter-checks":
        raise RuntimeError("acceptance must use the existing scoped bridge admission")
    host = next(line.split(": ", 1)[1] for line in
                command_output(["rustc", "-vV"]).splitlines() if line.startswith("host: "))
    if host not in {"aarch64-apple-darwin", "x86_64-apple-darwin"}:
        raise RuntimeError("unsupported host target")
    sdk = command_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    cc = command_output(["xcrun", "--sdk", "macosx", "--find", "clang"])
    ar = command_output(["xcrun", "--sdk", "macosx", "--find", "ar"])
    destination = ROOT / "build/ci/cache-acceptance"
    destination.mkdir(parents=True, exist_ok=True)
    report = {"schema_version": 1, "passed": False, "cases": [],
              "source_sha": command_output(["git", "rev-parse", "HEAD"]),
              "pr_head_sha": os.environ.get("IANVS_ACCEPTANCE_HEAD_SHA"),
              "host": host, "deployment_target": "13.0",
              "scope": "real Cargo product rebuilds and fresh-process dylib loads; not a timing benchmark"}
    owned: list[Path] = []
    temporary = Path(tempfile.mkdtemp(prefix="ianvs-cache-acceptance-",
                                      dir=os.environ["RUNNER_TEMP"]))
    checkout = temporary / "sources"
    added = False
    try:
        subprocess.run(["git", "worktree", "add", "--detach", str(checkout), "HEAD"],
                       cwd=ROOT, check=True, timeout=180)
        added = True
        originals = {relative: (checkout / relative / "src/lib.rs").read_text()
                     for _, relative in PACKAGES}
        locks = {relative: hashlib.sha256((checkout / relative / "Cargo.lock").read_bytes()).hexdigest()
                 for _, relative in PACKAGES}
        for package, relative in PACKAGES:
            # No existing Hook directory is reused or removed. An unpredictable,
            # recognized scope exercises exactly the existing cache/bridge code.
            parent = ROOT / ".dart_tool/hooks_runner/shared" / package / "build"
            parent.mkdir(parents=True, exist_ok=True)
            if parent.resolve() != parent or parent.is_symlink():
                raise RuntimeError("refusing a symlinked Hook directory")
            allocation = parent / uuid.uuid4().hex
            allocation.mkdir()
            owned.append(allocation)
            target = allocation / "cargo-target"
            manifest = checkout / relative / "Cargo.toml"
            for name, value, enabled, changed_config, expected in CASES:
                # Keep canonical and packaged isolated source trees synchronized.
                for source_relative, original in originals.items():
                    (checkout / source_relative / "src/lib.rs").write_text(probe_source(original, value))
                if target.exists():
                    shutil.rmtree(target)  # Only the directory allocated above.
                target.mkdir()
                # Deliberately sanitize the child as Dart Hooks do. The PATH
                # bridge must restore settings only when FLAG is not disabled.
                environment = {key: value for key, value in os.environ.items()
                               if key in {"PATH", "HOME", "TMPDIR", "TMP", "TEMP", "LANG", "CARGO_HOME", "RUSTUP_HOME"}}
                environment.update({
                    cache.FLAG: "1" if enabled else "0",
                    "CARGO_TARGET_DIR": str(target), "CARGO_BUILD_JOBS": "2",
                    "CARGO_NET_OFFLINE": "true", "SDKROOT": sdk,
                    "MACOSX_DEPLOYMENT_TARGET": "13.0", "HOST_CC": cc, "HOST_AR": ar,
                    f"CARGO_TARGET_{host.upper().replace('-', '_')}_LINKER": cc,
                    f"CC_{host.replace('-', '_')}": cc, f"AR_{host.replace('-', '_')}": ar,
                    "RUSTFLAGS": f"--check-cfg=cfg({CFG})" + (f" --cfg={CFG}" if changed_config else ""),
                })
                before = cache.cache_snapshot()
                started = time.monotonic()
                print(f"Real native acceptance: {package}/{name}", flush=True)
                build(["cargo", "build", "--locked", "--release", "--manifest-path",
                       str(manifest), "--target", host], manifest.parent, environment,
                      destination / f"{package}-{name}.log")
                library = target / host / "release/libianvs_core.dylib"
                if not library.is_file():
                    raise RuntimeError("native rebuild produced no library")
                observed = load_probe(library)
                counts = delta(before, cache.cache_snapshot())
                check_case(name, counts, observed, expected)
                report["cases"].append({"package": package, "case": name, "passed": True,
                                        "observed": observed, "expected": expected,
                                        "rustflags": environment["RUSTFLAGS"],
                                        "seconds": round(time.monotonic() - started, 3),
                                        "compiler_cache_delta": counts,
                                        "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest()})
                if hashlib.sha256((manifest.parent / "Cargo.lock").read_bytes()).hexdigest() != locks[relative]:
                    raise RuntimeError("locked acceptance build changed Cargo.lock")
        report["passed"] = len(report["cases"]) == len(PACKAGES) * len(CASES)
        return 0
    except BaseException as error:
        report["passed"] = False
        report["error_type"] = type(error).__name__
        raise
    finally:
        try:
            for directory in owned:
                shutil.rmtree(directory)
            if added:
                subprocess.run(["git", "worktree", "remove", "--force", str(checkout)],
                               cwd=ROOT, check=True, timeout=120)
            shutil.rmtree(temporary)
        except BaseException:
            report["passed"] = False
            report["cleanup_failed"] = True
            raise
        finally:
            (destination / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
            print("NATIVE_CACHE_ACCEPTANCE=" + json.dumps(report), flush=True)


if __name__ == "__main__":
    sys.exit(main())

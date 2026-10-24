"""Scope, isolation and process semantics; no real Cargo/Flutter required."""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import native_hook_cache as cache


class NativeHookCacheTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="native cache ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cargo = self.root / "cargo"
        self.dependency = self.cargo / "registry/src/index-123/serde-1.0.0"
        self.dependency.mkdir(parents=True)
        self.env = {
            cache.FLAG: "1", cache.EPOCH: "a" * 64,
            "GITHUB_ACTIONS": "true", "GITHUB_JOB": "flutter-checks",
            "CARGO_TARGET_DIR": str(self.root / ".dart_tool/hooks_runner/shared/ianvs_pty/build/abc123/cargo-target"),
            "CARGO_MANIFEST_DIR": str(self.dependency), "CARGO_HOME": str(self.cargo),
            "SDKROOT": "/SDKs/MacOSX26.sdk", "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "SCCACHE_PATH": str(self.root / "sccache"),
        }
        self.args = ["/toolchain/bin/rustc", "--crate-type", "rlib", "--emit=dep-info,metadata,link", "src/lib.rs"]

    def command(self, **changes):
        return cache.compiler_command(self.args, dict(self.env, **changes), self.root)

    def assert_bypass(self, **changes):
        command, env = self.command(**changes)
        self.assertEqual(command, self.args)
        self.assertNotIn(cache.CONTEXT, env)

    def test_registry_rlib_inside_known_hook_is_cached(self):
        command, env = self.command()
        self.assertEqual(command, [self.env["SCCACHE_PATH"], *self.args])
        self.assertRegex(env[cache.CONTEXT], r"^[0-9a-f]{64}$")
        self.assertNotIn(cache.CONTEXT, self.env)
        for key, value in self.env.items():
            self.assertEqual(env[key], value)

    def test_disabled_non_ci_or_other_job_bypasses(self):
        for key, value in ((cache.FLAG, "0"), ("GITHUB_ACTIONS", "false"),
                           ("GITHUB_JOB", "example-checks"), (cache.EPOCH, "bad")):
            with self.subTest(key=key):
                self.assert_bypass(**{key: value})

    def test_incomplete_configuration_bypasses(self):
        for key in ("CARGO_TARGET_DIR", "CARGO_MANIFEST_DIR", "CARGO_HOME",
                    "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "SCCACHE_PATH"):
            with self.subTest(key=key):
                self.assert_bypass(**{key: ""})

    def test_debug_prebuild_and_clean_abi_remain_uncached(self):
        for path in ("native/core/target", "build/ci/abi/root-target", "clean/standalone-target"):
            self.assert_bypass(CARGO_TARGET_DIR=str(self.root / path))

    def test_workspace_vendor_and_git_sources_remain_uncached(self):
        for path in ("native/core", "native/vendor/zmodem2", "cargo/git/checkouts/dep",
                     "packages/ianvs_terminal_core/native/core", "cargo/registry/src-evil/foo/bar"):
            directory = self.root / path
            directory.mkdir(parents=True, exist_ok=True)
            self.assert_bypass(CARGO_MANIFEST_DIR=str(directory))

    def test_symlink_outside_registry_cannot_opt_in(self):
        outside = self.root / "local-crate"
        outside.mkdir()
        link = self.dependency.parent / "fake-1.0.0"
        link.symlink_to(outside, target_is_directory=True)
        self.assert_bypass(CARGO_MANIFEST_DIR=str(link))

    def test_unknown_or_outside_hook_path_bypasses(self):
        for path in ("/outside/.dart_tool/hooks_runner/shared/ianvs_pty/build/abc/cargo-target",
                     str(self.root / ".dart_tool/hooks_runner/shared/unknown/build/abc/cargo-target"),
                     str(self.root / ".dart_tool/hooks_runner/shared/ianvs_pty/build/abc/cargo-target/other"),
                     ".dart_tool/hooks_runner/shared/ianvs_pty/build/abc/cargo-target"):
            self.assert_bypass(CARGO_TARGET_DIR=path)

    def test_library_queries_final_linking_and_macros_are_not_cached(self):
        for types in ("bin", "cdylib", "dylib", "staticlib", "proc-macro", "rlib,cdylib", ""):
            with self.subTest(types=types):
                args = [self.args[0], f"--crate-type={types}", "src/lib.rs"]
                self.assertEqual(cache.compiler_command(args, self.env, self.root)[0], args)
        for extra in (["-vV"], ["@rustc.rsp"], ["--crate-type"]):
            args = [self.args[0], *extra]
            self.assertEqual(cache.compiler_command(args, self.env, self.root)[0], args)

    def test_all_crate_types_are_considered(self):
        args = [self.args[0], "--crate-type", "rlib", "--crate-type=cdylib", "src/lib.rs"]
        self.assertEqual(cache.compiler_command(args, self.env, self.root)[0], args)
        args = [self.args[0], "--crate-type=lib", "src/lib.rs"]
        self.assertEqual(cache.compiler_command(args, self.env, self.root)[0][0], self.env["SCCACHE_PATH"])

    def test_other_nested_compiler_wrapper_is_not_intercepted(self):
        args = ["/toolchain/custom-wrapper", *self.args]
        self.assertEqual(cache.compiler_command(args, self.env, self.root)[0], args)

    def test_source_configuration_sdk_and_epoch_have_distinct_contexts(self):
        baseline = self.command()[1][cache.CONTEXT]
        variations = (
            {"CARGO_TARGET_DIR": self.env["CARGO_TARGET_DIR"].replace("ianvs_pty", "ianvs_terminal_core")},
            {"CARGO_TARGET_DIR": self.env["CARGO_TARGET_DIR"].replace("abc123", "def456")},
            {"MACOSX_DEPLOYMENT_TARGET": "12.0"}, {"SDKROOT": "/SDKs/MacOSX27.sdk"},
            {"HOST_CC": "/Xcode/clang"}, {cache.EPOCH: "b" * 64},
        )
        contexts = {self.command(**change)[1][cache.CONTEXT] for change in variations}
        self.assertNotIn(baseline, contexts)
        self.assertEqual(len(contexts), len(variations))

    def test_parent_project_locations_are_supported(self):
        for prefix in ("example", "packages/ianvs_pty", "packages/ianvs_terminal_core"):
            tail = Path(self.env["CARGO_TARGET_DIR"]).relative_to(self.root)
            command, _ = self.command(CARGO_TARGET_DIR=str(self.root / prefix / tail))
            self.assertEqual(command[0], self.env["SCCACHE_PATH"])

    def test_stats_disabled_does_not_spawn_a_process(self):
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(cache.subprocess, "run") as run:
            self.assertIsNone(cache.cache_snapshot())
            run.assert_not_called()

    def test_stats_keep_numeric_counters_not_location_or_secrets(self):
        payload = {"stats": {"compile_requests": 4, "cache_hits": {"counts": {"Rust": 3}},
                             "cache_misses": {"counts": {"Rust": 1}}},
                   "cache_location": "https://example/token=SECRET"}
        with mock.patch.dict(os.environ, self.env, clear=True), \
             mock.patch.object(cache.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(payload))):
            record = cache.cache_snapshot()
        self.assertTrue(record["available"])
        self.assertEqual(record["counters"]["cache_hits"]["counts"]["Rust"], 3)
        self.assertNotIn("SECRET", json.dumps(record))

    def test_stats_failure_is_not_reported_as_zero_hits(self):
        for failure in (subprocess.TimeoutExpired("sccache", 3), FileNotFoundError("SECRET"),
                        subprocess.CalledProcessError(1, "sccache", stderr="SECRET")):
            with mock.patch.dict(os.environ, self.env, clear=True), \
                 mock.patch.object(cache.subprocess, "run", side_effect=failure):
                record = cache.cache_snapshot()
            self.assertFalse(record["available"])
            self.assertNotIn("counters", record)
            self.assertNotIn("SECRET", json.dumps(record))

    def test_malformed_empty_or_oversized_stats_are_unavailable(self):
        for raw in ("{", "[]", "{}", "x" * 65537):
            with mock.patch.dict(os.environ, self.env, clear=True), \
                 mock.patch.object(cache.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, raw)):
                self.assertFalse(cache.cache_snapshot()["available"])

    def prepare_configure(self):
        for name in ("pubspec.lock", "tools/ci/native_hook_cache.py",
                     "packages/ianvs_pty/hook/build.dart", "packages/ianvs_pty/hook/native_dependencies.dart",
                     "packages/ianvs_terminal_core/hook/build.dart", "packages/ianvs_terminal_core/hook/native_dependencies.dart"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        env = dict(self.env, RUNNER_TEMP=str(self.root), GITHUB_ENV=str(self.root / "env"))
        def output(args):
            return "sccache 0.16.0" if args[0] == env["SCCACHE_PATH"] else "fixture-tool-version"
        return env, output

    def test_configure_is_pinned_and_exports_only_scoped_cache_settings(self):
        env, output = self.prepare_configure()
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.object(cache.platform, "system", return_value="Darwin"), \
             mock.patch.object(cache, "command_output", side_effect=output), \
             contextlib.redirect_stdout(io.StringIO()):
            cache.configure(self.root)
        exports = (self.root / "env").read_text()
        self.assertIn("CARGO_INCREMENTAL=0\n", exports)
        self.assertIn("SCCACHE_GHA_ENABLED=true\n", exports)
        self.assertNotIn("CARGO_TARGET_DIR=", exports)
        self.assertNotIn("RUSTFLAGS=", exports)
        self.assertNotIn("ACTIONS_RUNTIME_TOKEN", exports)
        wrapper = self.root / "ianvs-native-hook-rustc"
        self.assertTrue(os.access(wrapper, os.X_OK))
        self.assertIn(' rustc "$@"', wrapper.read_text())
        subprocess.run(["sh", "-n", str(wrapper)], check=True)

    def test_configure_rejects_existing_wrappers_and_wrong_job(self):
        env, output = self.prepare_configure()
        for change in ({"RUSTC_WRAPPER": "existing"}, {"RUSTC_WORKSPACE_WRAPPER": "existing"},
                       {"GITHUB_JOB": "macos-app"}):
            with mock.patch.dict(os.environ, dict(env, **change), clear=True), \
                 mock.patch.object(cache.platform, "system", return_value="Darwin"), \
                 mock.patch.object(cache, "command_output", side_effect=output):
                with self.assertRaises(RuntimeError):
                    cache.configure(self.root)

    def test_configure_epoch_changes_with_hook_source(self):
        env, output = self.prepare_configure()
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.object(cache.platform, "system", return_value="Darwin"), \
             mock.patch.object(cache, "command_output", side_effect=output), \
             contextlib.redirect_stdout(io.StringIO()):
            cache.configure(self.root)
            path = self.root / "build/ci/native-phases/compiler-cache/configuration.json"
            before = json.loads(path.read_text())["epoch"]
            (self.root / "packages/ianvs_pty/hook/build.dart").write_text("changed\n")
            cache.configure(self.root)
            self.assertNotEqual(before, json.loads(path.read_text())["epoch"])

    def test_real_exec_preserves_failure_and_does_not_retry(self):
        compiler = self.root / "rustc"
        counter = self.root / "compiler-calls"
        compiler.write_text(f"#!{sys.executable}\nfrom pathlib import Path\nimport sys\np=Path({str(counter)!r})\np.write_text(p.read_text()+'call\\n' if p.exists() else 'call\\n')\nprint('compiler-stderr', file=sys.stderr)\nsys.exit(7)\n")
        compiler.chmod(0o700)
        env = dict(os.environ, **self.env)
        env[cache.FLAG] = "0"
        result = subprocess.run([sys.executable, cache.__file__, "rustc", str(compiler), "--crate-type=rlib"],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(counter.read_text(), "call\n")
        self.assertIn("compiler-stderr", result.stderr)

    def test_real_exec_preserves_sigterm(self):
        compiler = self.root / "rustc"
        compiler.write_text(f"#!{sys.executable}\nimport os,signal\nos.kill(os.getpid(),signal.SIGTERM)\n")
        compiler.chmod(0o700)
        result = subprocess.run([sys.executable, cache.__file__, "rustc", str(compiler)],
                                env=dict(os.environ, **{cache.FLAG: "0"}), timeout=10)
        self.assertEqual(result.returncode, -signal.SIGTERM)

    def test_cached_exec_preserves_compiler_failure_without_retry(self):
        module = self.root / "tools/ci/native_hook_cache.py"
        module.parent.mkdir(parents=True)
        module.write_text(Path(cache.__file__).read_text())
        compiler = self.root / "rustc"
        compiler.write_text(f"#!{sys.executable}\nimport sys\nprint('real-compiler')\nsys.exit(9)\n")
        compiler.chmod(0o700)
        sccache = Path(self.env["SCCACHE_PATH"])
        count = self.root / "cached-calls"
        sccache.write_text(
            f"#!{sys.executable}\nimport os,sys\nfrom pathlib import Path\n"
            f"p=Path({str(count)!r})\np.write_text(p.read_text()+'call\\n' if p.exists() else 'call\\n')\n"
            f"assert len(os.environ[{cache.CONTEXT!r}]) == 64\n"
            "os.execv(sys.argv[1],sys.argv[1:])\n")
        sccache.chmod(0o700)
        result = subprocess.run(
            [sys.executable, str(module), "rustc", str(compiler), "--crate-type=rlib"],
            env=dict(os.environ, **self.env), text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(count.read_text(), "call\n")
        self.assertIn("real-compiler", result.stdout)

    def test_phase_snapshots_keep_failure_and_do_not_infer_hook_hits(self):
        import native_phase_metrics as metrics
        before = {"available": True, "counters": {"compile_requests": 0}}
        after = {"available": True, "counters": {"compile_requests": 5}}
        with mock.patch.dict(os.environ, {cache.FLAG: "1"}), \
             mock.patch.object(metrics, "compiler_cache_snapshot", side_effect=[before, after]), \
             contextlib.redirect_stdout(io.StringIO()):
            phase = metrics.begin("PTY", self.root)
            result = metrics.finish(phase, 7)
        self.assertEqual(result["exit_code"], 7)
        self.assertEqual(result["hook_build_count"], 0)
        self.assertEqual(result["compiler_cache"]["before"], before)
        self.assertEqual(result["compiler_cache"]["after"], after)
        self.assertIn("Do not sum", result["compiler_cache"]["note"])

    def test_nested_phase_cache_counters_are_snapshots_not_summed(self):
        import native_phase_metrics as metrics
        snapshots = [{"available": True, "counters": {"compile_requests": n}} for n in [0, 1, 3, 5]]
        with mock.patch.dict(os.environ, {cache.FLAG: "1"}), \
             mock.patch.object(metrics, "compiler_cache_snapshot", side_effect=snapshots), \
             contextlib.redirect_stdout(io.StringIO()):
            parent = metrics.begin("repository", self.root)
            child = metrics.begin("PTY", self.root)
            leaf = metrics.finish(child, 0)
            result = metrics.finish(parent, 0)
        self.assertEqual(result["nested_phase_ids"], [leaf["id"]])
        self.assertIsNone(result["unattributed_seconds"])
        self.assertEqual(result["compiler_cache"]["after"], snapshots[3])
        self.assertEqual(leaf["compiler_cache"]["after"], snapshots[2])

    def test_phase_observation_spawns_no_cache_command_when_disabled(self):
        import native_phase_metrics as metrics
        with mock.patch.dict(os.environ, {cache.FLAG: "0"}), \
             mock.patch.object(cache.subprocess, "run") as run, \
             contextlib.redirect_stdout(io.StringIO()):
            phase = metrics.begin("uncached", self.root)
            result = metrics.finish(phase, 0)
        run.assert_not_called()
        self.assertNotIn("compiler_cache", result)

    def test_composite_rollout_is_scoped_pinned_and_has_no_ignored_failures(self):
        action = (cache.ROOT / ".github/actions/cache-rust/action.yml").read_text()
        self.assertIn(f"mozilla-actions/sccache-action@{cache.ACTION_SHA}", action)
        self.assertIn(f'version: "{cache.SCCACHE_VERSION}"', action)
        self.assertEqual(action.count("github.job == 'flutter-checks'"), 3)
        self.assertEqual(action.count("vars.IANVS_NATIVE_HOOK_CACHE != 'off'"), 3)
        self.assertNotIn("continue-on-error", action)
        self.assertIn("cache-workspace-crates: false", action)
        self.assertNotIn("CARGO_TARGET_DIR", action)


if __name__ == "__main__":
    unittest.main()

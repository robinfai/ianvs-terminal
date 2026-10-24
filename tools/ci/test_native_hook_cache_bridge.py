"""Hermetic-boundary regressions. Subprocess tools below are explicit stand-ins.

Real Cargo/rustc evidence is required separately by the workflow usage gate.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import contextlib
import io
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import native_hook_cache as cache
import native_hook_cache_bridge as bridge


class HookBridgeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="hook bridge ' ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.module = self.root / "tools/ci/native_hook_cache_bridge.py"
        self.module.parent.mkdir(parents=True)
        self.module.write_text(Path(bridge.__file__).read_text())
        (self.module.parent / "native_hook_cache.py").write_text(Path(cache.__file__).read_text())
        self.temp = self.root / "runner temp"
        self.temp.mkdir()
        self.real = self.root / "real tools"
        self.real.mkdir()
        self.home = self.root / "cargo-home"
        self.dep = self.home / "registry/src/index-123/fixture-1.0.0"
        self.dep.mkdir(parents=True)
        self.target = str(self.root / ".dart_tool/hooks_runner/shared/ianvs_pty/build/abc123/cargo-target")
        self.real_cargo = self.real / "cargo"
        self.compiler = self.real / "rustc"
        self.sccache = self.real / "sccache"
        self.write_executable(self.real_cargo, "import sys\nprint('cargo-direct')\nsys.exit(0)\n")
        self.write_executable(self.compiler, "print('compiler-output')\n")
        self.write_executable(self.sccache, "import os,sys\nprint('sccache-route', flush=True)\nos.execv(sys.argv[1],sys.argv[1:])\n")
        original = self.temp / "ianvs-native-hook-rustc"
        self.write_executable(original, "pass\n")
        self.setup_env = {
            "PATH": os.defpath, "HOME": str(self.root), cache.FLAG: "1", cache.EPOCH: "a" * 64,
            "GITHUB_ACTIONS": "true", "GITHUB_JOB": "flutter-checks",
            "RUNNER_TEMP": str(self.temp), "GITHUB_ENV": str(self.temp / "github-env"),
            "GITHUB_PATH": str(self.temp / "github-path"), "RUSTC_WRAPPER": str(original),
            "SCCACHE_PATH": str(self.sccache), "CARGO_HOME": str(self.home),
            "RUSTUP_HOME": str(self.root / "rustup-home"),
            "ACTIONS_RUNTIME_TOKEN": "SECRET-MUST-NOT-BE-FORWARDED",
            "UNRELATED_PASSWORD": "SECRET-MUST-NOT-BE-FORWARDED",
        }
        bridge.diagnostics(self.root).mkdir(parents=True)
        (bridge.diagnostics(self.root) / "configuration.json").write_text(json.dumps({"epoch": "a" * 64}))

    def write_executable(self, path, body):
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o700)

    def configure(self):
        with mock.patch.dict(os.environ, self.setup_env, clear=True), \
             mock.patch.object(bridge.platform, "system", return_value="Darwin"), \
             mock.patch.object(bridge.shutil, "which", return_value=str(self.real_cargo)), \
             mock.patch.object(bridge, "start_server") as server, \
             contextlib.redirect_stdout(io.StringIO()):
            bridge.configure(self.root)
        self.runtime_file = self.temp / "ianvs-native-hook-bridge/runtime.json"
        self.runtime = bridge.read_runtime(self.runtime_file, self.root)
        self.bin = self.runtime_file.parent / "bin"
        return server.call_args.args[0]

    def hook_environment(self):
        # PATH/HOME survive the pinned hooks_runner filter. Build settings below
        # are supplied by the real repository Hook, not by the parent process.
        return {"PATH": str(self.bin) + os.pathsep + os.defpath, "HOME": str(self.root),
                "CARGO_TARGET_DIR": self.target, "SDKROOT": "/SDKs/MacOSX26.sdk",
                "MACOSX_DEPLOYMENT_TARGET": "13.0"}

    def pipeline(self, compiler_body="print('compiler-output')\n"):
        self.configure()
        self.write_executable(self.compiler, compiler_body)
        self.write_executable(self.real_cargo,
            "import os,sys\n"
            "assert 'ACTIONS_RUNTIME_TOKEN' not in os.environ\n"
            "assert 'UNRELATED_PASSWORD' not in os.environ\n"
            "assert os.environ['SDKROOT']=='/SDKs/MacOSX26.sdk'\n"
            "assert os.environ['CARGO_INCREMENTAL']=='0'\n"
            f"os.environ['CARGO_MANIFEST_DIR']={str(self.dep)!r}\n"
            "wrapper=os.environ['RUSTC_WRAPPER']\n"
            f"os.execvpe(wrapper,[wrapper,{str(self.compiler)!r},'--crate-type=rlib','src/lib.rs'],os.environ)\n")
        return subprocess.run([str(self.bin / "cargo"), "build", "--locked", "--release"],
                              env=self.hook_environment(), capture_output=True, text=True, timeout=10)

    def events(self):
        return [json.loads(line) for line in (bridge.diagnostics(self.root) / "bridge-events.jsonl").read_text().splitlines()]

    def test_bootstrap_passes_only_the_original_configure_exports(self):
        exports = {cache.FLAG: "1", cache.EPOCH: "b" * 64, "RUSTC_WRAPPER": "/generated"}
        with mock.patch.dict(os.environ, {}, clear=True), \
             mock.patch.object(cache, "configure", return_value=exports) as first, \
             mock.patch.object(bridge, "configure") as second:
            self.assertEqual(bridge.main(["bootstrap"]), 0)
            self.assertEqual(dict(os.environ), exports)
            first.assert_called_once_with()
            second.assert_called_once_with()

    def test_workflow_keeps_real_builds_and_gates_cache_usage(self):
        root = Path(bridge.__file__).resolve().parents[2]
        workflow = (root / ".github/workflows/verify.yml").read_text()
        action = (root / ".github/actions/cache-rust/action.yml").read_text()
        self.assertIn("native_hook_cache_bridge.py bootstrap", action)
        self.assertIn("test_native_hook_cache*.py", action)
        self.assertEqual(action.count("github.job == 'flutter-checks'"), 3)
        self.assertEqual(action.count("vars.IANVS_NATIVE_HOOK_CACHE != 'off'"), 3)
        self.assertNotIn("continue-on-error", action)
        flutter = workflow.split("  flutter-checks:\n", 1)[1].split("  example-checks:\n", 1)[0]
        gate = flutter.split("      - name: Require real Native Hook compiler cache requests\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("!cancelled()", gate)
        self.assertIn("vars.IANVS_NATIVE_HOOK_CACHE != 'off'", gate)
        self.assertIn("native_hook_cache_bridge.py verify", gate)
        self.assertNotIn("continue-on-error", gate)
        self.assertLess(flutter.index("Run repository verification"), flutter.index("Require real Native Hook"))
        self.assertIn("./tools/verify_flutter_terminal.sh", flutter)
        self.assertIn("dart run tools/verify_terminal_core_publish.dart", flutter)
        self.assertIn("flutter test test/design", flutter)

    def test_generated_shims_cross_a_sanitized_environment(self):
        result = self.pipeline()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("compiler-output", result.stdout)
        self.assertIn("sccache-route", result.stdout)
        cargo, rustc = self.events()
        self.assertTrue(all(not value for value in cargo["inherited_settings_present"].values()))
        self.assertEqual(rustc["decision"], "eligible_registry_rlib")
        self.assertEqual(rustc["missing_settings"], [])

    def test_compiler_failure_is_preserved_without_retry(self):
        calls = self.root / "compiler-calls"
        result = self.pipeline("from pathlib import Path\nimport sys\n"
                               f"p=Path({str(calls)!r})\np.write_text(p.read_text()+'x' if p.exists() else 'x')\n"
                               "print('compiler-error',file=sys.stderr)\nsys.exit(17)\n")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(calls.read_text(), "x")
        self.assertIn("compiler-error", result.stderr)

    def test_compiler_sigterm_is_preserved_through_both_exec_boundaries(self):
        result = self.pipeline("import os,signal\nos.kill(os.getpid(),signal.SIGTERM)\n")
        self.assertEqual(result.returncode, -signal.SIGTERM)

    def test_original_cargo_failure_and_arguments_are_preserved(self):
        self.configure()
        self.write_executable(self.real_cargo,
            "import sys\nassert sys.argv[1:]==['build','space and ; shell']\nsys.exit(19)\n")
        result = subprocess.run([str(self.bin / "cargo"), "build", "space and ; shell"],
                                env=self.hook_environment(), capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 19)

    def test_runtime_and_diagnostics_never_contain_parent_secrets(self):
        parent = self.configure()
        self.assertEqual(parent["ACTIONS_RUNTIME_TOKEN"], self.setup_env["ACTIONS_RUNTIME_TOKEN"])
        for path in (self.runtime_file, self.temp / "github-env",
                     bridge.diagnostics(self.root) / "configuration.json"):
            self.assertNotIn("SECRET", path.read_text())
            self.assertNotIn("ACTIONS_RUNTIME_TOKEN", path.read_text())
        self.assertEqual(self.runtime_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.runtime_file.parent.stat().st_mode & 0o777, 0o700)
        self.assertTrue(set(self.runtime["environment"]) <= bridge.SAFE_SETTINGS)

    def test_shell_scripts_are_valid_and_paths_with_quotes_work(self):
        self.configure()
        for path in (self.bin / "cargo", Path(self.runtime["environment"]["RUSTC_WRAPPER"])):
            subprocess.run(["sh", "-n", str(path)], check=True)
            self.assertTrue(os.access(path, os.X_OK))
        self.assertEqual((self.temp / "github-path").read_text().strip(), str(self.bin))

    def test_debug_abi_and_non_hook_cargo_do_not_restore_settings(self):
        self.configure()
        self.write_executable(self.real_cargo,
            "import os\nassert 'RUSTC_WRAPPER' not in os.environ\n"
            f"assert {cache.FLAG!r} not in os.environ\nprint('uncached')\n")
        for directory in ("native/core/target", "build/ci/abi/root-target", "", ".dart_tool/unknown"):
            env = self.hook_environment()
            env["CARGO_TARGET_DIR"] = str(self.root / directory) if directory else ""
            result = subprocess.run([str(self.bin / "cargo"), "build"], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "uncached")
        self.assertFalse((bridge.diagnostics(self.root) / "bridge-events.jsonl").exists())

    def test_unrecognized_and_symlink_escaping_target_bypasses(self):
        self.configure()
        outside = self.root / "outside"
        outside.mkdir()
        linked = self.root / ".dart_tool"
        linked.symlink_to(outside, target_is_directory=True)
        for target in (self.target, self.target.replace("ianvs_pty", "unknown"),
                       self.target + "/child", "relative/cargo-target", "/elsewhere" + self.target):
            env = dict(self.hook_environment(), CARGO_TARGET_DIR=target)
            command, after, event = bridge.cargo_command(["build"], env, self.runtime, self.root)
            self.assertEqual(command, [str(self.real_cargo), "build"])
            self.assertEqual(after, env)
            self.assertIsNone(event)

    def test_explicit_disable_or_other_job_cannot_be_reenabled(self):
        self.configure()
        for changes in ({cache.FLAG: "0"}, {"GITHUB_ACTIONS": "false"}, {"GITHUB_JOB": "example-checks"}):
            env = dict(self.hook_environment(), **changes)
            _, after, event = bridge.cargo_command(["build"], env, self.runtime, self.root)
            self.assertEqual(after, env)
            self.assertIsNone(event)

    def test_existing_wrappers_are_not_overwritten(self):
        self.configure()
        for key in ("RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER"):
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                bridge.cargo_command(["build"], dict(self.hook_environment(), **{key: "/custom/wrapper"}),
                                     self.runtime, self.root)

    def test_effective_sdk_toolchain_home_and_profile_are_not_rewritten(self):
        self.configure()
        env = dict(self.hook_environment(), CARGO_HOME="/custom/cargo", RUSTUP_HOME="/custom/rustup",
                   HOST_CC="/Xcode/clang", MACOSX_DEPLOYMENT_TARGET="12.0")
        args = ["build", "--locked", "--release", "--target", "aarch64-apple-darwin"]
        command, after, _ = bridge.cargo_command(args, env, self.runtime, self.root)
        self.assertEqual(command[1:], args)
        for key in ("SDKROOT", "CARGO_HOME", "RUSTUP_HOME", "HOST_CC", "MACOSX_DEPLOYMENT_TARGET"):
            self.assertEqual(after[key], env[key])

    def test_source_and_final_link_exclusions_remain_in_original_policy(self):
        self.configure()
        _, env, _ = bridge.cargo_command(["build"], self.hook_environment(), self.runtime, self.root)
        env["CARGO_MANIFEST_DIR"] = str(self.dep)
        for crate_type in ("bin", "proc-macro", "cdylib", "staticlib", "rlib,cdylib"):
            args = [str(self.compiler), "--crate-type=" + crate_type]
            command, _, event = bridge.rustc_command(args, env, self.root)
            self.assertEqual(command, args)
            self.assertEqual(event["decision"], "excluded_crate_type")
        for source in ("native/core", "native/vendor/crate", "cargo/git/checkouts/dep"):
            path = self.root / source
            path.mkdir(parents=True, exist_ok=True)
            args = [str(self.compiler), "--crate-type=rlib"]
            command, _, event = bridge.rustc_command(args, dict(env, CARGO_MANIFEST_DIR=str(path)), self.root)
            self.assertEqual(command, args)
            self.assertEqual(event["decision"], "scope_or_source_rejected")

    def test_missing_settings_record_names_not_values(self):
        args = [str(self.compiler), "--crate-type=rlib", "SECRET-ARGUMENT"]
        command, _, event = bridge.rustc_command(args, {"UNRELATED_PASSWORD": "SECRET"}, self.root)
        self.assertEqual(command, args)
        self.assertIn("CARGO_HOME", event["missing_settings"])
        self.assertNotIn("SECRET", json.dumps(event))

    def test_runtime_rejects_secret_keys_wrong_root_and_invalid_epoch(self):
        self.configure()
        for change in ("secret", "root", "epoch", "relative", "newline"):
            data = json.loads(json.dumps(self.runtime))
            if change == "secret": data["environment"]["ACTIONS_RUNTIME_TOKEN"] = "SECRET"
            if change == "root": data["root"] = "/unrelated"
            if change == "epoch": data["environment"][cache.EPOCH] = "bad"
            if change == "relative": data["cargo"] = "relative/cargo"
            if change == "newline": data["environment"]["SCCACHE_PATH"] = "/tool\nOTHER=bad"
            self.runtime_file.write_text(json.dumps(data))
            with self.subTest(change=change), self.assertRaises(ValueError):
                bridge.read_runtime(self.runtime_file, self.root)

    def test_bridge_code_changes_invalidate_the_namespace(self):
        self.configure()
        before = self.runtime["environment"][cache.EPOCH]
        import shutil
        shutil.rmtree(self.runtime_file.parent)
        self.module.write_text(self.module.read_text() + "\n# changed bridge\n")
        self.configure()
        self.assertNotEqual(before, self.runtime["environment"][cache.EPOCH])

    def test_setup_rejects_wrong_scope_stale_state_and_foreign_wrapper(self):
        for key, value in (("GITHUB_JOB", "example-checks"), (cache.FLAG, "0"),
                           ("RUSTC_WRAPPER", "/foreign/wrapper")):
            with mock.patch.dict(os.environ, dict(self.setup_env, **{key: value}), clear=True), \
                 mock.patch.object(bridge.platform, "system", return_value="Darwin"), \
                 self.assertRaises(RuntimeError):
                bridge.configure(self.root)
        self.configure()
        with self.assertRaises(FileExistsError):
            self.configure()

    def test_runtime_keeps_cargo_proxy_path_instead_of_resolving_rustup(self):
        rustup = self.real / "rustup"
        self.real_cargo.rename(rustup)
        self.real_cargo.symlink_to(rustup)
        self.configure()
        self.assertEqual(self.runtime["cargo"], str(self.real_cargo))
        self.assertNotEqual(self.runtime["cargo"], str(self.real_cargo.resolve()))

    def test_parent_daemon_uses_a_fresh_socket_and_keeps_credentials(self):
        socket_path = self.root / "daemon.sock"
        server_socket = socket.socket(socket.AF_UNIX)
        self.addCleanup(server_socket.close)
        env = dict(self.setup_env, SCCACHE_IDLE_TIMEOUT="0", SCCACHE_SERVER_UDS=str(socket_path))
        def output(args, environment):
            if args == ["--start-server"]:
                server_socket.bind(str(socket_path))
                return "started"
            return json.dumps({"stats": {"compile_requests": 0}})
        with mock.patch.object(bridge, "_server_output", side_effect=output) as call:
            bridge.start_server(env)
        self.assertEqual([item.args[0] for item in call.call_args_list],
                         [["--start-server"], ["--show-stats", "--stats-format=json"]])
        self.assertTrue(all(item.args[1]["ACTIONS_RUNTIME_TOKEN"] == self.setup_env["ACTIONS_RUNTIME_TOKEN"]
                            for item in call.call_args_list))

    def test_existing_daemon_socket_is_not_reset_or_replaced(self):
        path = self.root / "daemon.sock"
        path.write_text("existing")
        env = dict(self.setup_env, SCCACHE_SERVER_UDS=str(path))
        with mock.patch.object(bridge, "_server_output") as call, self.assertRaises(RuntimeError):
            bridge.start_server(env)
        call.assert_not_called()
        self.assertEqual(path.read_text(), "existing")

    def test_zero_stats_without_a_live_server_are_not_accepted(self):
        env = dict(self.setup_env, SCCACHE_SERVER_UDS=str(self.root / "absent.sock"))
        with mock.patch.object(bridge, "_server_output", return_value="started") as call, \
             self.assertRaises(RuntimeError):
            bridge.start_server(env)
        self.assertEqual(call.call_count, 1)

    def populate_usage(self):
        for package in bridge.PACKAGES:
            scope = {"package": package, "configuration": "abc123"}
            bridge.append_event({"kind": "cargo", "decision": "bridge", "scope": scope}, self.root)
            bridge.append_event({"kind": "rustc", "decision": "eligible_registry_rlib", "scope": scope}, self.root)
        return {"available": True, "counters": {"compile_requests": 2, "requests_executed": 2,
                "cache_hits": {"counts": {"Rust": 0}}, "cache_misses": {"counts": {"Rust": 2}}}}

    def test_real_usage_gate_accepts_cold_misses_but_does_not_claim_speedup(self):
        snapshot = self.populate_usage()
        with mock.patch.object(cache, "cache_snapshot", return_value=snapshot):
            result = bridge.usage_summary(self.root)
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["eligible_requests"], {package: 1 for package in bridge.PACKAGES})
        self.assertIn("not established", result["note"])

    def test_zero_unavailable_or_noncacheable_only_stats_fail_the_gate(self):
        good = self.populate_usage()
        variants = [None, {"available": False}, {"available": True, "counters": {}},
                    {"available": True, "counters": dict(good["counters"], compile_requests=0)},
                    {"available": True, "counters": dict(good["counters"], requests_executed=0)},
                    {"available": True, "counters": dict(good["counters"], cache_misses={"counts": {"Rust": 0}})}]
        for snapshot in variants:
            with mock.patch.object(cache, "cache_snapshot", return_value=snapshot):
                self.assertFalse(bridge.usage_summary(self.root)["passed"])

    def test_one_package_only_or_missing_events_cannot_pass(self):
        snapshot = self.populate_usage()
        path = bridge.diagnostics(self.root) / "bridge-events.jsonl"
        lines = path.read_text().splitlines()
        for data in ("\n".join(lines[:2]) + "\n", "{broken\n", ""):
            path.write_text(data)
            with mock.patch.object(cache, "cache_snapshot", return_value=snapshot):
                self.assertFalse(bridge.usage_summary(self.root)["passed"])
        path.unlink()
        with mock.patch.object(cache, "cache_snapshot", return_value=snapshot):
            self.assertFalse(bridge.usage_summary(self.root)["passed"])

    def test_concurrent_diagnostic_appends_remain_complete(self):
        event = {"kind": "rustc", "decision": "excluded_crate_type", "scope": None}
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda _: bridge.append_event(event, self.root), range(100)))
        self.assertEqual(self.events(), [event] * 100)

    def test_cli_zero_usage_is_nonzero_and_writes_diagnostics(self):
        self.configure()
        self.write_executable(self.sccache,
            "import json\nprint(json.dumps({'stats':{'compile_requests':0,'requests_executed':0}}))\n")
        result = subprocess.run([sys.executable, str(self.module), "verify"],
            env=dict(os.environ, **self.runtime["environment"]), text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        data = json.loads((bridge.diagnostics(self.root) / "usage.json").read_text())
        self.assertFalse(data["passed"])
        self.assertNotIn("SECRET", json.dumps(data))


if __name__ == "__main__":
    unittest.main()

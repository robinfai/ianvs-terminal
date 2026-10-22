"""Behavioral tests of the measurement harness, not native/Flutter product tests."""
import copy
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

import native_hook_probe as probe

ROOT = Path(__file__).resolve().parents[2]


class NativeHookProbeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.core = self.root / "packages/ianvs_terminal_core/native/core"
        self.core.mkdir(parents=True)
        (self.core / "Cargo.toml").write_text('[package]\nname="test-core"\n')
        (self.core / "Cargo.lock").write_text("version = 4\n")
        directory = self.root / ".dart_tool/hooks_runner/ianvs_terminal_core/config"
        directory.mkdir(parents=True)
        self.path = directory / probe.METRIC_NAME
        self.target = directory / "cargo-target"
        self.target.mkdir()
        self.metric = {
            "schema_version": 1, "exit_code": 0, "elapsed_ms": 1234,
            "started_at": "2026-10-22T00:00:00Z", "profile": "release",
            "target": "aarch64-apple-darwin",
            "manifest_path": str(self.core / "Cargo.toml"),
            "working_directory": str(self.core), "target_directory": str(self.target),
            "build_environment": {
                "CARGO_TARGET_DIR": str(self.target), "CARGO_BUILD_JOBS": "2",
                "SDKROOT": "/example/sdk", "MACOSX_DEPLOYMENT_TARGET": "11.0",
            },
        }
        self.metric["arguments"] = [
            "build", "--locked", "--release", "--manifest-path",
            self.metric["manifest_path"], "--target", self.metric["target"],
        ]
        self.write_metric()

    def write_metric(self):
        self.path.write_text(json.dumps(self.metric))

    def test_successful_metric_is_loaded(self):
        self.assertEqual(probe.load_metric(self.path, self.root), self.metric)

    def test_discovery_prunes_cargo_artifacts(self):
        (self.target / probe.METRIC_NAME).write_text("not a measurement")
        self.assertEqual(probe.discover(self.root), [self.path])

    def test_missing_measurement_is_not_zero_cost(self):
        self.path.unlink()
        with self.assertRaisesRegex(ValueError, "No native hook"):
            probe.main(["--root", str(self.root)])

    def test_nonzero_build_is_not_a_valid_baseline(self):
        self.metric["exit_code"] = 101
        self.write_metric()
        with self.assertRaisesRegex(ValueError, "successful"):
            probe.load_metric(self.path, self.root)

    def test_rejects_unsupported_schema_and_target(self):
        for key, value in (("schema_version", 2), ("target", "x86_64-unknown-linux-gnu"),
                           ("profile", "debug"), ("elapsed_ms", -1)):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.metric)
                changed[key] = value
                self.path.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):
                    probe.load_metric(self.path, self.root)

    def test_rejects_cleaning_normal_workspace_target(self):
        self.metric["target_directory"] = str(self.core / "target")
        self.write_metric()
        with self.assertRaisesRegex(ValueError, "private cargo-target"):
            probe.load_metric(self.path, self.root)

    def test_rejects_symlink_target(self):
        self.target.rmdir()
        other = self.root / "other"
        other.mkdir()
        self.target.symlink_to(other, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "private cargo-target"):
            probe.load_metric(self.path, self.root)

    def test_rejects_changed_build_flags(self):
        self.metric["arguments"].append("--features=unmeasured")
        self.write_metric()
        with self.assertRaisesRegex(ValueError, "original locked"):
            probe.load_metric(self.path, self.root)

    def test_rejects_unbounded_build_parallelism(self):
        self.metric["build_environment"]["CARGO_BUILD_JOBS"] = "12"
        self.write_metric()
        with self.assertRaisesRegex(ValueError, "two-job"):
            probe.load_metric(self.path, self.root)

    def test_rejects_unexpected_environment_and_target(self):
        for key, value in (("CARGO_REGISTRIES_CRATES_IO_TOKEN", "secret"),
                           ("CARGO_TARGET_DIR", str(self.core))):
            with self.subTest(key=key):
                changed = copy.deepcopy(self.metric)
                changed["build_environment"][key] = value
                self.path.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):
                    probe.load_metric(self.path, self.root)

    def test_replay_uses_build_configuration_without_parent_rustflags(self):
        env = probe.replay_environment(self.metric, {
            "PATH": "/bin", "HOME": "/home/test", "RUSTFLAGS": "-Copt-level=0",
            "CARGO_REGISTRIES_CRATES_IO_TOKEN": "secret", "GITHUB_TOKEN": "secret",
            "SDKROOT": "/wrong-sdk", "NIX_CFLAGS_COMPILE": "-fPIC",
        })
        self.assertEqual(env["SDKROOT"], "/example/sdk")
        self.assertEqual(env["CARGO_BUILD_JOBS"], "2")
        self.assertEqual(env["NIX_CFLAGS_COMPILE"], "-fPIC")
        self.assertNotIn("RUSTFLAGS", env)
        self.assertFalse(any("TOKEN" in name for name in env))

    def test_cleanup_selects_local_not_registry_crates(self):
        metadata = {"packages": [
            {"id": "local-core", "source": None, "manifest_path": str(self.core / "Cargo.toml")},
            {"id": "external", "source": "registry+example", "manifest_path": "/external/Cargo.toml"},
        ]}
        self.assertEqual(probe.local_packages(metadata, self.root), ["local-core"])

    def test_cleanup_rejects_outside_checkout(self):
        with self.assertRaisesRegex(ValueError, "outside the checkout"):
            probe.local_packages({"packages": [
                {"id": "outside", "source": None, "manifest_path": "/outside/Cargo.toml"},
            ]}, self.root)

    def test_cleanup_rejects_empty_package_list(self):
        with self.assertRaisesRegex(ValueError, "No local Cargo"):
            probe.local_packages({"packages": []}, self.root)

    def fake_cargo(self, failure=""):
        directory = self.root / "bin"
        directory.mkdir()
        log = self.root / "cargo-calls.jsonl"
        metadata = {"packages": [
            {"id": "local-core", "source": None, "manifest_path": str(self.core / "Cargo.toml")},
            {"id": "registry-dep", "source": "registry+example", "manifest_path": "/cargo/dep/Cargo.toml"},
        ]}
        cargo = directory / "cargo"
        cargo.write_text(f'''#!{sys.executable}
import json, os, pathlib, sys
args = sys.argv[1:]
with open({str(log)!r}, "a") as output:
    output.write(json.dumps(args) + "\\n")
if args[0] == {failure!r}:
    sys.exit(17)
if args[0] == "metadata":
    print({json.dumps(metadata)!r})
if args[0] == "build":
    library = pathlib.Path(os.environ["CARGO_TARGET_DIR"]) / "aarch64-apple-darwin/release/libianvs_core.dylib"
    library.parent.mkdir(parents=True, exist_ok=True)
    library.write_text("fake artifact; test harness only")
''')
        cargo.chmod(0o755)
        env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])
        return log, env

    def test_replays_build_clean_build_with_original_arguments(self):
        log, env = self.fake_cargo()
        result = probe.probe(self.metric, self.root, env)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["build", "metadata", "clean", "build"])
        self.assertEqual(calls[0], self.metric["arguments"])
        self.assertEqual(calls[-1], self.metric["arguments"])
        self.assertIn("--locked", calls[1])
        self.assertEqual(calls[2][-2:], ["--package", "local-core"])
        self.assertNotIn("registry-dep", calls[2])
        self.assertIn("not an Actions cache restore", result["interpretation"])

    def test_failed_warm_build_stops_before_cleanup(self):
        log, env = self.fake_cargo(failure="build")
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            probe.probe(self.metric, self.root, env)
        self.assertEqual(failure.exception.returncode, 17)
        self.assertEqual(len(log.read_text().splitlines()), 1)

    def test_failed_clean_stops_before_dependency_warm_build(self):
        log, env = self.fake_cargo(failure="clean")
        with self.assertRaises(subprocess.CalledProcessError):
            probe.probe(self.metric, self.root, env)
        self.assertEqual(len(log.read_text().splitlines()), 3)


class ExampleProbeEntrypointTests(unittest.TestCase):
    def run_script(self, shard="0", *, actions=True, fail_command=""):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for directory in ("tools/ci", "example/test/design", "example/test/new", "bin"):
            (root / directory).mkdir(parents=True)
        for name in ("a", "b", "c", "d", "e", "f", "g"):
            (root / f"example/test/new/{name}_test.dart").touch()
        (root / "example/test/design/golden_test.dart").touch()
        shutil.copy2(ROOT / "tools/verify_flutter_terminal.sh", root / "tools/verify_flutter_terminal.sh")
        log = root / "calls"
        for name in ("flutter", "python3", "build_core.sh"):
            destination = root / ("tools" if name.endswith(".sh") else "bin") / name
            destination.write_text(
                "#!/usr/bin/env bash\nset -eu\n"
                f"echo \"${{0##*/}} $*\" >> {shlex.quote(str(log))}\n"
                f"if [ \"${{0##*/}}\" = {shlex.quote(fail_command)} ]; then exit 17; fi\n"
            )
            destination.chmod(0o755)
        env = {key: value for key, value in os.environ.items() if not key.startswith("VERIFY_")}
        env.update({
            "PATH": str(root / "bin") + os.pathsep + env["PATH"],
            "GITHUB_ACTIONS": "true" if actions else "false",
            "VERIFY_FLUTTER_TERMINAL_SUITE": "flutter",
            "VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE": "only",
            "VERIFY_FLUTTER_TERMINAL_EXAMPLE_SHARD": shard,
            "VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS": "1",
        })
        result = subprocess.run(["bash", str(root / "tools/verify_flutter_terminal.sh")],
                                env=env, text=True, capture_output=True, timeout=10)
        return result, log.read_text().splitlines() if log.exists() else []

    def test_only_shard_zero_replays_cargo(self):
        for shard in ("0", "1", "2"):
            with self.subTest(shard=shard):
                result, calls = self.run_script(shard)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("--replay" in calls[-1], shard == "0")
                self.assertIn("native_hook_probe.py", calls[-1])

    def test_local_invocation_never_runs_probe(self):
        result, calls = self.run_script(actions=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call.startswith("python3") for call in calls))

    def test_flutter_failure_is_preserved_and_probe_does_not_run(self):
        result, calls = self.run_script(fail_command="flutter")
        self.assertEqual(result.returncode, 17)
        self.assertIn("CI phase duration:", result.stderr)
        self.assertFalse(any(call.startswith("python3") for call in calls))

    def test_debug_build_failure_stops_before_tests(self):
        result, calls = self.run_script(fail_command="build_core.sh")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(len(calls), 1)

    def test_probe_failure_does_not_turn_green(self):
        result, _ = self.run_script(fail_command="python3")
        self.assertEqual(result.returncode, 17)

    def test_three_shards_cover_every_non_design_file_once(self):
        files = []
        for shard in ("0", "1", "2"):
            result, calls = self.run_script(shard)
            self.assertEqual(result.returncode, 0, result.stderr)
            command = next(call for call in calls if call.startswith("flutter test "))
            files.extend(command.split()[2:])
        self.assertEqual(len(files), len(set(files)))
        self.assertEqual(sorted(files), [f"test/new/{name}_test.dart" for name in "abcdefg"])


if __name__ == "__main__":
    unittest.main()

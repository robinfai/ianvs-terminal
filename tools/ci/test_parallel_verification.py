"""Exercise suite partitioning and the blocking workflow contract without SDKs.

The fixtures only replace external toolchains. The real repository shell script
and the exact aggregation step are executed. They do not validate product code.
"""
from collections import Counter
import itertools
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/verify.yml"


def job_source(job):
    """Extract one level-two job; fail loudly if the workflow shape changes."""
    match = re.search(r"(?ms)^  " + re.escape(job) + r":\n(.*?)(?=^  [\w-]+:\n|\Z)",
                      WORKFLOW.read_text())
    if match is None:
        raise AssertionError(f"Missing job: {job}")
    return match.group(1)


class ParallelVerificationTests(unittest.TestCase):
    def run_suite(self, suite=None, fail_command="", skip_design="0", os_name="Darwin"):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for path in ("tools", "bin", "native/core", "native/completion_core",
                     "native/vendor/par-term-emu-core-rust", "native/vendor/zmodem2",
                     "packages/ianvs_pty", "packages/ianvs_terminal",
                     "packages/ianvs_terminal_core/native/core", "backend",
                     "example/test/design", "example/test/new", "example/test/benchmarks",
                     "example/lib/features/shell"):
            (root / path).mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tools/verify_flutter_terminal.sh", root / "tools/verify_flutter_terminal.sh")
        (root / "example/lib/features/shell/shell_screen_command_menu.dart").write_text(
            "title: context.l10n.defaultsAppearance\n")
        for path in ("design/view_test.dart", "new/new_test.dart", "designated_test.dart",
                     "benchmarks/cat_log_benchmark_test.dart", "benchmarks/other_test.dart"):
            (root / "example/test" / path).touch()
        log = root / "commands.log"
        stub = '''#!/usr/bin/env bash
set -eu
name="${0##*/}"
printf '%s | %s | %s\\n' "$PWD" "$name" "$*" >> LOG_PATH
if [[ "$name $*" == FAIL_COMMAND ]]; then exit 17; fi
case "$name" in
  rustup) echo thumbv7em-none-eabihf ;;
  uname) echo OS_NAME ;;
esac
'''.replace("LOG_PATH", shlex.quote(str(log))).replace(
            "FAIL_COMMAND", shlex.quote(fail_command)).replace("OS_NAME", shlex.quote(os_name))
        for name in ("rustup", "cargo", "dart", "flutter", "go", "gofmt", "python3", "uname"):
            file = root / "bin" / name
            file.write_text(stub)
            file.chmod(0o755)
        for name in ("build_core.sh", "verify_generated_contracts.sh", "verify_macos_app.sh"):
            file = root / "tools" / name
            file.write_text(stub)
            file.chmod(0o755)
        env = {key: value for key, value in os.environ.items() if not key.startswith("VERIFY_")}
        env["PATH"] = str(root / "bin") + os.pathsep + env["PATH"]
        env["VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION"] = "1"
        env["VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS"] = skip_design
        if suite is not None:
            env["VERIFY_FLUTTER_TERMINAL_SUITE"] = suite
        result = subprocess.run(["bash", str(root / "tools/verify_flutter_terminal.sh")],
                                cwd=root, env=env, capture_output=True, text=True, timeout=20)
        commands = log.read_text().replace(str(root), "ROOT").splitlines() if log.exists() else []
        return result, commands

    def test_partition_union_equals_local_full_command_multiset(self):
        results = [self.run_suite(suite) for suite in (None, "native", "flutter")]
        for result, _ in results:
            self.assertEqual(result.returncode, 0, result.stderr)
        full, native, flutter = (Counter(commands) for _, commands in results)
        self.assertEqual(full, native + flutter)
        self.assertFalse(native & flutter, "No test or prerequisite should be run by both suites")

    def test_explicit_all_matches_legacy_default(self):
        self.assertEqual(self.run_suite()[1], self.run_suite("all")[1])

    def test_native_suite_never_invokes_dart_or_flutter(self):
        result, commands = self.run_suite("native")
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in commands:
            self.assertNotIn(" | dart | ", command)
            self.assertNotIn(" | flutter | ", command)
            self.assertNotIn(" | verify_macos_app.sh | ", command)
        self.assertIn("go test -race", " ".join(commands).replace(" | ", " "))
        self.assertIn("--required --shell zsh", "\n".join(commands))

    def test_flutter_suite_retains_ffi_generated_protocol_and_performance_checks(self):
        result, commands = self.run_suite("flutter")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = "\n".join(commands)
        for expected in ("build_core.sh", "verify_generated_contracts.sh", "sync_terminal_core.dart --check",
                         "validate_osc_protocol_corpus.py", "osc_semantic_probe.py --self-test",
                         "dart | analyze --fatal-infos", "bench_ci_smoke.yaml",
                         "runtime_documentation_contract_test.dart"):
            self.assertIn(expected, text)
        self.assertNotIn(" | cargo | ", text)
        self.assertNotIn(" | rustup | ", text)

    def test_native_suite_retains_every_rust_workspace_and_serial_test_safety(self):
        result, commands = self.run_suite("native")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = "\n".join(commands)
        for path in ("native/core", "native/completion_core", "native/vendor/par-term-emu-core-rust",
                     "native/vendor/zmodem2", "packages/ianvs_terminal_core/native/core"):
            self.assertIn(f"ROOT/{path} | cargo | test --locked", text)
        self.assertEqual(text.count("--test-threads=1"), 2)
        self.assertIn("--no-default-features --lib --target thumbv7em-none-eabihf", text)
        self.assertIn("--test ffi_abi_manifest_test --test session_architecture_test", text)

    def test_native_failure_is_not_swallowed(self):
        result, commands = self.run_suite("native", "cargo fmt --check")
        self.assertEqual(result.returncode, 17)
        self.assertIn("CI phase duration:", result.stderr)
        self.assertNotIn("Go backend", result.stdout)
        self.assertNotIn(" | flutter | ", "\n".join(commands))

    def test_flutter_failure_is_not_swallowed(self):
        result, _ = self.run_suite("flutter", "dart analyze --fatal-infos")
        self.assertEqual(result.returncode, 17)
        self.assertIn("CI phase duration:", result.stderr)
        self.assertNotIn("Example tests", result.stdout)

    def test_invalid_suite_stops_before_any_toolchain(self):
        for suite in ("Native", "none", "all native", "$(exit 0)"):
            with self.subTest(suite=suite):
                result, commands = self.run_suite(suite)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(commands, [])

    def test_local_default_runs_design_and_discovers_new_tests(self):
        result, commands = self.run_suite()
        self.assertEqual(result.returncode, 0, result.stderr)
        example = next(line for line in commands if line.startswith("ROOT/example | flutter | test "))
        for path in ("test/design/view_test.dart", "test/new/new_test.dart", "test/benchmarks/other_test.dart"):
            self.assertIn(path, example)
        self.assertNotIn("cat_log_benchmark_test.dart", example)

    def test_ci_exclusion_removes_only_the_independently_run_design_suite(self):
        result, commands = self.run_suite("flutter", skip_design="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        example = next(line for line in commands if line.startswith("ROOT/example | flutter | test "))
        self.assertNotIn("test/design/", example)
        self.assertIn("test/designated_test.dart", example)
        self.assertIn("test/new/new_test.dart", example)

    def test_independent_suites_keep_original_macos_coverage(self):
        for job, suite in (("native-checks", "native"), ("flutter-checks", "flutter")):
            block = job_source(job)
            self.assertIn("runs-on: macos-26", block)
            self.assertNotIn("needs:", block)
            self.assertIn("VERIFY_FLUTTER_TERMINAL_SUITE: " + suite, block)
            self.assertNotIn("continue-on-error:", block)
            self.assertIn("tools/verify_flutter_terminal.sh", block)

    def test_existing_required_check_aggregates_both_suites(self):
        block = job_source("flutter-terminal")
        self.assertIn("name: Flutter terminal (macos-26)", block)
        self.assertIn("needs: [native-checks, flutter-checks, example-checks]", block)
        self.assertIn("if: ${{ always() }}", block)
        self.assertIn("NATIVE_RESULT: ${{ needs.native-checks.result }}", block)
        self.assertIn("FLUTTER_RESULT: ${{ needs.flutter-checks.result }}", block)
        self.assertIn("EXAMPLE_RESULT: ${{ needs.example-checks.result }}", block)
        script = block.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in script.splitlines())
        for native, flutter in itertools.product(("success", "failure", "cancelled", "skipped", ""), repeat=2):
            with self.subTest(native=native, flutter=flutter):
                env = dict(os.environ, NATIVE_RESULT=native, FLUTTER_RESULT=flutter, EXAMPLE_RESULT="success")
                result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], env=env,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, native == flutter == "success")

    def test_example_parallel_gate(self):
        self.assertIn("VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE: only", job_source("example-checks"))
        self.assertIn("VERIFY_FLUTTER_TERMINAL_EXAMPLE_MODE: skip", job_source("flutter-checks"))
        result, commands = self.run_suite("flutter")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("example | flutter | test" in x for x in commands))
        block = job_source("flutter-terminal")
        script = "\n".join(line[10:] for line in block.split("        run: |\n", 1)[1].splitlines())
        for status in ("failure", "cancelled", "skipped", ""):
            env = dict(os.environ, NATIVE_RESULT="success", FLUTTER_RESULT="success", EXAMPLE_RESULT=status)
            self.assertNotEqual(subprocess.run(["bash", "-e", "-c", script], env=env, capture_output=True).returncode, 0)

    def test_example_single_runner_parallel_contract(self):
        block = job_source("example-checks")
        self.assertNotIn("matrix:", block)
        self.assertIn("Run Example widget tests with bounded in-job concurrency", block)
        self.assertIn("python3 tools/ci/run_example_parallel.py --workers 2", block)
        self.assertIn("needs: [native-checks, flutter-checks, example-checks]", job_source("flutter-terminal"))
        driver = (ROOT / "tools/ci/run_example_parallel.py").read_text()
        for required in ("--no-pub", "--concurrency={workers}", "subprocess.Popen", "proc.wait()", "return code"):
            self.assertIn(required, driver)
        self.assertEqual(driver.count("subprocess.Popen("), 1)
        self.assertNotIn("tests[i::args.workers]", driver)

    def test_timing_wrapper_retains_blocking_steps(self):
        block = job_source("flutter-checks")
        for name in ("Workspace pub get", "Visual golden tests",
                     "Standalone pub archive verification", "Repository verification"):
            self.assertIn(name, block)
        self.assertNotIn("continue-on-error:", block)
        script = (ROOT / "tools/verify_flutter_terminal.sh").read_text()
        for phase in ("Native debug prebuild", "Generated contracts and sync",
                      "OSC corpus validation"):
            self.assertIn('ci_begin_phase "' + phase + '"', script)

    def test_visual_failure_does_not_skip_other_verification(self):
        block = job_source("flutter-checks")
        self.assertIn("id: dependencies\\n        run: python3 tools/ci/time_command.py 'Workspace pub get' -- flutter pub get", block)
        for name in ("Verify standalone pub archive", "Run repository verification"):
            segment = block.split("      - name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertIn("if: ${{ !cancelled() && steps.dependencies.outcome == 'success' }}", segment)
        self.assertIn("(steps.visual_baselines.outcome == 'success' || steps.visual_baselines.outcome == 'failure')", block)
        visual = block.split("      - name: Verify visual baselines\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("time_command.py 'Visual golden tests' -- flutter test test/design", visual)
        self.assertNotIn("continue-on-error", visual)
        self.assertNotIn("continue-on-error", job_source("flutter-terminal"))

    def test_candidate_regeneration_requires_explicit_manual_input(self):
        block = job_source("flutter-checks")
        for name in ("Render baseline candidates for review", "Upload baseline candidates"):
            segment = block.split("      - name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertIn("github.event_name == 'workflow_dispatch' && inputs.render_baseline_candidates", segment)
            self.assertIn("steps.visual_baselines.outcome == 'failure'", segment)
        self.assertIn("type: boolean\n        default: false", WORKFLOW.read_text())
        self.assertIn("path: example/test/design/failures/", block)

    def test_cache_is_pinned_dependency_only_and_toolchain_scoped(self):
        action = (ROOT / ".github/actions/cache-rust/action.yml").read_text()
        self.assertIn("Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0", action)
        for setting in ("cache-bin: false", "cache-workspace-crates: false", "add-job-id-key: true",
                        "add-rust-environment-hash-key: true", "runner.os", "runner.arch", "xcodebuild -version"):
            self.assertIn(setting, action)
        self.assertNotIn("cache-directories:", action)
        for job in ("native-checks", "flutter-checks", "macos-app", "ios-terminal"):
            block = job_source(job)
            self.assertIn("uses: ./.github/actions/cache-rust", block)
            self.assertLess(block.index("name: Set up Rust"), block.index("name: Cache Rust dependencies"))
            self.assertIn("native/core", block)
            self.assertIn("packages/ianvs_terminal_core/native/core", block)

    def test_all_remote_actions_remain_commit_pinned(self):
        for file in (WORKFLOW, ROOT / ".github/actions/cache-rust/action.yml"):
            for action in re.findall(r"uses:\s+(\S+)", file.read_text()):
                if not action.startswith("./"):
                    self.assertRegex(action, r"^[\w./-]+@[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()

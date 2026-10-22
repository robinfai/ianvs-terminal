"""Execute the real shell entrypoints with toolchain stubs, not product code."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ScriptTests(unittest.TestCase):
    def fixture(self, script, fail_command=""):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        for directory in ("tools", "bin", "native/core", "native/completion_core",
                          "native/vendor/par-term-emu-core-rust", "native/vendor/zmodem2",
                          "packages/ianvs_pty", "packages/ianvs_terminal",
                          "packages/ianvs_terminal_core/native/core", "backend", "example/test",
                          "example/lib/features/shell"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tools" / script, root / "tools" / script)
        for helper in ("build_core.sh", "verify_generated_contracts.sh"):
            path = root / "tools" / helper
            path.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            path.chmod(0o755)
        (root / "example/lib/features/shell/shell_screen_command_menu.dart").write_text(
            "title: context.l10n.defaultsAppearance\n", encoding="utf-8"
        )
        log = root / "commands.log"
        uname = "Darwin" if script == "verify_macos_app.sh" else "Linux"
        stub = """#!/usr/bin/env bash
set -eu
command_name="${0##*/}"
printf '%s | %s | %s\\n' "$PWD" "$command_name" "$*" >> LOG_PATH
if [[ "$command_name $*" == FAIL_COMMAND ]]; then exit 17; fi
case "$command_name" in
  rustup) echo thumbv7em-none-eabihf ;;
  uname) echo UNAME_VALUE ;;
  lipo) if [[ "$1" == -archs ]]; then echo arm64; fi ;;
  codesign)
    if [[ "$*" == *--verbose=4* ]]; then echo 'flags=0x10000(runtime) Signature=adhoc' >&2; fi
    if [[ "$*" == *--entitlements* ]]; then echo '<plist><dict/></plist>'; fi
    ;;
  plutil)
    if [[ "$1" == -convert ]]; then echo '{}'; fi
    if [[ "$1" == -extract ]]; then echo false; fi
    ;;
  mktemp)
    if [[ "$1" == /private/tmp/* ]]; then
      /usr/bin/mktemp ENTITLEMENTS_TEMPLATE
    else
      /usr/bin/mktemp "$@"
    fi
    ;;
esac
exit 0
""".replace("LOG_PATH", shlex.quote(str(log))).replace("FAIL_COMMAND", shlex.quote(fail_command))
        stub = stub.replace("UNAME_VALUE", uname).replace(
            "ENTITLEMENTS_TEMPLATE", shlex.quote(str(root / "entitlements.XXXXXX"))
        )
        for name in ("rustup", "uname", "python3", "cargo", "dart", "flutter", "go", "gofmt",
                     "lipo", "codesign", "plutil", "mktemp", "xcodebuild", "xcrun"):
            target = root / "bin" / name
            target.write_text(stub, encoding="utf-8")
            target.chmod(0o755)
        env = dict(os.environ)
        env["PATH"] = str(root / "bin") + os.pathsep + env["PATH"]
        # A developer's local verification overrides must not affect the fixture.
        for key in list(env):
            if key.startswith("VERIFY_"):
                del env[key]
        return root, log, env

    def run_script(self, root, script, env):
        return subprocess.run(["bash", str(root / "tools" / script)], env=env,
                              capture_output=True, text=True, timeout=20)

    def example_run(self, skip=None, fail_command=""):
        root, log, env = self.fixture("verify_flutter_terminal.sh", fail_command)
        for name in ("design/view_test.dart", "designated_test.dart", "newly_added/new_test.dart",
                     "benchmarks/cat_log_benchmark_test.dart", "benchmarks/mobile_scene_benchmark_test.dart"):
            path = root / "example/test" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        env["VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION"] = "1"
        if skip is not None:
            env["VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS"] = skip
        result = self.run_script(root, "verify_flutter_terminal.sh", env)
        lines = log.read_text().splitlines() if log.exists() else []
        example = [line for line in lines if line.startswith(str(root / "example") + " | flutter | test ")]
        return result, lines, example

    def test_local_default_includes_design_and_new_tests(self):
        result, _, example = self.example_run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(example), 1)
        self.assertIn("test/design/view_test.dart", example[0])
        self.assertIn("test/newly_added/new_test.dart", example[0])
        self.assertIn("test/benchmarks/mobile_scene_benchmark_test.dart", example[0])
        self.assertNotIn("cat_log_benchmark_test.dart", example[0])

    def test_ci_excludes_only_previously_verified_design_directory(self):
        result, _, example = self.example_run("1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(example), 1)
        self.assertNotIn("test/design/view_test.dart", example[0])
        self.assertIn("test/designated_test.dart", example[0])
        self.assertIn("test/newly_added/new_test.dart", example[0])
        self.assertIn("test/benchmarks/mobile_scene_benchmark_test.dart", example[0])

    def test_invalid_design_flag_fails_before_toolchain(self):
        result, lines, _ = self.example_run("yes")
        self.assertEqual(result.returncode, 64)
        self.assertEqual(lines, [])

    def test_timing_blocks_preserve_failure_status(self):
        result, _, example = self.example_run("1", "cargo fmt --check")
        self.assertEqual(result.returncode, 17, result.stdout)
        self.assertEqual(example, [])
        self.assertIn("CI phase duration:", result.stderr)

    def macos_run(self, mode=None, fail_command=""):
        root, log, env = self.fixture("verify_macos_app.sh", fail_command)
        if mode is not None:
            env["VERIFY_APPLE_FULL"] = mode
        result = self.run_script(root, "verify_macos_app.sh", env)
        return result, log.read_text() if log.exists() else ""

    def test_default_macos_mode_keeps_all_four_builds_and_native_tests(self):
        result, log = self.macos_run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.count("flutter | build macos --debug"), 2)
        self.assertEqual(log.count("flutter | build macos --release"), 2)
        self.assertEqual(log.count("flutter | test -d macos"), 6)
        self.assertIn("xcodebuild | test", log)

    def test_debug_macos_mode_keeps_all_functional_and_native_tests(self):
        result, log = self.macos_run("0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.count("flutter | build macos --debug"), 1)
        self.assertNotIn("flutter | build macos --release", log)
        self.assertEqual(log.count("flutter | test -d macos"), 6)
        self.assertIn("codesign | --verify --deep --strict", log)
        self.assertIn("xcodebuild | test", log)

    def test_macos_functional_failure_still_blocks_debug_mode(self):
        result, log = self.macos_run("0", "flutter test -d macos integration_test/real_pty_acceptance_test.dart")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn("xcodebuild | test", log)

    def test_invalid_apple_mode_fails(self):
        result, log = self.macos_run("false")
        self.assertEqual(result.returncode, 64)
        self.assertEqual(log, "")

    def test_ios_release_guard_does_not_guard_acceptance_or_simulator_abi(self):
        source = (ROOT / "tools/verify_ios_simulator.sh").read_text()
        before, after = source.split('if [ "$VERIFY_APPLE_FULL" = "1" ]; then', 1)
        for text in ("xcodebuild test", "integration_test/ios_sandbox_shell_acceptance_test.dart",
                     "integration_test/compact_mobile_acceptance_test.dart",
                     'verify_ios_native_exports "$IOS_APP" "$simulator_arch"', "trap cleanup EXIT"):
            self.assertIn(text, before)
        self.assertIn('VERIFY_APPLE_FULL="${VERIFY_APPLE_FULL:-1}"', before)
        self.assertIn('"${apple_build_env[@]}" flutter build ios --release --no-codesign', after)
        self.assertIn('verify_ios_native_exports "$IOS_RELEASE_APP" arm64', after)


if __name__ == "__main__":
    unittest.main()

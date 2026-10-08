"""Local contract tests: every Flutter/Xcode/codesign invocation is a fake."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("build_ios_fixture.sh")
TEAM = "PRDTEAM123"
PROFILE = "12345678-1234-1234-1234-123456789abc"
GENERATED = (
    "ios/Flutter/Generated.xcconfig",
    "ios/Flutter/flutter_export_environment.sh",
    "ios/Flutter/ephemeral/flutter_native_integration.env",
)

FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, sys
directory = pathlib.Path(__file__).parent
plan = json.loads((directory / 'plan.json').read_text())
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
config_path = pathlib.Path(os.environ['XCODE_XCCONFIG_FILE'])
settings = {}
for line in config_path.read_text().splitlines():
    key, value = line.split('=', 1)
    settings[key.strip()] = value.strip().strip('"')
entitlements_path = pathlib.Path(settings['CODE_SIGN_ENTITLEMENTS'])
entry = {'tool': name, 'args': args, 'cwd': os.getcwd(),
         'environment_keys': list(os.environ), 'settings': settings,
         'config_path': str(config_path),
         'entitlements': plistlib.loads(entitlements_path.read_bytes()),
         'config_mode': config_path.stat().st_mode & 0o777}
if name == 'flutter':
    fixture = pathlib.Path(next(x.split('=', 1)[1] for x in args if x.startswith('--dart-define-from-file=')))
    entry['fixture_path'] = str(fixture)
    entry['fixture_sha256'] = __import__('hashlib').sha256(fixture.read_bytes()).hexdigest()
    for path in ('ios/Flutter/Generated.xcconfig', 'ios/Flutter/flutter_export_environment.sh',
                 'ios/Flutter/ephemeral/flutter_native_integration.env'):
        path = pathlib.Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('DART_DEFINES=temporary-fixture-content\n')
    if plan.get('echo_fixture'):
        print(fixture.read_text())
if name == 'xcodebuild':
    products = pathlib.Path(next(x.split('=', 1)[1] for x in args if x.startswith('CONFIGURATION_BUILD_DIR=')))
    app = products / 'Runner.app'
    app.mkdir(parents=True)
    (app / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': plan.get('bundle', settings['PRODUCT_BUNDLE_IDENTIFIER']),
        'CFBundleExecutable': 'Runner', 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
    }))
    (app / 'Runner').write_bytes(b'fake-built-binary')
if name == 'codesign' and '--display' in args:
    group = 'PRDTEAM123.work.ianvs.trail.mobileprd'
    signed = {'application-identifier': group, 'keychain-access-groups': [group]}
    if plan.get('shared_group'):
        signed['keychain-access-groups'].append('PRDTEAM123.work.ianvs.trail')
    if plan.get('wrong_group'):
        signed['keychain-access-groups'] = ['PRDTEAM123.work.ianvs.trail']
    if plan.get('wrong_identifier'):
        signed['application-identifier'] = 'PRDTEAM123.work.ianvs.trail'
    if plan.get('app_group'):
        signed['com.apple.security.application-groups'] = ['group.production']
    sys.stdout.buffer.write(plistlib.dumps(signed))
with (directory / 'calls.jsonl').open('a') as output:
    output.write(json.dumps(entry) + '\n')
sys.exit(plan.get(name + '_exit', 0))
'''


class IosFixtureBuildTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mobile-prd-build-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout with spaces"
        self.example = self.root / "example"
        self.tools = self.root / "tools/mobile_prd"
        self.tools.mkdir(parents=True)
        self.script = self.tools / SCRIPT.name
        shutil.copy2(SCRIPT, self.script)
        target = self.example / "integration_test/mobile_prd_acceptance_test.dart"
        target.parent.mkdir(parents=True)
        target.write_text("void main() {}\n")
        self.original_generated = {}
        for relative in GENERATED[:2]:
            path = self.example / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            data = ("original " + relative).encode()
            path.write_bytes(data)
            path.chmod(0o640)
            self.original_generated[relative] = data
        self.bin = self.root / "fake-bin"
        self.bin.mkdir()
        for name in ("flutter", "xcodebuild", "codesign"):
            path = self.bin / name
            path.write_text(FAKE_TOOL)
            path.chmod(0o700)
        self.set_plan()
        self.fixture = self.root / "fixture.json"
        self.definitions = {
            "TRAIL_MOBILE_PRD_FIXTURE": json.dumps({
                "runId": "test-run", "ssh": {"password": "PUBLIC_FIXTURE_ONLY"},
                "modelBaseUrl": "http://127.0.0.1:1/v1",
                "evidenceBaseUrl": "http://127.0.0.1:1",
            }),
            "TRAIL_MOBILE_PRD_CASE": "flow",
        }
        self.fixture.write_text(json.dumps(self.definitions))
        self.environment = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "FLUTTER": str(self.bin / "flutter"),
            "XCODEBUILD": str(self.bin / "xcodebuild"),
            "CODESIGN": str(self.bin / "codesign"),
            "PYTHON": shutil.which("python3"),
            "SHOULD_NOT_REACH_BUILDER": "private-environment-value",
            "XCODE_XCCONFIG_FILE": "/do-not-use/caller-production.xcconfig",
            "IANVS_IOS_BUNDLE_ID": "work.ianvs.trail",
        }

    def set_plan(self, **values):
        (self.bin / "plan.json").write_text(json.dumps(values))

    def run_build(self, platform="simulator", mode="debug", extra=(), signed=True):
        args = ["--platform", platform, "--mode", mode, "--fixture", str(self.fixture)]
        if platform == "physical" and signed:
            args.extend(["--team", "PRDTEAM123", "--profile", PROFILE])
        return subprocess.run(
            ["/bin/bash", str(self.script), *args, *extra],
            cwd=self.root, env=self.environment, capture_output=True, text=True, timeout=20,
        )

    def calls(self):
        path = self.bin / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_cleaned(self):
        temporary = self.root / "build/tmp/mobile-prd-ios"
        if temporary.exists():
            self.assertEqual(list(temporary.iterdir()), [])
        for relative, data in self.original_generated.items():
            path = self.example / relative
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.example / GENERATED[2]).exists())

    def metadata(self):
        paths = list((self.root / "build/mobile-prd-v1.1/ios").glob("*/build-metadata.json"))
        self.assertEqual(len(paths), 1)
        return paths[0], json.loads(paths[0].read_text())

    def assert_success(self, result, platform, mode):
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual([c["tool"] for c in calls], ["flutter", "xcodebuild"] +
                         (["codesign", "codesign"] if platform == "physical" else []))
        flutter, xcode = calls[:2]
        for expected in ("--" + mode, "--config-only", "--no-codesign", "--no-pub",
                         "--target=integration_test/mobile_prd_acceptance_test.dart"):
            self.assertIn(expected, flutter["args"])
        self.assertEqual("--simulator" in flutter["args"], platform == "simulator")
        self.assertNotEqual(flutter["fixture_path"], str(self.fixture))
        self.assertFalse(Path(flutter["fixture_path"]).exists())
        self.assertEqual(flutter["fixture_sha256"], hashlib.sha256(self.fixture.read_bytes()).hexdigest())
        for call in calls:
            self.assertNotIn("SHOULD_NOT_REACH_BUILDER", call["environment_keys"])
            self.assertNotIn("IANVS_IOS_BUNDLE_ID", call["environment_keys"])
            self.assertEqual(call["settings"]["PRODUCT_BUNDLE_IDENTIFIER"], "work.ianvs.trail.mobileprd")
            self.assertEqual(call["entitlements"], {"keychain-access-groups": [
                "$(AppIdentifierPrefix)work.ianvs.trail.mobileprd"]})
            self.assertEqual(call["config_mode"], 0o600)
            self.assertIn("/build/tmp/mobile-prd-ios/run.", call["config_path"])
            self.assertFalse(Path(call["config_path"]).exists())
        self.assertIn(mode.title(), xcode["args"])
        self.assertIn("iphonesimulator" if platform == "simulator" else "iphoneos", xcode["args"])
        self.assertFalse(any("allowProvisioning" in value for value in xcode["args"]))
        self.assertEqual(xcode["args"][-1], "build")
        path, metadata = self.metadata()
        self.assertEqual(metadata["build_mode"], mode)
        self.assertEqual(metadata["build_platform"], platform)
        self.assertEqual(metadata["signed_keychain_isolation_verified"], platform == "physical")
        self.assertFalse(metadata["installed"])
        self.assertFalse(metadata["device_validated"])
        self.assertFalse(metadata["acceptance_passed"])
        self.assertEqual(metadata["binary_sha256"], hashlib.sha256(b"fake-built-binary").hexdigest())
        self.assertNotIn("PUBLIC_FIXTURE_ONLY", result.stdout + result.stderr + path.read_text())
        self.assertNotIn(PROFILE, path.read_text())
        self.assertNotIn("PRDTEAM123", path.read_text())
        self.assertTrue((path.parent / "Products/Runner.app/Runner").exists())
        self.assert_cleaned()

    def test_simulator_debug_has_isolated_config_and_restores_generated_files(self):
        self.assert_success(self.run_build(), "simulator", "debug")

    def test_physical_debug_verifies_unique_signed_keychain_group(self):
        self.assert_success(self.run_build("physical", "debug"), "physical", "debug")

    def test_physical_profile_does_not_enable_account_or_device_registration(self):
        self.assert_success(self.run_build("physical", "profile"), "physical", "profile")

    def test_physical_release_remains_separate_from_production(self):
        self.assert_success(self.run_build("physical", "release"), "physical", "release")

    def test_unsupported_simulator_modes_fail_without_fallback(self):
        for mode in ("profile", "release"):
            with self.subTest(mode=mode):
                result = self.run_build(mode=mode)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(self.calls(), [])
                self.assert_cleaned()

    def test_physical_requires_explicit_existing_signing_parameters(self):
        result = self.run_build("physical", signed=False)
        self.assertEqual(result.returncode, 64)
        self.assertEqual(self.calls(), [])
        self.assert_cleaned()

    def test_invalid_fixture_never_reaches_build_tools_or_leaks_content(self):
        for value in ([], {}, {"TRAIL_MOBILE_PRD_FIXTURE": "PRIVATE_INVALID_JSON"},
                      {"TRAIL_MOBILE_PRD_FIXTURE": json.dumps({"runId": "PRIVATE_MARKER"})}):
            with self.subTest(value=type(value).__name__):
                self.fixture.write_text(json.dumps(value))
                result = self.run_build()
                self.assertEqual(result.returncode, 64)
                self.assertNotIn("PRIVATE", result.stdout + result.stderr)
                self.assertEqual(self.calls(), [])
                self.assert_cleaned()

    def test_entrypoint_and_fixture_are_required(self):
        self.fixture.unlink()
        self.assertEqual(self.run_build().returncode, 64)
        self.fixture.write_text(json.dumps(self.definitions))
        (self.example / "integration_test/mobile_prd_acceptance_test.dart").unlink()
        self.assertEqual(self.run_build().returncode, 64)
        self.assertEqual(self.calls(), [])

    def test_unknown_override_cannot_select_production_bundle(self):
        result = self.run_build(extra=("--bundle", "work.ianvs.trail"))
        self.assertEqual(result.returncode, 64)
        self.assertEqual(self.calls(), [])

    def test_existing_build_lock_is_preserved(self):
        lock = self.root / "build/tmp/mobile-prd-ios/build.lock"
        lock.mkdir(parents=True)
        result = self.run_build()
        self.assertEqual(result.returncode, 64)
        self.assertTrue(lock.exists())
        self.assertEqual(self.calls(), [])

    def test_flutter_failure_keeps_private_log_but_cleans_fixture_and_config(self):
        self.set_plan(flutter_exit=17, echo_fixture=True)
        result = self.run_build()
        self.assertEqual(result.returncode, 17)
        self.assertNotIn("PUBLIC_FIXTURE_ONLY", result.stdout + result.stderr)
        logs = list((self.root / "build/mobile-prd-v1.1/ios").glob("*/build.private.log"))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)
        self.assertEqual([c["tool"] for c in self.calls()], ["flutter"])
        self.assert_cleaned()

    def test_xcode_failure_removes_partial_app_and_restores_generated_files(self):
        self.set_plan(xcodebuild_exit=23)
        result = self.run_build("physical")
        self.assertEqual(result.returncode, 23)
        self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/Products")))
        self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/build-metadata.json")))
        self.assert_cleaned()

    def test_signature_failure_cannot_publish_a_successful_artifact(self):
        self.set_plan(codesign_exit=31)
        result = self.run_build("physical")
        self.assertEqual(result.returncode, 31)
        self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/Products")))
        self.assert_cleaned()

    def test_built_bundle_must_match_fixture_identity(self):
        self.set_plan(bundle="work.ianvs.trail")
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/Products")))
        self.assert_cleaned()

    def test_signed_group_or_app_group_mismatch_fails_closed(self):
        for key in ("shared_group", "wrong_group", "wrong_identifier", "app_group"):
            with self.subTest(key=key):
                self.set_plan(**{key: True})
                result = self.run_build("physical")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/Products")))
                self.assertFalse(list((self.root / "build/mobile-prd-v1.1/ios").glob("*/build-metadata.json")))
                self.assert_cleaned()


if __name__ == "__main__":
    unittest.main()

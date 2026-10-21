"""Policy and real-git regressions; requires only Python and git."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from apple_verification_scope import changed_paths, choose, classify


class PolicyTests(unittest.TestCase):
    def test_documentation_skips_only_apple_jobs(self):
        for platform in ("macos", "ios"):
            self.assertEqual(classify(["README.md", "docs/ci.md"], platform), "skip")

    def test_shared_ui_and_acceptance_keep_debug_integration(self):
        for path in ("example/lib/mobile.dart", "example/test/design/view_test.dart",
                     "example/integration_test/compact_mobile_acceptance_test.dart",
                     "example/test_driver/driver.dart", "example/test_http/client_test.dart",
                     "backend/internal/api.go"):
            for platform in ("macos", "ios"):
                with self.subTest(path=path, platform=platform):
                    self.assertEqual(classify([path], platform), "debug")

    def test_platform_specific_changes_keep_full_native_checks(self):
        self.assertEqual(classify(["example/ios/Runner/AppDelegate.swift"], "ios"), "full")
        self.assertEqual(classify(["example/ios/Runner/AppDelegate.swift"], "macos"), "skip")
        self.assertEqual(classify(["example/macos/Runner/Info.plist"], "macos"), "full")
        self.assertEqual(classify(["example/macos/Runner/Info.plist"], "ios"), "skip")

    def test_sensitive_and_unknown_paths_are_full(self):
        for path in ("native/core/src/lib.rs", "packages/ianvs_terminal/lib/ffi.dart",
                     "tools/build_core.sh", ".github/workflows/verify.yml", "pubspec.lock",
                     "example/pubspec.yaml", "example/assets/font.ttf", "Makefile",
                     "new_component/file.txt", "docs", "docs-elsewhere/file.md",
                     "example/lib/embedded.bin", "README-other.md"):
            for platform in ("macos", "ios"):
                with self.subTest(path=path, platform=platform):
                    self.assertEqual(classify([path], platform), "full")

    def test_mixed_changes_never_downgrade_full(self):
        for paths in (["docs/ci.md", "native/core/Cargo.toml"],
                      ["example/lib/app.dart", "pubspec.lock"],
                      ["pubspec.lock", "example/lib/app.dart"]):
            self.assertEqual(classify(paths, "ios"), "full")
        self.assertEqual(classify(["example/macos/Runner/Info.plist", "example/lib/app.dart"], "ios"), "debug")

    def test_empty_diff_is_full(self):
        self.assertEqual(classify([], "macos"), "full")

    def test_non_pr_invocations_are_full(self):
        for event in ("push", "schedule", "workflow_dispatch", "", "pull_request_target"):
            self.assertEqual(choose("ios", {"GITHUB_EVENT_NAME": event})[0], "full")

    def test_missing_pr_context_is_full(self):
        self.assertEqual(choose("ios", {"GITHUB_EVENT_NAME": "pull_request"})[0], "full")

    def test_diff_errors_are_full(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "event.json"
            path.write_text("{}", encoding="utf-8")
            env = {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_EVENT_PATH": str(path)}
            for error in (ValueError("bad parents"), OSError("no git"),
                          subprocess.CalledProcessError(128, "git"),
                          subprocess.TimeoutExpired("git", 30)):
                with patch("apple_verification_scope.changed_paths", side_effect=error):
                    self.assertEqual(choose("ios", env)[0], "full")
            for data in ("not json", "null", "[]", "{}"):
                path.write_text(data, encoding="utf-8")
                self.assertEqual(choose("ios", env)[0], "full")

    def test_invalid_platform_rejected(self):
        with self.assertRaises(ValueError):
            classify(["README.md"], "android")


class GitDiffTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name) / "source"
        self.repo.mkdir()
        self.run_git("init", "-q", "-b", "main")
        self.run_git("config", "user.name", "CI test")
        self.run_git("config", "user.email", "ci@example.invalid")
        (self.repo / "native").mkdir()
        (self.repo / "native/file.md").write_text("fixture\n", encoding="utf-8")
        self.run_git("add", ".")
        self.run_git("commit", "-qm", "base")
        self.base = self.run_git("rev-parse", "HEAD").strip()
        self.run_git("checkout", "-qb", "feature")
        (self.repo / "docs").mkdir()
        self.run_git("mv", "native/file.md", "docs/moved.md")
        (self.repo / "docs/with space\nand newline.md").write_text("fixture\n", encoding="utf-8")
        self.run_git("add", ".")
        self.run_git("commit", "-qm", "move")
        self.head = self.run_git("rev-parse", "HEAD").strip()
        self.run_git("checkout", "-q", "main")
        self.run_git("merge", "--no-ff", "-qm", "merge", "feature")
        self.event = {"pull_request": {"base": {"sha": self.base}, "head": {"sha": self.head}}}

    def run_git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, stderr=subprocess.PIPE).decode()

    def test_renames_preserve_source_and_destination_and_newlines(self):
        paths = changed_paths(self.repo, self.event)
        self.assertEqual(set(paths), {"native/file.md", "docs/moved.md", "docs/with space\nand newline.md"})
        self.assertEqual(classify(paths, "ios"), "full")

    def test_depth_two_checkout_has_sufficient_history(self):
        clone = Path(self.directory.name) / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth=2", self.repo.as_uri(), str(clone)], check=True)
        self.assertEqual(changed_paths(clone, self.event), changed_paths(self.repo, self.event))

    def test_unexpected_parent_rejected(self):
        self.event["pull_request"]["base"]["sha"] = "0" * 40
        with self.assertRaises(ValueError):
            changed_paths(self.repo, self.event)

    def test_non_merge_checkout_rejected(self):
        self.run_git("checkout", "-q", "feature")
        with self.assertRaises(subprocess.CalledProcessError):
            changed_paths(self.repo, self.event)

    def test_end_to_end_pr_selection(self):
        path = Path(self.directory.name) / "event.json"
        path.write_text(json.dumps(self.event), encoding="utf-8")
        env = {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_EVENT_PATH": str(path)}
        self.assertEqual(choose("ios", env, self.repo)[0], "full")


if __name__ == "__main__":
    unittest.main()

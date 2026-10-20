"""Launcher contracts without executing Flutter, a shell, or a native app."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "desktop_prd_run_manual", Path(__file__).with_name("run_manual.py"),
)
LAUNCHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LAUNCHER)


class ManualLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="desktop-prd-launcher-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def mark(self, root):
        (root / LAUNCHER.MARKER).write_text(json.dumps({
            "schema_version": 1,
            "purpose": "trail-desktop-prd-manual",
            "root": str(root),
        }))

    def test_empty_new_or_own_fixture_only(self):
        self.assertEqual(LAUNCHER.checked_fixture_root(self.root), self.root)
        sentinel = self.root / "user-settings.json"
        sentinel.write_text("keep")
        with self.assertRaises(ValueError):
            LAUNCHER.checked_fixture_root(self.root)
        self.assertEqual(sentinel.read_text(), "keep")
        self.mark(self.root)
        self.assertEqual(LAUNCHER.checked_fixture_root(self.root), self.root)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_link_or_copied_marker_does_not_adopt_another_directory(self):
        marked = self.root / "marked"
        marked.mkdir()
        self.mark(marked)
        alias = self.root / "alias"
        alias.symlink_to(marked, target_is_directory=True)
        with self.assertRaises(ValueError):
            LAUNCHER.checked_fixture_root(alias)
        copied = self.root / "copied"
        copied.mkdir()
        (copied / LAUNCHER.MARKER).write_bytes((marked / LAUNCHER.MARKER).read_bytes())
        with self.assertRaises(ValueError):
            LAUNCHER.checked_fixture_root(copied)

    def test_allowlist_keeps_auth_loader_home_without_secrets_or_injection(self):
        source = {
            "HOME": "/Users/tester", "USER": "tester", "LANG": "en_US.UTF-8",
            "OPENAI_API_KEY": "not-a-real-key", "DEEPSEEK_API_KEY": "not-a-real-key",
            "SSH_AUTH_SOCK": "/private/agent.sock", "CODEX_HOME": "/private/auth",
            "DYLD_INSERT_LIBRARIES": "/private/injected", "ZDOTDIR": "/private/user-zsh",
            "PATH": "/private/inherited-path", "TRAIL_OTHER": "injected",
        }
        environment = LAUNCHER.launch_environment(source, "/sdk/flutter/bin/flutter")
        self.assertEqual(set(environment), {"HOME", "USER", "LANG", "PATH"})
        self.assertEqual(environment["HOME"], source["HOME"])
        self.assertNotIn("/private", environment["PATH"])
        self.assertIn("/sdk/flutter/bin", environment["PATH"])

    def test_launcher_uses_exact_target_and_preserves_argument_boundaries(self):
        root = self.root / "spaces and $(not-a-command)"
        flutter = self.root / "flutter"
        flutter.write_text("not executed")
        flutter.chmod(0o700)
        with patch.object(LAUNCHER.subprocess, "run") as run:
            run.return_value.returncode = 7
            with patch.object(LAUNCHER.os, "environ", {
                "HOME": "/Users/tester", "OPENAI_API_KEY": "not-a-real-key",
            }):
                code = LAUNCHER.main(["--flutter", str(flutter), "--fixture-dir", str(root)])
        self.assertEqual(code, 7)
        command = run.call_args.args[0]
        self.assertIn("tool/desktop_prd_acceptance.dart", command)
        self.assertIn(f"--dart-define=TRAIL_DESKTOP_PRD_DIRECTORY={root}", command)
        self.assertIn("--dart-define=TRAIL_UI_NATIVE_KEYBOARD=true", command)
        self.assertNotIn("OPENAI_API_KEY", run.call_args.kwargs["env"])
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_unrelated_nonempty_root_rejected_before_starting_flutter(self):
        (self.root / "production-settings").write_text("keep")
        with patch.object(LAUNCHER.subprocess, "run") as run:
            with self.assertRaises(SystemExit) as error:
                LAUNCHER.main(["--flutter", "/bin/echo", "--fixture-dir", str(self.root)])
        self.assertEqual(error.exception.code, 2)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()

"""Exercise release authentication before any expensive build can start."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('build_macos_release.sh')


class NotaryPreflightTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.log = self.root / 'calls.json'
        stub = self.root / 'xcrun'
        stub.write_text(
            '#!/usr/bin/env python3\n'
            'import json, os, sys\n'
            'with open(os.environ["PREFLIGHT_LOG"], "w") as output:\n'
            '    json.dump(sys.argv[1:], output)\n'
            'sys.exit(42)\n'
        )
        stub.chmod(0o755)
        self.env = {
            'PATH': str(self.root) + os.pathsep + os.environ['PATH'],
            'PREFLIGHT_LOG': str(self.log),
            'MACOS_SIGNING_IDENTITY': 'Developer ID Application: Fixture',
            'SPARKLE_PUBLIC_KEY': 'fixture', 'SPARKLE_KEY_FILE': 'fixture',
            'RELEASE_VERSION': '0.1.0', 'RELEASE_BUILD': '1',
            'RELEASE_REPOSITORY': 'fixture/repo',
            'RELEASE_OUTPUT': str(self.root / 'output'),
            'SPARKLE_TOOLS': str(self.root),
        }

    def run_script(self):
        return subprocess.run(['bash', str(SCRIPT)], env=self.env,
                              capture_output=True, text=True)

    def test_apple_account_authentication_failure_stops_before_build(self):
        self.env.update(APPLE_ID='fixture@example.invalid', APPLE_TEAM_ID='FIXTURE',
                        APPLE_APP_SPECIFIC_PASSWORD='fixture-password')
        self.assertEqual(self.run_script().returncode, 42)
        self.assertEqual(json.loads(self.log.read_text()), [
            'notarytool', 'history', '--apple-id', 'fixture@example.invalid',
            '--team-id', 'FIXTURE', '--password', 'fixture-password',
            '--output-format', 'json',
        ])
        self.assertFalse((self.root / 'output').exists())

    def test_api_key_authentication_failure_stops_before_build(self):
        self.env.update(NOTARY_KEY_FILE='fixture.p8', NOTARY_KEY_ID='KEY',
                        NOTARY_ISSUER_ID='ISSUER')
        self.assertEqual(self.run_script().returncode, 42)
        self.assertEqual(json.loads(self.log.read_text()), [
            'notarytool', 'history', '--key', 'fixture.p8', '--key-id', 'KEY',
            '--issuer', 'ISSUER', '--output-format', 'json',
        ])
        self.assertFalse((self.root / 'output').exists())

    def test_missing_credentials_stop_without_contacting_apple(self):
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()

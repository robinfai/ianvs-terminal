import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from changed_jobs import CLIENT, JOBS, changed_paths, jobs_for_paths, main


class ChangedJobsTests(unittest.TestCase):
    def test_docs_only_keep_the_always_on_contracts_gate(self):
        self.assertEqual(jobs_for_paths(['docs/TESTING.md', 'README.md']), set())

    def test_backend_also_checks_the_embedded_macos_server(self):
        self.assertEqual(jobs_for_paths(['backend/internal/store/store.go']), {'backend', 'macos'})

    def test_native_and_packaged_sources_cover_all_client_platforms(self):
        for path in ('native/core/src/lib.rs', 'packages/ianvs_pty/hook/build.dart',
                     'packages/ianvs_terminal_core/native/core/Cargo.lock'):
            with self.subTest(path=path):
                self.assertEqual(jobs_for_paths([path]), CLIENT | {'native'})

    def test_platform_only_changes_do_not_build_the_other_app(self):
        self.assertEqual(jobs_for_paths(['example/ios/Runner/Info.plist']), {'flutter', 'ios'})
        self.assertEqual(jobs_for_paths(['example/macos/Runner/AppDelegate.swift']), {'flutter', 'macos'})

    def test_shared_helpers_and_locks_build_both_platforms(self):
        for path in ('example/test/support/fake.dart', 'pubspec.lock', 'example/lib/app.dart'):
            with self.subTest(path=path):
                self.assertEqual(jobs_for_paths([path]), CLIENT)

    def test_workflows_tools_and_unknown_paths_expand_to_full_coverage(self):
        for path in ('.github/workflows/verify.yml', 'tools/ci/changed_jobs.py',
                     'Makefile', 'new_module/config.json'):
            with self.subTest(path=path):
                self.assertEqual(jobs_for_paths([path]), JOBS)

    def test_manual_and_first_push_run_every_gate(self):
        self.assertIsNone(changed_paths('workflow_dispatch', {}))
        self.assertIsNone(changed_paths('push', {'before': '0' * 40}))

    def test_missing_base_runs_every_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            event = root / 'event.json'
            event.write_text(json.dumps({'before': 'old', 'after': 'new'}))
            env = {'GITHUB_EVENT_NAME': 'push', 'GITHUB_EVENT_PATH': str(event),
                   'GITHUB_OUTPUT': str(root / 'output'),
                   'GITHUB_STEP_SUMMARY': str(root / 'summary')}
            with patch.dict(os.environ, env), patch('changed_jobs.subprocess.check_output',
                    side_effect=subprocess.CalledProcessError(128, 'git')):
                main()
            self.assertEqual(set((root / 'output').read_text().splitlines()),
                             {f'{job}=true' for job in JOBS})

    def test_diff_includes_deletions_and_both_sides_of_renames(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'CI fixture')
            git('config', 'user.email', 'ci@example.invalid')
            (root / 'example').mkdir()
            (root / 'example/old.dart').write_text('old')
            git('add', '.')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (root / 'docs').mkdir()
            (root / 'example/old.dart').rename(root / 'docs/moved.md')
            git('add', '-A')
            git('commit', '-qm', 'rename')
            real_check_output = subprocess.check_output
            def in_repository(args, **kwargs):
                return real_check_output(args, cwd=root, **kwargs)
            with patch('changed_jobs.subprocess.check_output', side_effect=in_repository):
                paths = changed_paths('push', {'before': base, 'after': 'HEAD'})
            self.assertEqual(set(paths), {'example/old.dart', 'docs/moved.md'})
            self.assertEqual(jobs_for_paths(paths), CLIENT)


if __name__ == '__main__':
    unittest.main()

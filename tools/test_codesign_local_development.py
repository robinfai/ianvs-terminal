import unittest

from codesign_local_development import codesign_arguments


class LocalDevelopmentSigningTests(unittest.TestCase):
    def test_only_timestamp_changes_for_local_development(self):
        arguments = [
            '--force', '--sign', 'certificate hash', '--options', 'runtime',
            '--timestamp', '/App With Spaces.app/Contents/Frameworks/acp.dylib',
        ]
        actual = codesign_arguments(arguments, {
            'IANVS_LOCAL_APPLE_DEVELOPMENT_SIGNING': '1',
        })
        self.assertEqual(actual, arguments[:5] + [
            '--timestamp=none', arguments[-1],
        ])
        self.assertEqual(arguments[5], '--timestamp')

    def test_distribution_and_unmarked_calls_are_unchanged(self):
        for environment in [{}, {'IANVS_LOCAL_APPLE_DEVELOPMENT_SIGNING': '0'}]:
            arguments = ['--sign', 'Developer ID Application', '--timestamp', 'app']
            self.assertEqual(codesign_arguments(arguments, environment), arguments)

    def test_explicit_timestamps_and_verification_are_preserved(self):
        environment = {'IANVS_LOCAL_APPLE_DEVELOPMENT_SIGNING': '1'}
        for arguments in [
            ['--verify', '--deep', '--strict', 'app'],
            ['--sign', '-', '--timestamp=none', 'app'],
            ['--sign', 'identity', '--timestamp=https://tsa.example.test', 'app'],
        ]:
            self.assertEqual(codesign_arguments(arguments, environment), arguments)


if __name__ == '__main__':
    unittest.main()

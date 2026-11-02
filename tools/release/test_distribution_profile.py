import datetime
import unittest
from prepare_distribution_profile import entitlements


class DistributionProfileTest(unittest.TestCase):
    def profile(self):
        return {
            'ExpirationDate': datetime.datetime(2040, 1, 1),
            'ProvisionsAllDevices': True,
            'TeamIdentifier': ['TEAM'],
            'Entitlements': {
                'com.apple.application-identifier': 'TEAM.work.ianvs.trail',
                'com.apple.developer.team-identifier': 'TEAM',
                'keychain-access-groups': ['TEAM.*'],
            },
        }

    def test_developer_id_uses_web_login_without_native_entitlement(self):
        result = entitlements(self.profile(), 'Developer ID Application: Test (TEAM)')
        self.assertNotIn('com.apple.developer.applesignin', result)
        self.assertEqual(result['keychain-access-groups'], ['TEAM.work.ianvs.trail'])

    def test_rejects_wrong_team_app_expiry_and_keychain(self):
        for key, value in [('com.apple.application-identifier', 'TEAM.other'),
                           ('com.apple.developer.team-identifier', 'OTHER'),
                           ('keychain-access-groups', ['OTHER.*'])]:
            with self.subTest(key=key):
                profile = self.profile()
                profile['Entitlements'][key] = value
                with self.assertRaises(ValueError):
                    entitlements(profile, 'Developer ID Application: Test (TEAM)')
        with self.assertRaises(ValueError):
            entitlements(self.profile(), 'Developer ID Application: Test (OTHER)')
        profile = self.profile()
        profile['ExpirationDate'] = datetime.datetime(2000, 1, 1)
        with self.assertRaises(ValueError):
            entitlements(profile, 'Developer ID Application: Test (TEAM)')


if __name__ == '__main__':
    unittest.main()

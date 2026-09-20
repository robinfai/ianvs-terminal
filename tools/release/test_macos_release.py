import base64
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from macos_release import SPARKLE, appcast, configure, sign_app


class MacOSReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'Trail.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.plist = self.app / 'Contents/Info.plist'
        self.plist.write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'work.ianvs.trail',
            'CFBundleVersion': '669', 'CFBundleShortVersionString': '1.1.669',
            'LSMinimumSystemVersion': '10.15',
        }))
        self.key = base64.b64encode(bytes(range(32))).decode()
        self.signature = base64.b64encode(bytes(range(64))).decode()
        self.archive = self.root / 'Trail.zip'
        self.archive.write_bytes(b'fixture payload')
        self.feed = self.root / 'appcast.xml'

    def test_configure_requires_valid_update_key(self):
        for key in ('', 'not-base64', base64.b64encode(b'short').decode()):
            with self.subTest(key=key), self.assertRaises(ValueError):
                configure(self.app, key)

    def test_production_rejects_untrusted_feed_urls(self):
        for url in ('http://127.0.0.1/feed', 'file:///tmp/feed',
                    'https://user:secret@example.com/feed', 'https:///feed'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                configure(self.app, self.key, url)

    def test_production_requires_archive_and_feed_verification(self):
        configure(self.app, self.key, 'https://github.com/example/releases/latest/download/appcast.xml')
        info = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(info['SUPublicEDKey'], self.key)
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
        self.assertTrue(info['SURequireSignedFeed'])

    def test_loopback_test_build_has_a_separate_bundle_identity(self):
        configure(self.app, self.key, 'http://127.0.0.1:9123/appcast.xml', test=True)
        info = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'work.ianvs.trail.update-test')
        self.assertFalse(info['SUEnableAutomaticChecks'])

    def test_appcast_describes_exact_archive_and_build(self):
        url = 'https://github.com/example/release.zip?one=1&two=2'
        appcast(self.app, self.archive, url, self.signature, self.feed)
        item = ET.parse(self.feed).find('channel/item')
        self.assertEqual(item.find(f'{{{SPARKLE}}}version').text, '669')
        self.assertEqual(item.find(f'{{{SPARKLE}}}shortVersionString').text, '1.1.669')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'), url)
        self.assertEqual(enclosure.get('length'), str(self.archive.stat().st_size))
        self.assertEqual(enclosure.get(f'{{{SPARKLE}}}edSignature'), self.signature)

    def test_appcast_rejects_invalid_signatures_and_insecure_downloads(self):
        with self.assertRaises(ValueError):
            appcast(self.app, self.archive, 'https://example.com/a.zip', self.key, self.feed)
        with self.assertRaises(ValueError):
            appcast(self.app, self.archive, 'http://example.com/a.zip', self.signature, self.feed)

    def test_appcast_rejects_non_incrementing_build_format(self):
        info = plistlib.loads(self.plist.read_bytes())
        info['CFBundleVersion'] = 'bad-build'
        self.plist.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):
            appcast(self.app, self.archive, 'https://example.com/a.zip', self.signature, self.feed)

    def test_public_release_refuses_development_or_adhoc_signatures(self):
        for identity in ('-', 'Apple Development: Example'):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                sign_app(self.app, identity, self.root / 'unused.entitlements')


if __name__ == '__main__':
    unittest.main()

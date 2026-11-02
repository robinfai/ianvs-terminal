import tempfile
import unittest
from pathlib import Path
from advance_test_feed import advance

class TestChannelAdvance(unittest.TestCase):
    def test_advance_preserves_archive_checksum_and_rejects_regression(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            def feed(name, version, build):
                p = root / name
                p.write_text(f'<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><s:version>{build}</s:version><s:shortVersionString>{version}</s:shortVersionString></item></channel></rss>')
                return p
            old = feed('old', '0.1.0', 700)
            new = feed('new', '0.1.1', 701)
            sums = root / 'SHA256SUMS'
            archive = 'a' * 64 + '  Trail-0.1.0-macOS-universal.zip\n'
            sums.write_text(archive + 'b' * 64 + '  appcast.xml\n')
            self.assertTrue(advance(old, new, sums).startswith(archive))
            for version, build in [('0.1.0', 701), ('0.1.1', 700), ('0.2.0', 702)]:
                with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                    advance(old, feed('bad', version, build), sums)

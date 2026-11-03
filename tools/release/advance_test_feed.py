#!/usr/bin/env python3
"""Validate monotonic test-channel updates and preserve baseline archive checksums."""
import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}


def advance(old_feed, new_feed, old_checksums):
    def version(path):
        item = ET.parse(path).find('channel/item')
        name = item.find('s:shortVersionString', NS).text
        if not re.fullmatch(r'0\.1\.(0|[1-9][0-9]*)', name):
            raise ValueError('Test channel only accepts 0.1.x releases')
        return tuple(map(int, name.split('.'))), int(item.find('s:version', NS).text)
    old, old_build = version(old_feed)
    new, new_build = version(new_feed)
    if new <= old or new_build <= old_build:
        raise ValueError('Both version and build must advance')
    import hashlib
    lines = old_checksums.read_text().splitlines()
    archives = [line for line in lines if line.endswith('  Trail-0.1.0-macOS-universal.zip')]
    if len(archives) != 1 or not re.fullmatch(r'[a-f0-9]{64}  Trail-0\.1\.0-macOS-universal\.zip', archives[0]):
        raise ValueError('Missing baseline archive checksum')
    images = [line for line in lines if line.endswith('  Trail-0.1.0-macOS-universal.dmg')]
    if len(images) > 1 or (images and not re.fullmatch(r'[a-f0-9]{64}  Trail-0\.1\.0-macOS-universal\.dmg', images[0])):
        raise ValueError('Invalid baseline disk image checksum')
    return '\n'.join(archives + images) + '\n' + hashlib.sha256(new_feed.read_bytes()).hexdigest() + '  appcast.xml\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('old_feed', 'new_feed', 'old_checksums', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    args.output.write_text(advance(args.old_feed, args.new_feed, args.old_checksums))

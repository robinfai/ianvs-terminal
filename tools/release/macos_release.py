#!/usr/bin/env python3
"""Small, validated helpers shared by release CI and local update acceptance."""
import argparse
import base64
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def validate_key(key):
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError('Sparkle public key must decode to 32 bytes')


def configure(app, key, feed=None, test=False):
    validate_key(key)
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    if test:
        info['CFBundleIdentifier'] = 'work.ianvs.trail.update-test'
        info['CFBundleName'] = 'Trail Update Test'
        info['SUEnableAutomaticChecks'] = False
        info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
    elif info['CFBundleIdentifier'] != 'work.ianvs.trail':
        raise ValueError('Unexpected production bundle identifier')
    info['SUPublicEDKey'] = key
    if feed:
        parsed = urlparse(feed)
        if parsed.username or parsed.password or parsed.fragment or not parsed.hostname:
            raise ValueError('Invalid feed URL')
        if parsed.scheme != 'https' and not (
            test and parsed.scheme == 'http' and parsed.hostname == '127.0.0.1'
        ):
            raise ValueError('Production update feeds require HTTPS')
        info['SUFeedURL'] = feed
    info['SUVerifyUpdateBeforeExtraction'] = True
    info['SURequireSignedFeed'] = True
    path.write_bytes(plistlib.dumps(info))


def appcast(app, archive, url, signature, output, test=False):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    build = str(info['CFBundleVersion'])
    version = str(info['CFBundleShortVersionString'])
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Build number must be a positive integer')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Version must be major.minor.patch')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('EdDSA signature must decode to 64 bytes')
    parsed = urlparse(url)
    if parsed.username or parsed.password or parsed.fragment or not parsed.hostname:
        raise ValueError('Invalid download URL')
    if parsed.scheme != 'https' and not (
        test and parsed.scheme == 'http' and parsed.hostname == '127.0.0.1'
    ):
        raise ValueError('Production downloads require HTTPS')
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Trail Updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'Trail ' + version
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = build
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'description').text = (
        'This update includes the latest changes merged into main. '
        'Installing restarts Trail and closes active terminal sessions.'
    )
    ET.SubElement(item, 'enclosure', {
        'url': url, 'length': str(archive.stat().st_size),
        'type': 'application/octet-stream', f'{{{SPARKLE}}}edSignature': signature,
    })
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)


def sign_app(app, identity, entitlements, test=False):
    if not test and not identity.startswith('Developer ID Application:'):
        raise ValueError('Public releases require a Developer ID Application identity')
    options = ['--force', '--options', 'runtime', '--sign', identity]
    options += ['--timestamp=none'] if test else ['--timestamp']
    # Sign nested Mach-O executables and bundles inside-out, never --deep sign.
    paths = sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True)
    for path in paths:
        if path.is_symlink():
            continue
        is_bundle = path.is_dir() and path.suffix in ('.framework', '.app', '.xpc')
        is_macho = False
        if path.is_file():
            with path.open('rb') as binary:
                is_macho = binary.read(4) in (
                    b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                    b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
                    b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                    b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca',
                )
        if is_bundle or is_macho:
            subprocess.run(['codesign', *options, str(path)], check=True)
    subprocess.run(['codesign', *options, '--entitlements', str(entitlements), str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    config = sub.add_parser('configure')
    config.add_argument('app', type=Path)
    config.add_argument('--public-key', required=True)
    config.add_argument('--feed')
    config.add_argument('--test', action='store_true')
    feed = sub.add_parser('appcast')
    for name in ('app', 'archive', 'output'):
        feed.add_argument(name, type=Path)
    feed.add_argument('--url', required=True)
    feed.add_argument('--signature', required=True)
    feed.add_argument('--test', action='store_true')
    sign = sub.add_parser('sign')
    sign.add_argument('app', type=Path)
    sign.add_argument('--identity', required=True)
    sign.add_argument('--entitlements', required=True, type=Path)
    sign.add_argument('--test', action='store_true')
    args = parser.parse_args()
    if args.command == 'configure':
        configure(args.app, args.public_key, args.feed, args.test)
    elif args.command == 'appcast':
        appcast(args.app, args.archive, args.url, args.signature, args.output, args.test)
    else:
        sign_app(args.app, args.identity, args.entitlements, args.test)


if __name__ == '__main__':
    main()

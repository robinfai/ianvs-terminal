#!/usr/bin/env python3
"""Validate the Developer ID authorization and produce explicit app entitlements."""
import argparse
import datetime
import fnmatch
import plistlib
from pathlib import Path


def entitlements(profile, identity, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
    if expiry <= now or profile.get('ProvisionsAllDevices') is not True:
        raise ValueError('An unexpired Developer ID profile for all devices is required')
    teams = profile.get('TeamIdentifier', [])
    if len(teams) != 1 or not identity.endswith('(' + teams[0] + ')'):
        raise ValueError('Profile and signing certificate teams differ')
    team = teams[0]
    app_id = team + '.work.ianvs.trail'
    allowed = profile['Entitlements']
    if allowed.get('com.apple.application-identifier') != app_id:
        raise ValueError('Profile must authorize exactly work.ianvs.trail')
    if allowed.get('com.apple.developer.team-identifier') != team:
        raise ValueError('Invalid profile team entitlement')
    # Developer ID does not support native Apple sign-in. The app uses web OAuth.
    if not any(fnmatch.fnmatchcase(app_id, pattern) for pattern in allowed.get('keychain-access-groups', [])):
        raise ValueError('Profile must authorize the Trail Keychain group')
    return {
        'com.apple.application-identifier': app_id,
        'com.apple.developer.team-identifier': team,
        'keychain-access-groups': [app_id],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('profile', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--identity', required=True)
    args = parser.parse_args()
    args.output.write_bytes(plistlib.dumps(entitlements(plistlib.loads(args.profile.read_bytes()), args.identity)))

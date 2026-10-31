#!/usr/bin/env python3
"""Adapt ACP's timestamp request only for the local Apple Development build."""

import os
import sys


def codesign_arguments(arguments, environment):
    if environment.get('IANVS_LOCAL_APPLE_DEVELOPMENT_SIGNING') != '1':
        return list(arguments)
    # Do not change identity, runtime options, entitlements or verification.
    return [
        '--timestamp=none' if argument == '--timestamp' else argument
        for argument in arguments
    ]


if __name__ == '__main__':
    os.execv('/usr/bin/codesign', [
        '/usr/bin/codesign', *codesign_arguments(sys.argv[1:], os.environ),
    ])

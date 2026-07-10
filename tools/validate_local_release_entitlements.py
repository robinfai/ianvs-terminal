#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path


LIBRARY_VALIDATION_KEY = "com.apple.security.cs.disable-library-validation"


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: validate_local_release_entitlements.py <plist-or->",
            file=sys.stderr,
        )
        return 64

    source = sys.argv[1]
    try:
        if source == "-":
            entitlements = plistlib.loads(sys.stdin.buffer.read())
        else:
            with Path(source).open("rb") as stream:
                entitlements = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f"invalid local release entitlements: {error}", file=sys.stderr)
        return 1

    is_exact = (
        isinstance(entitlements, dict)
        and set(entitlements) == {LIBRARY_VALIDATION_KEY}
        and entitlements[LIBRARY_VALIDATION_KEY] is True
    )
    if not is_exact:
        print(
            "local release entitlements must contain only "
            "com.apple.security.cs.disable-library-validation=true",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

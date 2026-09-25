#!/usr/bin/env python3
"""Check every macOS dylib slice's string pool, then load the host slice."""

from __future__ import annotations

import argparse
import ctypes
import re
import subprocess
from pathlib import Path


def xcrun(*arguments: str) -> str:
    result = subprocess.run(
        ["xcrun", *arguments], capture_output=True, text=True, check=True
    )
    return result.stdout


def verify_library(library: Path) -> None:
    library = library.resolve(strict=True)
    architectures = xcrun("lipo", "-archs", str(library)).split()
    if not architectures:
        raise ValueError(f"No Mach-O architectures found: {library}")
    for architecture in architectures:
        commands = xcrun("otool", "-arch", architecture, "-l", str(library))
        offsets = re.findall(r"^\s*stroff\s+(\d+)\s*$", commands, re.MULTILINE)
        if len(offsets) != 1:
            raise ValueError(f"Missing or ambiguous LC_SYMTAB: {architecture}: {library}")
        offset = int(offsets[0])
        if offset % 8:
            raise ValueError(
                f"Misaligned LINKEDIT string pool: {architecture}: "
                f"stroff=0x{offset:08X} must be 8-byte aligned: {library}"
            )
    # Symbol and signature checks alone do not exercise dyld's validation.
    # Foreign slices are checked structurally above; dlopen tests the host slice.
    ctypes.CDLL(str(library))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    arguments = parser.parse_args()
    try:
        verify_library(arguments.library)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"macOS native library verification failed: {error}\n")
    print(f"Verified Mach-O alignment and host dlopen: {arguments.library}")


if __name__ == "__main__":
    main()

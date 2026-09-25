#!/usr/bin/env python3
"""Exercise the release gate against real universal Mach-O fixtures."""

import ctypes
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_macos_native_library import verify_library


@unittest.skipUnless(sys.platform == "darwin", "requires the macOS toolchain")
class NativeLibraryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="ianvs-macho-test-")
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        source = cls.root / "fixture.c"
        source.write_text("int answer(void) { return 42; }\n")
        cls.library = cls.root / "fixture.dylib"
        subprocess.run(
            [
                "xcrun", "clang", "-dynamiclib", "-arch", "arm64",
                "-arch", "x86_64", str(source), "-o", str(cls.library),
            ],
            check=True, capture_output=True,
        )

    def test_loads_valid_universal_library(self):
        verify_library(self.library)
        self.assertEqual(ctypes.CDLL(str(self.library)).answer(), 42)

    def test_rejects_misaligned_string_pool_in_either_slice(self):
        original = self.library.read_bytes()
        magic, count = struct.unpack_from(">II", original)
        self.assertEqual(magic, 0xCAFEBABE)
        self.assertEqual(count, 2)
        for index in range(count):
            with self.subTest(slice=index):
                data = bytearray(original)
                # fat_arch.offset -> mach_header_64 -> LC_SYMTAB.stroff.
                slice_offset = struct.unpack_from(">I", data, 8 + index * 20 + 8)[0]
                ncmds = struct.unpack_from("<I", data, slice_offset + 16)[0]
                command = slice_offset + 32
                for _ in range(ncmds):
                    kind, size = struct.unpack_from("<II", data, command)
                    if kind == 2:  # LC_SYMTAB
                        offset = struct.unpack_from("<I", data, command + 16)[0]
                        self.assertEqual(offset % 8, 0)
                        struct.pack_into("<I", data, command + 16, offset + 4)
                        break
                    command += size
                else:
                    self.fail("fixture has no LC_SYMTAB")
                broken = self.root / f"misaligned-{index}.dylib"
                broken.write_bytes(data)
                with patch("verify_macos_native_library.ctypes.CDLL") as load:
                    with self.assertRaisesRegex(ValueError, "Misaligned LINKEDIT"):
                        verify_library(broken)
                    load.assert_not_called()

    def test_does_not_accept_alignment_when_dlopen_fails(self):
        with patch(
            "verify_macos_native_library.ctypes.CDLL",
            side_effect=OSError("Library not loaded: missing dependency"),
        ) as load:
            with self.assertRaisesRegex(OSError, "missing dependency"):
                verify_library(self.library)
            load.assert_called_once()

    def test_rejects_non_macho_input(self):
        invalid = self.root / "invalid.dylib"
        invalid.write_text("not a Mach-O binary")
        with self.assertRaises(subprocess.CalledProcessError):
            verify_library(invalid)


if __name__ == "__main__":
    unittest.main()

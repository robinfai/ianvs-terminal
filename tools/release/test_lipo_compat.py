#!/usr/bin/env python3
"""Verify the Xcode 27 adapter against real Mach-O files."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


@unittest.skipUnless(sys.platform == "darwin", "requires the macOS toolchain")
class LipoCompatibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="ianvs-lipo-test-")
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        cls.lipo = Path(__file__).resolve().parents[2] / "tools/apple_toolchain/lipo"
        source = cls.root / "fixture.c"
        source.write_text("int answer(void) { return 42; }\n")
        cls.universal = cls.root / "universal fixture.o"
        subprocess.run(
            [
                "xcrun", "clang", "-c", "-arch", "arm64", "-arch", "x86_64",
                str(source), "-o", str(cls.universal),
            ],
            check=True, capture_output=True, timeout=60,
        )
        cls.thin = cls.root / "arm64 fixture.o"
        subprocess.run(
            ["xcrun", "lipo", str(cls.universal), "-thin", "arm64", "-output", str(cls.thin)],
            check=True, capture_output=True, timeout=30,
        )

    def run_lipo(self, *arguments):
        return subprocess.run(
            [str(self.lipo), *(str(argument) for argument in arguments)],
            capture_output=True, text=True, timeout=30,
        )

    def test_accepts_both_architectures_without_modifying_binary(self):
        original = self.universal.read_bytes()
        for architectures in (("arm64", "x86_64"), ("x86_64", "arm64")):
            with self.subTest(architectures=architectures):
                result = self.run_lipo(self.universal, "-verify_arch", *architectures)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.universal.read_bytes(), original)

    def test_rejects_a_missing_architecture_in_either_position(self):
        for architectures in (("arm64", "x86_64"), ("x86_64", "arm64")):
            with self.subTest(architectures=architectures):
                result = self.run_lipo(self.thin, "-verify_arch", *architectures)
                self.assertNotEqual(result.returncode, 0)

    def test_preserves_single_architecture_verification(self):
        result = self.run_lipo(self.thin, "-verify_arch", "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(
            self.run_lipo(self.thin, "-verify_arch", "x86_64").returncode, 0,
        )

    def test_rejects_missing_or_invalid_input(self):
        invalid = self.root / "invalid.o"
        invalid.write_text("not a Mach-O file")
        for binary in (invalid, self.root / "missing.o"):
            with self.subTest(binary=binary):
                result = self.run_lipo(binary, "-verify_arch", "arm64", "x86_64")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)

    def test_passes_through_info_and_multi_architecture_extraction(self):
        info = self.run_lipo("-info", self.universal)
        self.assertEqual(info.returncode, 0, info.stderr)
        self.assertIn("arm64", info.stdout)
        self.assertIn("x86_64", info.stdout)

        output = self.root / "extracted fixture.o"
        result = self.run_lipo(
            "-output", output, "-extract", "arm64", "-extract", "x86_64", self.universal,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        architectures = self.run_lipo("-archs", output)
        self.assertEqual(architectures.returncode, 0, architectures.stderr)
        self.assertEqual(set(architectures.stdout.split()), {"arm64", "x86_64"})

    def test_prepare_and_assemble_use_the_adapter_before_xcode_tools(self):
        project_dir = self.lipo.parents[2] / "example/macos"
        scheme = ET.parse(
            project_dir / "Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
        )
        prepare = scheme.find("./BuildAction/PreActions/ExecutionAction/ActionContent")
        project = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(project_dir / "Runner.xcodeproj/project.pbxproj")],
            check=True, capture_output=True, text=True, timeout=30,
        )
        assemble = json.loads(project.stdout)["objects"]["33CC111E2044C6BF0003C045"]

        flutter_root = self.root / "Flutter SDK fixture"
        flutter_script = flutter_root / "packages/flutter_tools/bin/macos_assemble.sh"
        flutter_script.parent.mkdir(parents=True)
        flutter_script.write_text(
            '#!/bin/sh\nexec lipo "$IANVS_TEST_BINARY" -verify_arch arm64 x86_64\n',
        )
        flutter_script.chmod(0o755)
        (self.root / "Flutter/ephemeral").mkdir(parents=True)
        xcode_lipo = subprocess.run(
            ["xcrun", "--find", "lipo"],
            check=True, capture_output=True, text=True, timeout=30,
        ).stdout.strip()
        environment = {
            **os.environ,
            "PATH": f"{Path(xcode_lipo).parent}:/usr/bin:/bin",
            "PROJECT_DIR": str(project_dir),
            "FLUTTER_ROOT": str(flutter_root),
            "IANVS_TEST_BINARY": str(self.universal),
        }
        for script in (prepare.attrib["scriptText"], assemble["shellScript"]):
            with self.subTest(script=script):
                result = subprocess.run(
                    ["/bin/sh", "-c", script],
                    cwd=self.root, env=environment,
                    capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()

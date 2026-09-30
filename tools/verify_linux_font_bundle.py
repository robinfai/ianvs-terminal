#!/usr/bin/env python3
"""Verify the redistributable default font payload in a built Flutter bundle."""

import argparse
import hashlib
import json
from pathlib import Path


FAMILY = "JetBrainsMono Nerd Font Mono"
PREFIX = "packages/ianvs_terminal/assets/fonts/"
FONTS = {
    "Regular": (400, "normal", "f01031f40e48dc29e1112e6b0b0450a2c6cd097f3f35cfff05c55cb311f8034c"),
    "Bold": (700, "normal", "5bdd4a873f3cd32f882d2c55545089123926e27707d5880fc9eaf84eb01b6686"),
    "Italic": (400, "italic", "ccd88b36d325e6a905edc8dd3f2522718d9690d9bed3fbb4684c7e746c34f846"),
    "BoldItalic": (700, "italic", "d931df2928b3216892d35980cddcad9edade1b9c9cd2e09a6c2937139f474742"),
}
LICENSES = ("OFL.txt", "JETBRAINS-OFL.txt", "NERD-FONTS-LICENSE.txt")


def verify_bundle(bundle: Path) -> int:
    assets = bundle / "data/flutter_assets"
    manifest = json.loads((assets / "FontManifest.json").read_text())
    expected = {
        (PREFIX + f"JetBrainsMonoNerdFontMono-{face}.ttf", weight, style)
        for face, (weight, style, _) in FONTS.items()
    }
    for family in ("packages/ianvs_terminal/" + FAMILY,):
        matches = [entry for entry in manifest if entry["family"] == family]
        if len(matches) != 1:
            raise ValueError(f"Expected one FontManifest family: {family}")
        actual = {
            (font["asset"], font.get("weight", 400), font.get("style", "normal"))
            for font in matches[0]["fonts"]
        }
        if actual != expected or len(matches[0]["fonts"]) != 4:
            raise ValueError(f"Incomplete or incorrect font weight/style mapping: {family}")
    total = 0
    for face, (_, _, expected_hash) in FONTS.items():
        path = assets / PREFIX / f"JetBrainsMonoNerdFontMono-{face}.ttf"
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected_hash:
            raise ValueError(f"Bundled font differs from pinned Nerd Fonts v3.4.0: {path.name}")
        total += len(data)
    for name in LICENSES:
        text = (assets / PREFIX / name).read_text()
        if "Copyright" not in text or "OPEN FONT LICENSE" not in text:
            raise ValueError(f"Missing or incomplete bundled font license: {name}")
    provenance = (assets / PREFIX / "SOURCES.md").read_text()
    if "v3.4.0" not in provenance or any(value[2] not in provenance for value in FONTS.values()):
        raise ValueError("Bundled font provenance must retain pinned version and all SHA256 hashes")
    return total


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Flutter Linux bundle directory")
    args = parser.parse_args()
    try:
        total = verify_bundle(args.bundle)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Font bundle verification failed: {error}\n")
    print(f"Font bundle verified: 4 pinned faces, {total} bytes, 3 licenses, provenance, package alias")


if __name__ == "__main__":
    main()

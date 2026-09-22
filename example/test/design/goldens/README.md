# Visual regression baselines

These PNG files are inputs to the adjacent `*_visual_capture_test.dart` and
`settings_final_capture_test.dart` tests. Their subdirectories identify the
existing fixture groups; they are not historical review screenshots or proof
that the current build passes.

Run the affected test from `example/` without `--update-goldens` to compare the
current UI. Update a baseline only when an intentional UI change has been
reviewed. The capture suites target macOS rendering with fixed font assets;
follow the platform requirements in each test.

All six capture suites share `../visual_capture_fonts.dart`, which loads Roboto
(regular, medium, bold, italic and bold italic) and Material Icons from the
pinned Flutter SDK, Noto Sans SC from `../fonts/`, and JetBrains Mono from the
repository's native screenshot renderer. See `../fonts/README.md` for the CJK
asset's source, revision and license. No system font files are loaded.

The helper replaces text and component-theme font families while preserving
their other styles and state-dependent colors. Its code typography, terminal
fixtures and `monospace` alias use the same loaded JetBrains Mono asset. Noto
Sans SC supplies Chinese glyphs; JetBrains Mono also supplies shortcut symbols
missing from Roboto and Noto Sans SC. The fixtures do not use the production
terminal's system-font fallback chain. Production themes remain unchanged.

The 44 baselines cover 42 tests. Run all suites with `flutter test test/design`.
Use Flutter 3.44.2 (Dart 3.12.2) for these baselines; CI pins the same SDK and
engine. The package's minimum supported SDK is a separate compatibility floor.
CI runs visual comparisons before the longer repository gate and records the
SDK/engine, macOS version, architecture and fixed font hashes. Investigate
version/hash differences and the uploaded failure images before changing a
baseline. Pixel comparisons remain exact.

Design-review screenshots, logs and videos belong in `build/`, not `docs/` or
this baseline directory.

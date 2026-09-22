# Visual regression baselines

These PNG files are inputs to the adjacent `*_visual_capture_test.dart` and
`settings_final_capture_test.dart` tests. Their subdirectories identify the
existing fixture groups; they are not historical review screenshots or proof
that the current build passes.

Run the affected test from `example/` without `--update-goldens` to compare the
current UI. Update a baseline only when an intentional UI change has been
reviewed. The tests use local macOS fonts; follow the platform requirements in
each test.

All six capture suites share `../visual_capture_fonts.dart`, which loads SFNS,
STHeiti, Menlo and the Flutter SDK's Material Icons. It also applies capture
fonts to button and input themes that have explicit text styles. The shell
fixtures use the loaded Menlo font instead of an unregistered terminal font.

The 44 baselines cover 42 tests. Run all suites with `flutter test test/design`.
Use Flutter 3.44.2 (Dart 3.12.2) for these baselines; CI pins the same SDK and
engine. The package's minimum supported SDK is a separate compatibility floor.
CI runs visual comparisons before the longer repository gate and records the
SDK/engine, macOS version, architecture and font hashes. Its macOS runner image
can still update system fonts: investigate version/hash differences and the
uploaded failure images before changing a baseline. Pixel comparisons remain
exact.

Design-review screenshots, logs and videos belong in `build/`, not `docs/` or
this baseline directory.

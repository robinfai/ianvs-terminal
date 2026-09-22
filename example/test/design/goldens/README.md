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
The current refresh was generated and compared with Flutter 3.44.2 on macOS;
CI uses its pinned Flutter SDK and macOS runner. Pixel comparisons remain exact,
so a runner or font change must be investigated rather than silently tolerated.

Design-review screenshots, logs and videos belong in `build/`, not `docs/` or
this baseline directory.

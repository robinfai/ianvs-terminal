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

Each reviewed OS baseline contains 44 PNGs covering 42 capture tests. Run all
suites and the comparator contract tests with `flutter test test/design`.
Use Flutter 3.44.2 (Dart 3.12.2) for these baselines; CI pins the same SDK and
engine. The package's minimum supported SDK is a separate compatibility floor.
CI runs visual comparisons before the longer repository gate and records the
SDK/engine, macOS version, architecture and fixed font hashes. Investigate
version/hash differences and the uploaded failure images before changing a
baseline. Comparison uses the bounded edge tolerance described below.

`../visual_golden_comparator.dart` reads the host macOS major version once per
test isolate and routes each existing `goldens/<fixture>.png` key to
`goldens/macos-<major>/<fixture>.png`. Only macOS 26 and 27 are supported;
unknown versions fail explicitly, and a missing baseline fails comparison.
Both directories contain active expectations for the same current fixtures.
Generate and review each baseline on its corresponding OS; do not copy one
OS's rendered output into the other. This split accounts for CoreText
rasterization differences even with identical SDK and font files.

The comparator permits a difference only if **all** of these hold:

- Dimensions and every alpha value are identical.
- At most 0.45% of pixels differ, and no RGB channel changes by more than 56/255.
- In both images, each changed pixel's 3×3 neighborhood has at least 20/255
  contrast in one RGB channel. For each channel its local range must also be
  at least twice that pixel's channel change.

These limits add small headroom to the reviewed fixed-font CoreText differences
(maximum 0.41029% changed pixels and 52/255 channel delta). The neighborhood
check rejects flat-color noise and shifts of solid-color boundaries that could
otherwise fit the amplitude/area budget. It does not identify fonts: similarly
small icon-edge or other edge changes can pass, so intentional UI changes still
require review. The contract tests cover threshold boundaries, a shifted region,
flat-color changes, alpha, dimensions, missing files and diff artifacts.

Rejections retain Flutter's failure images and errors; updates retain Flutter's
original implementation. `--update-goldens` updates only the current OS directory.
CI's initial comparison remains failure-blocking; a later candidate
capture may use `--update-goldens` for review artifacts, never to approve or
automatically commit a baseline. Preserve complete relative paths when copying
reviewed candidates, since several fixtures share a filename.

Design-review screenshots, logs and videos belong in `build/`, not `docs/` or
this baseline directory.

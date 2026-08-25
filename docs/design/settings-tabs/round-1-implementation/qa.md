# Round 1 — design QA

## Evidence

- Source targets: `../round-1-imagegen/*-annotated.png`
- Implementation screenshots: `./01-general.png` through `./05-data.png`
- Same-input comparisons: `../round-1-comparison/*.png`
- Viewport/state: 1440 × 1024 logical pixels, 1× density, light theme,
  Simplified Chinese, unchanged representative settings state.
- Capture command: `flutter test --update-goldens
  test/design/settings_tab_visual_capture_test.dart`

## Result

Round 1 establishes the shared page frame and reduces surface competition.
General is closest to the ImageGen target. Appearance and Shortcuts have the
intended hierarchy but remain slightly dense vertically. Security now has the
correct stable list/detail structure, but the detail panel is less explanatory
than the target. Data now exposes the current state clearly, but its three
modes are not yet as easy to compare as the target's capability matrix.

## Findings carried into Round 2

- **P1 — Appearance vertical fit:** the dark-theme option falls below the fixed
  screenshot viewport. Tighten the preset and startup regions without reducing
  touch targets.
- **P1 — Security decision support:** add concise risk and behavior cues in the
  persistent detail panel while keeping the list stable.
- **P1 — Data mode comparison:** expose the most important capability
  differences directly in the mode rows or a compact comparison structure.
- **P2 — Shortcut toolbar density:** search, category, and restore controls are
  aligned, but the restore action competes with the primary filtering task.
- **P2 — General profile status:** the extra bottom status strip is useful but
  visually duplicates the selected row; reduce this duplication.

No P0 layout, clipping, interaction, or semantic blocker remains in the tested
desktop and mobile states. The focused regression suite passed 25 tests.

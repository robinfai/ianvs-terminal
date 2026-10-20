# Block and AI visual alignment — 2026-10-13

The default Block composer previously occupied a tall card while AI used a compact
reading surface. Both now share 12-point corners, neutral borders, a 96-point
mode slot, 44-point action targets, and a 56-point input surface after keyboard
dismissal. Block keeps its path, ownership, history and more controls in a separate
context row; the 56-point measurement excludes that row and the terminal toolbar.
The secondary bars are 52 points, and empty-state typography and positioning match.
All existing actions and menu choices remain available.

Editing still expands vertically, and the full-screen draft editor preserves text
and selection. A Return action arriving before the focus rebuild now keeps focus
rather than invoking Flutter's single-line completion default. The existing test
checks both zero submissions and subsequent hardware Shift+Enter insertion.

## Verification

- 925 passing design / composer / AI compact tests; the one optional desktop sidebar
  capture was explicitly enabled and passed separately. Existing visual goldens pass.
- 199 passing command composer and mobile Block behavioral regressions.
- Paired coverage: 320×740, 402×874 and 874×402, light/dark, empty/two-line draft,
  focus/dismissal/full-screen editing, retained selection and zero submissions.
- Native iOS **26.3.1 simulator**, iPhone 17 Pro, DPR 3: 402×874 portrait and
  874×402 landscape; each run passed all four scenarios plus teardown. Actual
  ShellScreen navigation keeps independent Block and AI drafts and zero backend
  command/write counters. Twenty paired native PNG originals are archived.
- Both appearances and orientations measure **56.0 logical pixels** for each
  dismissed input, empty or with a retained two-line draft; both secondary bars
  measure **52.0**. There were no overflow exceptions.
- Changed-source static analysis, formatting, diff checks and generated core
  synchronization passed. An unscoped workspace analyze also visited old ignored
  `build/**/review_main.dart` scratch files and reported 34 informational lints;
  no tracked source issue was reported. Those unrelated scratch files were left intact.

This is simulator UI verification with in-memory backends, not live SSH or physical
phone acceptance. Integration screenshots contain application pixels; they do not
include the OS keyboard pixels. The latest changes have not been installed on the
phone. CI for the new commit is pending; the prior 97f82ff4 run passed 8/8. Keep
PR #12 Draft and unmerged.

## Evidence

All links refer to this checkpoint's native run:

- [Measurements](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/measurements.json)
- [Original image hashes](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/capture-manifest.json)
- [Production source hashes](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/source-sha256.json)
- [Portrait log](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/native-portrait.log) / [landscape log](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/native-landscape.log)

| Native portrait, light | Native portrait, dark |
| --- | --- |
| ![Block](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/portrait-23-block-empty-light.png) | ![Block](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/portrait-23-block-empty-dark.png) |
| ![AI](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/portrait-27-shell-ai-empty-light.png) | ![AI](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/portrait-27-shell-ai-empty-dark.png) |

![Block landscape retained draft](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/landscape-25-block-dismissed-dark.png)
![AI landscape retained draft](../mobile-block-ai-v1/evidence/shared/block-ai-alignment-2026-10-13/landscape-26-shell-ai-draft-light.png)

## Follow-up: centered command/send glyphs

The bundled icon font assigned zero left side bearings even when an outline had a
nonzero xMin. The text shaper consequently moved the ink left inside correctly
centered Icon widgets. With the production font, the command triangle was displaced
by about 5.83 logical pixels. The generator and bundled font now preserve xMin as
the left bearing. All glyph outlines, codepoint mappings and advance widths are
unchanged; controls, sizes and callbacks are unchanged.

The paired mobile regression now loads the actual production icon font and measures
white glyph pixels inside the blue action circle. It fails on the original font,
then passes with the repaired font for command/AI, focused/dismissed input,
320/402-point portrait and 874-point landscape, both appearances. It still checks
56-point reading inputs, retained drafts/selection and zero submissions. The
horizontal/vertical ink bounding-center tolerance is 1.5 points, allowing the play
triangle's intentional asymmetric outline. Existing host captures continue using
their pinned substitute fonts unless production icons are explicitly requested.

The combined design and AI compact run passed 872 tests (one optional desktop
sidebar capture remains opt-in). Changed-test analysis and format checks pass.
Native iOS 26.3.1 portrait screenshots cover explicit command intent and AI send in
both appearances; this is not a repeated physical-device acceptance matrix.

[Font metrics and unchanged-outline proof](../mobile-block-ai-v1/evidence/shared/icon-centering-2026-10-13/icon-font-metrics.json) ·
[Failing pixel regression before the fix](../mobile-block-ai-v1/evidence/shared/icon-centering-2026-10-13/icon-ink-before.log) ·
[Passing regression after the fix](../mobile-block-ai-v1/evidence/shared/icon-centering-2026-10-13/icon-ink-after.log)

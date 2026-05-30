# T-075 Rendering, Glyph, and DPR Probes

## Goal

Add visual or automated probes for xterm.js rendering/glyph/DPR rows that are relevant to the Flutter Canvas renderer.

## Scope

- Selection overlay rounded-corner visual parity.
- Combined bold and faint/dim style rendering.
- Default font-weight assertion.
- Open-screen Unicode code point width/classification fixtures from xterm.js #5296.
- Fractional DPR text blur and snapping checks.

## Non-goals

- Do not add DOM/WebGL renderer support.
- Do not add image protocol support.
- Do not add ligature addon support.
- Do not change theme defaults except as a focused fix after a failing probe.

## Files In Scope

- `example/test/terminal/render_terminal_viewport_test.dart`
- `example/test/terminal/selection_controller_test.dart`
- `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `cd example && flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "bold and dim"` passes and now covers the dim-color resolution portion of a combined bold+dim style run, `FontWeight.w700` for the bold+dim cell, and `FontWeight.w400` for the adjacent default cell.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name style` passes existing style-color and default-style-adjacent tests.
- Render debug cells expose resolved `fontWeight`, so the default-weight and bold+faint xterm rows are pinned without relying only on visual inspection.
- `flutter test test/terminal/selection_controller_test.dart` passes text/cell geometry for wide, emoji, and combining glyphs.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport keeps selection paint inside cell bounds"` passes and samples selected-cell interior plus adjacent edges to prove selection paint stays inside selected terminal cell bounds.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport keeps open-screen scan-line glyphs in single cells"` passes and verifies `U+23BA` through `U+23BD` occupy sequential single cells with the cursor aligned after them.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport snaps baselines, background spans, and powerline rects to device pixels"` passes at DPR 1.25, 1.5, and 2.5 and covers text baseline, background span, and powerline placement rect snapping.
- Render tests include explicit fractional-DPR device-pixel snapping, but no host-display screenshot probe for fractional 1.25x/1.5x text blur.
- Computer Use visual pass on 2026-05-29, macOS 15.7.7 DPR 2.0: multi-row selection corners looked clean, ANSI default/bold/faint/bold+faint rows had the expected relative visual weight, and powerline/open-screen scan-line glyphs plus wide CJK and emoji rendered without fallback boxes or obvious overlap.
- Fractional-DPR host blur remains unconfirmed because the current Computer Use visual run used DPR 2.0, not 125% or 150% display scaling. The widget harness now covers the fractional snapping geometry at DPR 1.25 and 1.5.
- Rendering visual checks M-005, M-007, and M-008 are recorded as covered for the current product behavior. The remaining visual-only queue item is fractional DPR blur at 125%/150% display scaling in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md) item M-006.

## Functional Acceptance

- Add a test for a single style run that is both bold and dim/faint. Done in `example/test/terminal/render_terminal_viewport_test.dart`.
- Add a default-font-weight assertion on resolved cells or text style. Done through `TerminalResolvedCell.fontWeight`.
- Add open-screen Unicode code point fixtures from the upstream xterm.js change. Done for scan-line glyphs `U+23BA` through `U+23BD`.
- Add a fractional-DPR screenshot or pixel-snapping probe if the test harness can set the needed DPR.
- Document any visual-only residual risk in the audit.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "bold and dim"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport keeps selection paint inside cell bounds"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport keeps open-screen scan-line glyphs in single cells"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport snaps baselines, background spans, and powerline rects to device pixels"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name style
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name device-pixel
flutter test test/terminal/selection_controller_test.dart
```

## Manual QA

1. On a display scaled to 125% or 150%, render dense terminal text and compare screenshots before/after probe changes.
2. Select text with rounded selection styling and inspect corner clipping.
3. Render the upstream open-screen Unicode code points and confirm cell widths.
4. Compare ANSI default, bold, faint, and bold+faint rows in the example app.

## Done When

- Each rendering/glyph/DPR row has a named automated test or a recorded manual screenshot probe.
- The audit records the command and any remaining visual limitation.
- No renderer behavior changes land without a failing probe.

## Risks / Follow-ups

- Pixel-level blur checks can be flaky across Flutter engine and host display configurations.

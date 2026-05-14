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
- `packages/flutterm_terminal/lib/src/terminal/render_terminal_viewport.dart`
- `packages/flutterm_terminal/lib/src/terminal/terminal_models.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `cd example && flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "bold and dim"` passes and covers the dim-color resolution portion of a combined bold+dim style run.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name style` passes existing style-color and default-style-adjacent tests, but not the exact bold+faint or default-font-weight assertions.
- Render code resolves default font weight as `FontWeight.w400` and bold as `FontWeight.w700`; no test names the default-weight xterm row.
- `flutter test test/terminal/selection_controller_test.dart` passes text/cell geometry for wide, emoji, and combining glyphs, but does not include the upstream open-screen code points.
- Render tests include device-pixel snapping, but no screenshot probe for fractional 1.25x/1.5x text blur.
- Visual-only checks are queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md): rounded selection corners (M-005), fractional DPR blur (M-006), high-DPI/open-screen glyphs (M-007), and default/bold+faint visual weight (M-008).

## Functional Acceptance

- Add a test for a single style run that is both bold and dim/faint.
- Add a default-font-weight assertion on resolved cells or text style.
- Add open-screen Unicode code point fixtures from the upstream xterm.js change.
- Add a fractional-DPR screenshot or pixel-snapping probe if the test harness can set the needed DPR.
- Document any visual-only residual risk in the audit.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "bold and dim"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name style
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name device-pixel
flutter test test/terminal/selection_controller_test.dart
```

## Manual QA

1. On a display scaled to 125% or 150%, render dense terminal text and compare screenshots before/after probe changes.
2. Select text with rounded selection styling and inspect corner clipping.
3. Render the upstream open-screen Unicode code points and confirm cell widths.

## Done When

- Each rendering/glyph/DPR row has a named automated test or a recorded manual screenshot probe.
- The audit records the command and any remaining visual limitation.
- No renderer behavior changes land without a failing probe.

## Risks / Follow-ups

- Pixel-level blur checks can be flaky across Flutter engine and host display configurations.

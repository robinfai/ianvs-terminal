# T-071 xterm Scroll, Resize, and Alternate-Buffer Probes

## Goal

Close the xterm.js scroll/resize/alternate-buffer probe gaps with focused automated or manual regressions before product fixes.

## Scope

- Alternate-buffer wheel behavior and page-scroll containment.
- Alternate-buffer scrollbar transition behavior.
- Vertical-resize selection invalidation.
- CSI `8;t` resize/reflow ordering.
- Alternate-buffer wrapped line-end preservation.
- Write/resize ordering and resize-during-write crash probes.

## Non-goals

- Do not change product behavior until a failing probe is isolated.
- Do not broaden terminal renderer design.
- Do not change kitty keyboard or synchronized-output behavior.

## Files In Scope

- `example/test/terminal/render_terminal_viewport_test.dart`
- `example/test/terminal/selection_controller_test.dart`
- `packages/ianvs_terminal/test/terminal_api_test.dart`
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `native/core/tests/session_test.rs`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `cargo test --test session_test alternate_screen` passes one native alternate-screen mode test, but does not cover scrollbar teleporting or wrapped line-end corruption.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "alternate scroll"` passes arrow-key alternate-scroll behavior, not wheel/page-scroll containment.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name scrollbar` passes generic scrollbar visibility/drag behavior, not alternate-buffer transitions.
- `cargo test --test session_test session_emits_resize_events_from_terminal_requests` passes CSI `8;30;100t` resize-event emission, not resize reflow after the request.
- Manual confirmation items are queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md): alt-buffer wheel containment (M-001), alt-buffer scrollbar/line-end behavior (M-002), resize selection invalidation (M-003), and CSI/write-resize ordering (M-004).

## Functional Acceptance

- Add a focused alternate-buffer wheel probe for trackpad and mouse-wheel input, including a manual macOS note if widget automation cannot prove host page-scroll containment.
- Add a test for entering alternate screen, scrolling/dragging, and returning to main screen without scrollbar teleporting.
- Add a vertical-resize selection invalidation test.
- Add a native or package test for write-then-resize ordering and resize during active write.
- Add a native alternate-buffer wrapped-line fixture.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test session_test alternate_screen
cargo test --test session_test session_emits_resize_events_from_terminal_requests

cd example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "alternate scroll"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name scrollbar
flutter test test/terminal/selection_controller_test.dart
```

## Manual QA

1. Open `less` or `vim` in the example app.
2. Scroll with a trackpad and a mouse wheel while the alternate buffer is active.
3. Drag the scrollbar, exit the alternate buffer, and confirm the main buffer returns without jump or stale scroll position.

## Done When

- Each row in this cluster has a named regression or manual probe record.
- Confirmed failures are split into implementation tasks before product fixes.
- The audit table records the exact probe command and this task link.

## Risks / Follow-ups

- Host page scrolling may need a real app/manual probe rather than a pure widget test.

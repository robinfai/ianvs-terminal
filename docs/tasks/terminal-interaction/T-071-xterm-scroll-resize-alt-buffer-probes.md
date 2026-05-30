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

- `cargo test --test session_test alternate_screen` passes one native alternate-screen mode test.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test session_preserves_wrapped_line_metadata_in_alternate_screen` passed on 2026-05-29 and covers alternate-screen wrapped line-end metadata plus contiguous selection text across wrapped rows.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "alternate scroll"` passes arrow-key alternate-scroll behavior.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport accumulates partial alternate scroll wheel deltas"` passed on 2026-05-29 and covers sub-line alternate-scroll wheel accumulation before arrow escape emission.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport claims alternate scroll wheel before parent scrollables"` passed on 2026-05-30 and covers host/page-scroll containment by nesting the terminal in a parent `SingleChildScrollView`; the parent offset remains 0 while the terminal emits alternate-scroll arrow bytes.
- `flutter test test/terminal/render_terminal_viewport_test.dart --plain-name scrollbar` passes generic scrollbar visibility/drag behavior, not alternate-buffer transitions.
- `cargo test --test session_test session_emits_resize_events_from_terminal_requests` passes CSI `8;30;100t` resize-event emission, not resize reflow after the request.
- `flutter test test/terminal_api_test.dart --plain-name "terminal facade rejects zero resize dimensions"` passed on 2026-05-29 and covers zero-row/zero-column facade rejection before backend resize.
- `flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime controller applies resize before queued write frames"` passed on 2026-05-29 and covers input-triggered refresh with a queued pre-resize frame plus resize event; the resize publishes before the settled post-resize frame and no resize-during-write exception occurs.
- `flutter test test/terminal/selection_controller_test.dart --plain-name "selectionForFrame remaps stable selections after vertical resize"` passed on 2026-05-29 and locks the ianvs selection policy: stable absolute-row selections remap to the visible resized viewport slice, and fully offscreen selections render as empty instead of stale relative geometry.
- Computer Use manual pass on 2026-05-29, macOS 15.7.7: `less` keyboard paging worked in the alternate screen, exiting `less` returned to the main buffer without visible content teleport, resize-selection stayed visually aligned while zooming from 93x22 to 203x44, and `CSI 8;20;60t` resized the app to 60x20 with wrapped rows reflowed and no crash.
- A follow-up Computer Use pass on 2026-05-29 generated main-buffer scrollback, entered `less`, paged the alternate screen from rows 1-19 to rows 20-38, observed no host scrollbar/thumb during alternate screen, exited with `q`, and saw the main buffer plus bottom scrollbar return without visible teleporting.
- The same 2026-05-29 Computer Use pass could not confirm wheel containment because Computer Use scroll gestures did not move `less`; the 2026-05-30 parent-scrollable widget regression now pins the containment behavior that Computer Use could not deliver manually.
- Manual confirmation items M-001 through M-004 are recorded as covered for the current product behavior; repeat manual smoke only if platform scroll, selection resize, or app/window resize coupling changes.

## Functional Acceptance

- Add a focused alternate-buffer wheel probe for trackpad and mouse-wheel input, including a manual macOS note if widget automation cannot prove host page-scroll containment. Done with a parent-scrollable widget regression.
- Add a test or manual record for entering alternate screen, scrolling/paging, and returning to main screen without scrollbar teleporting. Done with Computer Use observation; the current product does not expose a draggable host thumb during alternate screen.
- Add a vertical-resize selection invalidation test. Done with stable-row remapping and offscreen-empty selection policy coverage.
- Add a native or package test for write-then-resize ordering and resize during active write. Done in `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`.
- Add a native alternate-buffer wrapped-line fixture. Done in `native/core/tests/session_test.rs`.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test session_test alternate_screen
cargo test --test session_test session_emits_resize_events_from_terminal_requests
cargo test --manifest-path native/core/Cargo.toml --test session_test session_preserves_wrapped_line_metadata_in_alternate_screen

cd packages/ianvs_terminal
flutter test test/terminal_api_test.dart --plain-name "terminal facade rejects zero resize dimensions"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime controller applies resize before queued write frames"

cd example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "alternate scroll"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport accumulates partial alternate scroll wheel deltas"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport claims alternate scroll wheel before parent scrollables"
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name scrollbar
flutter test test/terminal/selection_controller_test.dart
flutter test test/terminal/selection_controller_test.dart --plain-name "selectionForFrame remaps stable selections after vertical resize"
```

## Manual QA

1. Open `less` or `vim` in the example app.
2. Scroll with a trackpad and a mouse wheel while the alternate buffer is active.
3. Drag the scrollbar, exit the alternate buffer, and confirm the main buffer returns without jump or stale scroll position.
4. Emit a long wrapped line plus `CSI 8;rows;cols t` in the example app and confirm the window dimensions, wrapped rows, and absence of resize/write crashes.

## Done When

- Each row in this cluster has a named regression or manual probe record.
- Confirmed failures are split into implementation tasks before product fixes.
- The audit table records the exact probe command and this task link.

## Risks / Follow-ups

- Host page scrolling may need a real app/manual probe rather than a pure widget test.

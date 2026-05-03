# T-062 Ianvs Terminal Feedback Hardening

## Goal

Process actionable feedback from
`/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/FLUTTERM_FEEDBACK.md`
by fixing upstream terminal gaps that affect Ianvs Terminal readiness and by
recording remaining validation risks.

## Scope

- Fix `FT-006` by ensuring delta frames that carry row text also mark those
  rows dirty at the Dart viewport state boundary.
- Fix `FT-007` by exposing an explicit runtime refresh API that requests a
  native full repaint for the current scrollback offset.
- Fix `FT-009` by exposing alternate-screen state in native frame modes and in
  Dart `TerminalFrameModes`.
- Keep closed/product-side-only items (`FT-001`, `FT-002`, `FT-003`, `FT-008`,
  `FT-010`, `FT-011`) out of this implementation pass.
- Preserve existing xterm-style facade and low-level runtime APIs.

## Non-goals

- Do not add inline block rendering extensions for `FT-008`.
- Do not claim Windows / Linux support is complete for `FT-012`.
- Do not re-run the full manual compatibility matrix for `FT-004`.
- Do not solve old native/core baseline history from `FT-005`; only verify the
  current tree.

## Files In Scope

- `packages/flutterm_terminal/lib/src/terminal/terminal_models.dart`
- `packages/flutterm_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `packages/flutterm_terminal/lib/src/xterm/terminal_api.dart`
- `packages/flutterm_terminal/test/terminal_runtime_controller_test.dart`
- `packages/flutterm_terminal/test/terminal_api_test.dart`
- `native/core/src/model.rs`
- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`

## Functional Acceptance

- A delta frame with `rows` but empty/missing `dirty_ranges` invalidates every
  carried row so cached row visuals repaint.
- Stale hyperlinks on a row are cleared when that row arrives in a delta frame
  without corresponding hyperlink ranges.
- Consumers can call `TerminalRuntimeController.refreshSession(sessionId)` or
  `Terminal.refresh()` to request a native full repaint without relying on
  product-side scroll-to-current-offset workarounds.
- Native JSON frames include `modes.alternate_screen`; Dart parses it as
  `TerminalFrameModes.alternateScreen`.

## Verification Commands

```bash
flutter analyze
flutter test packages/flutterm_terminal
flutter test packages/flutterm_pty
flutter test example
cargo test --manifest-path native/core/Cargo.toml
```

## Manual QA

- Run Ianvs Terminal real shell smoke with the rebuilt native core and confirm
  startup prompt recovery no longer requires product-side dirty-range or
  scroll-to-current-offset workarounds.
- In a real shell, open `vim`, `less`, or another alternate-screen application
  and confirm the consumer observes `alternateScreen == true`.

## Done When

- The automated checks above pass.
- Current flutterm task documentation records how `FT-006`, `FT-007`, and
  `FT-009` were handled.
- Remaining feedback risks are explicitly left as follow-ups instead of being
  marked complete without evidence.

## Risks / Follow-ups

- `FT-004` and `FT-012` still require platform/manual matrix evidence before
  Ianvs Terminal can claim broader compatibility.
- `FT-008` needs a separate render-layer range annotation design before inline
  terminal blocks are implemented.

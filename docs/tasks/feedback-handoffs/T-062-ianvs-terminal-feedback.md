# T-062 Ianvs Terminal Feedback Hardening

## Goal

Process actionable feedback from
`/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/FLUTTERM_FEEDBACK.md`
by fixing the selected upstream terminal gaps that affect Ianvs Terminal
readiness and by recording explicit follow-up owners for the remaining items.

## Scope

- Fix `FT-006` by ensuring delta frames that carry row text also mark those
  rows dirty at the Dart viewport state boundary.
- Fix `FT-007` by exposing an explicit runtime refresh API that requests a
  native full repaint for the current scrollback offset.
- Fix `FT-009` by exposing alternate-screen state in native frame modes and in
  Dart `TerminalFrameModes`.
- Record follow-up handoffs for `FT-001` (`T-063`), `FT-004` (`T-059`),
  `FT-008` (`T-064`), and `FT-012` (`T-065`) without expanding this
  implementation pass.
- Preserve existing xterm-style facade and low-level runtime APIs.

## Non-goals

- Do not finish the typed shell-hook runtime surface, bash / fish contract, or
  broader command lifecycle follow-up from `FT-001`; that belongs to `T-063`.
- Do not add inline block rendering extensions for `FT-008`; that design
  follow-up belongs to `T-064`.
- Do not claim Windows / Linux support is complete for `FT-012`; that
  validation gate belongs to `T-065`.
- Do not re-run the full manual compatibility matrix for `FT-004`; the local
  manual matrix follow-up remains in `T-059`.
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
  `FT-009` were handled, and where `FT-001`, `FT-004`, `FT-008`, and `FT-012`
  continue.
- Remaining feedback risks are explicitly left as follow-ups instead of being
  marked complete without evidence.

## Risks / Follow-ups

- `FT-001` still needs a typed runtime shell-hook surface and a multi-shell
  contract in `T-063`.
- `FT-004` still depends on `T-059` producing non-blocked local manual matrix
  evidence.
- `FT-008` still needs the render-layer row-range annotation design in `T-064`
  before inline terminal blocks are implemented.
- `FT-012` still needs the Phase 4 Windows / Linux validation gate in `T-065`
  before broader platform claims are made.

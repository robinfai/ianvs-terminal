# T-237 Native historical scrollback export request

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Expose native historical scrollback text through the PTY JSON request channel so
`ShellScreen` export can save more than the current visible frame.

## Scope

- Add native `TerminalSession.export_scrollback_text()`.
- Route `terminal.export_scrollback` through `request_session_json`.
- Return JSON containing:
  - `content`
  - `scope: historical-scrollback`
- Add Dart runtime `exportScrollbackText(sessionId)`.
- Make `ShellScreen` export prefer native historical scrollback and fall back to
  visible-frame export when historical content is unavailable or empty.

## Non-goals

- Do not add format picker UI.
- Do not add file picker UI.
- Do not change export policy persistence.
- Do not run verification commands.

## Deliverables

- `native/core/src/session.rs`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Runtime can request historical scrollback text from native core.
- `ShellScreen` export metadata records `historical-scrollback` when native text
  is used.
- Visible-frame fallback remains available.
- Existing session identity and PTY process are not affected.

## Status

Implemented as native historical scrollback export request plumbing.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

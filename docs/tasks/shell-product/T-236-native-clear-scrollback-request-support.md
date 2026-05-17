# T-236 Native clear scrollback request support

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Add native core support for the `terminal.clear_scrollback` PTY JSON request
used by the Dart runtime clear-scrollback plumbing.

## Scope

- Add `TerminalSession.clear_scrollback()`.
- Process ESC[3J inside the native emulator, not by sending bytes to the shell.
- Reset `scrollback_offset`.
- Clear resize replay transcript and mark it truncated so a later resize does
  not rehydrate old scrollback.
- Clear cached rows/frame metadata and request a full repaint.
- Add request routing for `terminal.clear_scrollback`.
- Return `{"cleared": true}` when native clear is accepted.

## Non-goals

- Do not send clear escape bytes to the PTY shell process.
- Do not alter the active PTY process or session identity.
- Do not implement full historical scrollback export in this task.

## Deliverables

- `native/core/src/session.rs`

## Acceptance criteria

- Dart `TerminalRuntimeController.clearScrollback()` can receive a native
  `{"cleared": true}` response.
- Native emulator scrollback is cleared internally.
- Future resize replay does not reconstruct old scrollback from transcript.
- UI repaint is requested after clearing.

## Status

Implemented as native request support for `terminal.clear_scrollback`.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

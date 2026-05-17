# T-234 Clear scrollback runtime API blocker

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Define the remaining `clearScrollback` blocker as a runtime/API task instead of
continuing to search for a `ShellScreen` workaround.

## Required runtime capability

- Expose a terminal runtime operation that clears emulator scrollback for a
  specific session.
- Ensure the operation updates the active `TerminalViewportController` frame so
  the UI does not retain stale rows.
- Ensure future frames from the backend do not rehydrate cleared scrollback.
- Preserve the active PTY process and session identity.

## Required product wiring

- Add command-menu production dispatch for `clearScrollback` only after the
  runtime API exists.
- Gate the action on an active session.
- Keep read-only mode separate: clearing local scrollback is not terminal input.
- Report failure when the runtime cannot clear the buffer.

## Non-goals

- Do not implement `clearScrollback` by sending escape bytes to the shell.
- Do not clear only the visible widget tree while leaving runtime scrollback
  intact.
- Do not mark P1/P5 complete until this has runtime support or is explicitly
  descoped.

## Acceptance criteria

- A runtime API exists and is used by `ShellScreen`.
- The UI visibly clears session scrollback.
- The active process remains alive.
- The operation is covered by automated or manual verification before closure.

## Status

Unblocked by T-235 and T-236. Dart runtime plumbing, `ShellScreen` production
dispatch, and native `terminal.clear_scrollback` request support now exist.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this record.

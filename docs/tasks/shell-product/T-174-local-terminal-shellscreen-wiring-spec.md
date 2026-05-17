# T-174 Local terminal ShellScreen wiring spec

## Milestone

P1-P5 production wiring integration

## Intent

Define the concrete `ShellScreen` / `SessionController` / settings / export /
runtime callback map needed to move from foundation contracts to real production
wiring.

## Scope

- Map P1 action wiring to command menu, shortcut, runtime dispatch, and
  diagnostics surfaces.
- Map P2 workspace callbacks to tab, pane, and layout production behavior.
- Map P3 productivity callbacks to prompt, command output, search, read-only,
  and scrollback behavior.
- Map P4 policy callbacks to paste, clipboard, notifications, and hotkey window
  behavior.
- Map P5 visual callbacks to theme, layout template, export, graphics, and
  advanced visual behavior.

## Deliverables

- `docs/LOCAL_TERMINAL_SHELLSCREEN_WIRING_SPEC_2026-05.md`

## Acceptance criteria

- The spec identifies the production target for each callback group.
- Closure evidence is listed for P1-P5.
- The spec explicitly states that production callbacks are not populated yet.

## Status

Created. The spec documents the next implementation pass; it does not close the
work.

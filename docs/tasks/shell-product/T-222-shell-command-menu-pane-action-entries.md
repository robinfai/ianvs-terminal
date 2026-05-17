# T-222 Shell command menu pane action entries

## Milestone

P1 action runtime production wiring

## Intent

Expose production-dispatched pane actions in the command menu so their runtime
bindings are reachable from the product UI.

## Scope

- Add a `hasMultiplePanes` availability flag to `_ShellCommandMenu`.
- Add command-menu entries for:
  - `focusNextPane`
  - `focusPreviousPane`
  - `closePane`
- Enable focus next/previous only when the active tab has multiple panes.
- Keep close active pane enabled when an active session exists.

## Non-goals

- Do not implement resize, swap, or zoom pane UI in this task.
- Do not change pane focus/close runtime behavior.
- Do not change shortcut resolution.
- Do not run verification commands.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Command menu exposes the production-dispatched pane focus/close actions.
- Focus next/previous pane entries are disabled for single-pane tabs.
- Close active pane remains available for active sessions.

## Status

Implemented as command-menu entries for pane focus/close actions.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

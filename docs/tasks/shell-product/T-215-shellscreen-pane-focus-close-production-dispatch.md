# T-215 ShellScreen pane focus and close production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Move the existing pane-level behaviors that are already supported by
`ShellScreen` into the production action runtime path.

## Scope

- Add a local helper to focus the next or previous pane within the active tab.
- Route `focusNextPane`, `focusPreviousPane`, and `closePane` through production
  dispatch from command-menu and shortcut paths.
- Promote the three actions into the current default required production action
  set.
- Preserve current session-based close behavior for active panes.

## Non-goals

- Do not implement pane resize, swap, or zoom behavior in this task.
- Do not add directional pane action IDs.
- Do not remove legacy switch fallback.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `focusNextPane` and `focusPreviousPane` use the current tab's
  `effectivePanes` order and cycle between panes.
- Single-pane tabs skip pane focus movement.
- `closePane` preserves the existing active-session close behavior.
- The default required production action set includes these newly dispatched
  pane actions.

## Status

Implemented as pane focus/close production dispatch coverage.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

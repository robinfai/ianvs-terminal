# T-217 ShellScreen open recent directory production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Route the existing recent-directory command insertion behavior through the
production action runtime adapter.

## Scope

- Add `openRecentDirectory` to the command-menu production dispatch scope.
- Read the active pane's shell integration recent-directory list.
- Insert a quoted `cd <directory>` command for the most recent directory.
- Preserve the existing behavior of inserting the command text without sending a
  newline.
- Promote `openRecentDirectory` into the current default required production
  action set.

## Non-goals

- Do not change shell integration recent-directory collection.
- Do not execute the `cd` command automatically.
- Do not add a directory picker or selection UI in this task.
- Do not migrate shortcut dispatch for this action.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `openRecentDirectory` can execute through `ShellActionProductionRuntimeAdapter`
  from the command-menu path.
- Missing active sessions skip action execution.
- Empty recent-directory lists skip action execution.
- Successful execution restores terminal focus after inserting the command text.

## Status

Implemented as command-menu production dispatch coverage for
`openRecentDirectory`.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

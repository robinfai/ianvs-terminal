# T-218 ShellScreen duplicate current directory production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Expose and route `duplicateCurrentCwd` through the production action runtime
using the active pane's shell integration current-directory data.

## Scope

- Add a command-menu entry for `duplicateCurrentCwd`.
- Register a production callback for `duplicateCurrentCwd` in the command-menu
  dispatch scope.
- Require a default profile, active session, and non-empty current directory.
- Create a new tab with the default profile.
- Insert a quoted `cd <currentDirectory>` command into the duplicated session
  without automatically sending a newline.
- Promote `duplicateCurrentCwd` into the current default required production
  action set.

## Non-goals

- Do not change profile startup-directory configuration.
- Do not execute the `cd` command automatically.
- Do not implement closed-tab history or `reopenClosedTab`.
- Do not migrate shortcut dispatch for this action.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- The command menu exposes `Duplicate current directory` when a default profile
  and active session exist.
- `duplicateCurrentCwd` can execute through
  `ShellActionProductionRuntimeAdapter`.
- Missing default profile, missing active session, or missing current-directory
  data skips action execution.
- Successful execution creates a new tab and inserts a quoted `cd` command for
  the original current directory.

## Status

Implemented as command-menu production dispatch coverage for
`duplicateCurrentCwd`.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-224 ShellScreen two-pane layout template dispatch

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Expose a concrete local layout-template action through `ShellScreen` production
dispatch without pretending the lower-level workspace template model is already
fully synchronized with the live session model.

## Scope

- Add command-menu production dispatch for `applyLayoutTemplate`.
- Expose an `Apply two-pane layout` command-menu entry.
- Implement the current concrete template as a local split-right two-pane
  layout using the existing `_splitActiveSession` behavior.
- Enable the action only when a default profile, active session, and single-pane
  active tab exist.
- Promote `applyLayoutTemplate` into the current default required production
  action set.

## Non-goals

- Do not wire the persisted layout-template repository to live `ShellScreen`
  state in this task.
- Do not add arbitrary template selection UI.
- Do not alter split persistence or workspace restoration.
- Do not claim P5 visual/layout wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `applyLayoutTemplate` executes through `ShellActionProductionRuntimeAdapter`.
- Single-pane tabs can apply the two-pane split-right template.
- Multi-pane tabs skip/disable the action rather than adding extra panes.
- The action remains scoped to local terminal behavior.

## Status

Implemented as a concrete two-pane layout-template production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

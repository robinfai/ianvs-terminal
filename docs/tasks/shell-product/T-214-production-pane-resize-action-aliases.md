# T-214 Production pane resize action aliases

## Milestone

P1 action runtime production wiring

## Intent

Keep pane resize production wiring auditable by mapping direction-specific
callback names to the current `TerminalActionId.resizePane` action.

## Scope

- Extend the production action-name resolver with pane resize aliases:
  - `resizePaneLeft` -> `resizePane`
  - `resizePaneRight` -> `resizePane`
  - `resizePaneUp` -> `resizePane`
  - `resizePaneDown` -> `resizePane`
- Preserve the default action-set baseline from T-213.

## Non-goals

- Do not implement pane resize behavior in this task.
- Do not add new directional `TerminalActionId`s.
- Do not migrate pane management actions through `ShellScreen` production
  dispatch in this task.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_action_name_resolver.dart`

## Acceptance criteria

- Direction-specific pane resize callback names resolve to
  `TerminalActionId.resizePane`.
- Future pane resize callback registration will not be reported as an unknown
  production binding solely because of naming granularity.
- Remaining pane resize behavior remains tracked as future implementation work.

## Status

Implemented as production action-name aliases for pane resize callbacks.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

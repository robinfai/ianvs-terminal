# T-225 Production action set remove unresolved silence monitor

## Milestone

P1 action runtime production wiring

## Intent

Keep the default production action set auditable by removing an optional action
name that does not currently resolve to a `TerminalActionId`.

## Scope

- Remove `toggleSilenceMonitor` from the default optional production action set.
- Keep existing notification actions that have `TerminalActionId` coverage:
  - `toggleCommandFinishedNotify`
  - `toggleBellNotify`
  - `toggleActivityMonitor`

## Non-goals

- Do not implement notification preference persistence in this task.
- Do not add a new `TerminalActionId`.
- Do not claim notification production wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- The default production action set no longer contains an optional action name
  that cannot resolve through the production action-name resolver.
- Silence-monitor support remains future work until it has a concrete action ID
  and product behavior.

## Status

Implemented as an action-set auditability fix.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

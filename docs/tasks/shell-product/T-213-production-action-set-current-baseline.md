# T-213 Production action set current baseline

## Milestone

P1 action runtime production wiring

## Intent

Align the default production action set with the actions that currently have
real `ShellScreen` production runtime dispatch coverage, so audits can report
remaining work accurately instead of being blocked by stale required items.

## Scope

- Move currently production-dispatched `ShellScreen` actions into the default
  required action set.
- Move not-yet-migrated or secondary actions into the optional action set.
- Remove optional action names that do not currently resolve to a
  `TerminalActionId`.
- Preserve explicit optional coverage for future pane, profile, visual, and
  notification work.

## Non-goals

- Do not claim P1 action runtime wiring is globally complete.
- Do not add new behavior in this task.
- Do not remove legacy `ShellScreen` switch fallback.
- Do not change shortcut or command-menu presentation.

## Deliverables

- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- The default required action set reflects the current production-dispatched
  `ShellScreen` baseline.
- Not-yet-migrated actions are not treated as hard blockers for the current
  baseline.
- Optional action names are resolvable by the production action-name resolver.
- Remaining future work stays visible through optional action coverage and
  follow-up tasks.

## Status

Implemented as a default production action-set baseline update.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

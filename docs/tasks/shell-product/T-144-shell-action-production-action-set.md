# T-144 Shell action production action set

## Milestone

P1 - Local terminal action foundation

## Intent

Define the supported production action set that `ShellScreen` and
`SessionController` wiring must cover before the action runtime can be considered
complete.

## Scope

- Add a default required action-name set for core local terminal actions.
- Add an optional action-name set for actions that can land after the core UI
  path is wired.
- Resolve configured action names to `TerminalActionId` values.
- Report unknown configured action names without breaking compilation.
- Feed the resolved action ids into the runtime binding audit.

## Deliverables

- `example/lib/features/shell/shell_action_production_action_set.dart`
- `example/test/shell/shell_action_production_action_set_test.dart`

## Acceptance criteria

- Required action names resolve to action ids when the registry contains them.
- Unknown planned names are reported as explicit diagnostics.
- Runtime binding audits can be generated from the production action set.

## Status

Foundation implemented. Not verified in this session.

# T-145 Shell action production binding builder

## Milestone

P1 - Local terminal action foundation

## Intent

Provide the adapter that turns production `ShellScreen` / `SessionController`
callback registrations into audited `ShellActionRuntimeBindings`.

## Scope

- Accept production callbacks keyed by action name.
- Resolve action names to `TerminalActionId` values.
- Build runtime bindings for known actions.
- Report unknown binding names.
- Report unknown planned action names from the production action set.
- Return the runtime binding audit alongside the built bindings.

## Deliverables

- `example/lib/features/shell/shell_action_production_binding_builder.dart`
- `example/test/shell/shell_action_production_binding_builder_test.dart`

## Acceptance criteria

- Known action-name callbacks become runnable runtime bindings.
- Unknown callback names are reported without throwing.
- Unknown planned action names are surfaced in the build result.
- Build completion is true only when there are no unknown names and no missing
  required production bindings.

## Status

Foundation implemented. Not verified in this session.

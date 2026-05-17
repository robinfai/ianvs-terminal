# T-147 Shell action production callbacks

## Milestone

P1 - Local terminal action foundation

## Intent

Give `ShellScreen` and `SessionController` a typed callback contract for
registering production action handlers without manually constructing string-keyed
binding maps.

## Scope

- Add typed nullable callback fields for the supported production action names.
- Convert provided callbacks into action-name keyed bindings.
- Build audited runtime bindings through the production binding builder.
- Keep omitted callbacks visible through the existing missing-required binding
  audit.

## Deliverables

- `example/lib/features/shell/shell_action_production_callbacks.dart`
- `example/test/shell/shell_action_production_callbacks_test.dart`

## Acceptance criteria

- Typed callbacks produce runnable runtime bindings.
- Missing required callbacks remain visible in the binding audit.
- Optional callbacks do not appear as unplanned bindings when the action set
  marks them optional.

## Status

Foundation implemented. Not verified in this session.

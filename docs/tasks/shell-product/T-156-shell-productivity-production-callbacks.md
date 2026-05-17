# T-156 Shell productivity production callbacks

## Milestone

P3 - Shell productivity

## Intent

Define the production callback contract that will let `ShellScreen`,
`SessionController`, and terminal scrollback/search code wire real shell
productivity behavior into the P3 foundation.

## Scope

- Add shell productivity production operation ids.
- Add a binding context and structured binding result.
- Add typed nullable callbacks for prompt navigation, command output, recent
  directory, search, read-only, and scrollback operations.
- Add a wiring object that can run registered callbacks.
- Report missing required productivity callbacks before P3 can close.

## Deliverables

- `example/lib/features/productivity/shell_productivity_production_callbacks.dart`
- `example/test/productivity/shell_productivity_production_callbacks_test.dart`

## Acceptance criteria

- Registered productivity callbacks receive context and return structured
  results.
- Missing required operations are visible through the wiring object.
- Unsupported operations return a failed result instead of throwing.

## Status

Foundation implemented. Not verified in this session.

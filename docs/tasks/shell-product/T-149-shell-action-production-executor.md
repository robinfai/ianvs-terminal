# T-149 Shell action production executor

## Milestone

P1 - Local terminal action foundation

## Intent

Provide the execution adapter that invokes production action wiring only after
the typed callback surface is ready.

## Scope

- Execute a `TerminalActionId` through `ShellActionProductionWiringState`.
- Block execution when production wiring has unresolved blocking diagnostics.
- Preserve tab id, pane id, cwd, and payload context fields.
- Convert callback exceptions into structured platform-failure results.

## Deliverables

- `example/lib/features/shell/shell_action_production_executor.dart`
- `example/test/shell/shell_action_production_executor_test.dart`

## Acceptance criteria

- Ready wiring executes registered callbacks.
- Unready wiring returns an unavailable failure without invoking callbacks.
- Callback exceptions become platform-failure execution results.

## Status

Foundation implemented. Not verified in this session.

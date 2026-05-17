# T-155 Local workspace production callbacks

## Milestone

P2 - Local workspace

## Intent

Define the production callback contract that will let `ShellScreen` wire real
tab, pane, split, focus, resize, swap, zoom, and layout behavior into the local
workspace model.

## Scope

- Add workspace production operation ids.
- Add a binding context and structured binding result.
- Add typed nullable callbacks for supported workspace operations.
- Add a wiring object that can run registered callbacks.
- Report missing required workspace callbacks before P2 can close.

## Deliverables

- `example/lib/features/workspace/local_workspace_production_callbacks.dart`
- `example/test/workspace/local_workspace_production_callbacks_test.dart`

## Acceptance criteria

- Registered workspace callbacks receive context and return structured results.
- Missing required operations are visible through the wiring object.
- Unsupported operations return a failed result instead of throwing.

## Status

Foundation implemented. Not verified in this session.

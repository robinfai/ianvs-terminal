# T-256 Workspace production callback baseline regression

## Goal

Add regression coverage for the current core P2 workspace production callback baseline while keeping optional layout gaps visible.

## Scope

- Update `example/test/workspace/local_workspace_production_callbacks_test.dart`.
- Define the current core required workspace operations for live wiring.
- Assert the core baseline is ready when matching callbacks are supplied.
- Assert default all-operation wiring still reports advanced/layout gaps when only the core callbacks are supplied.

## Non-goals

- Do not mark P2 verified.
- Do not run tests in this task.
- Do not claim layout save/restore or reopen-closed-pane UI is complete.

## Acceptance

- Core tab, pane, split, focus, resize, swap, zoom, duplicate-cwd, and reopen-tab wiring remains protected by tests.
- Layout save/restore and other advanced workspace gaps remain visible as missing operations under the all-operations contract.

## Verification Commands

- `flutter test example/test/workspace/local_workspace_production_callbacks_test.dart`

## Result

Added focused regression coverage for the core P2 workspace production callback baseline and the remaining advanced workspace gaps.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Runtime and UI behavior still require the full verification plan.

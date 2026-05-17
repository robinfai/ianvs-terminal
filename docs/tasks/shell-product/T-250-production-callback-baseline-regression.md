# T-250 Production callback baseline regression

## Goal

Add regression coverage proving the typed production callback surface can satisfy the current default P1 action baseline.

## Scope

- Update `example/test/shell/shell_action_production_callbacks_test.dart`.
- Build `ShellActionProductionCallbacks` with callbacks for the current required baseline.
- Assert the default action set build is complete, has no unknown names, no missing required actions, and no unplanned registered actions.
- Assert the resize-pane alias path registers `TerminalActionId.resizePane`.

## Non-goals

- Do not mark P1 verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The typed callback surface cannot silently drop a required current baseline action without test coverage failing.
- The resize-pane alias remains covered by the typed callback surface.

## Verification Commands

- `flutter test example/test/shell/shell_action_production_callbacks_test.dart`

## Result

Added a focused regression test showing typed production callbacks can satisfy the current default P1 action baseline.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Runtime behavior still requires the full verification plan.

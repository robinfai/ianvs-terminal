# T-251 Production wiring state baseline regression

## Goal

Add regression coverage proving the production wiring state is ready when the current default P1 action baseline is satisfied by typed callbacks.

## Scope

- Update `example/test/shell/shell_action_production_wiring_state_test.dart`.
- Build `ShellActionProductionWiringState` with `ShellActionProductionActionSet.defaults()`.
- Provide typed callbacks for the current required baseline.
- Assert the wiring state is ready, has no blocking diagnostics, has no missing required actions, and registers the resize-pane alias.

## Non-goals

- Do not mark P1 verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The wiring state cannot silently regress from ready to blocked for the current default baseline when all typed callbacks are supplied.
- Blocking diagnostics remain covered at the state layer.

## Verification Commands

- `flutter test example/test/shell/shell_action_production_wiring_state_test.dart`

## Result

Added focused regression coverage for the default P1 baseline at the production wiring state layer.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Runtime behavior still requires the full verification plan.

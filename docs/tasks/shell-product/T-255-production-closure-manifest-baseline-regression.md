# T-255 Production closure manifest baseline regression

## Goal

Add regression coverage proving the P1 production closure manifest only closes the current default action baseline when wiring, tests, and static analysis are all satisfied.

## Scope

- Update `example/test/shell/shell_action_production_closure_manifest_test.dart`.
- Build a clean default P1 baseline wiring snapshot with complete typed callbacks.
- Assert unverified tests/analysis keep the manifest blocked.
- Assert the same wiring can close only when tests and analysis are marked passed.

## Non-goals

- Do not mark P1 verified in real completion evidence.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The closure manifest preserves the distinction between ready wiring and verified closure.
- The default P1 baseline cannot be treated as complete without tests and static analysis evidence.

## Verification Commands

- `flutter test example/test/shell/shell_action_production_closure_manifest_test.dart`

## Result

Added focused regression coverage for default P1 baseline closure-manifest semantics.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Real closure still requires executed and recorded verification evidence.

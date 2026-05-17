# T-261 Production wiring bundle core baseline regression

## Goal

Add regression coverage for `LocalTerminalProductionWiringBundle` so current P2-P5 core baselines assemble into a closeable cross-milestone manifest only when verification inputs are supplied.

## Scope

- Update `example/test/shell/local_terminal_production_wiring_bundle_test.dart`.
- Build a bundle with current P2-P5 core callbacks and required operations.
- Use a router-supported P1 action subset to prove action wiring works across the bundle.
- Assert the bundle closes when P0 and P1-P5 verification statuses are verified.
- Assert ready core wiring remains blocked when P2-P5 verification statuses are not verified.

## Non-goals

- Do not mark real verification gates as passed.
- Do not run tests in this task.
- Do not claim advanced P2-P5 gaps are complete.

## Acceptance

- The bundle preserves the distinction between core wiring readiness and verified closure.
- Cross-milestone assembly can execute representative routed actions from the core baseline.

## Verification Commands

- `flutter test example/test/shell/local_terminal_production_wiring_bundle_test.dart`

## Result

Added focused regression coverage for P2-P5 core baseline assembly and verification blockers at the production wiring bundle layer.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

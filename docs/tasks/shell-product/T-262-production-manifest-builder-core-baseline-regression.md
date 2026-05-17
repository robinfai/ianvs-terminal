# T-262 Production manifest builder core baseline regression

## Goal

Add regression coverage for `LocalTerminalProductionWiringManifestBuilder` so current P2-P5 core summaries close only when verification statuses are supplied.

## Scope

- Update `example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart`.
- Build current P2-P5 core summaries from real production callback wiring.
- Assert the manifest closes when P0, P1, and P2-P5 verification statuses are verified.
- Assert the same ready summaries remain blocked when P2-P5 verification statuses are not verified.

## Non-goals

- Do not mark real verification gates as passed.
- Do not run tests in this task.
- Do not claim advanced P2-P5 gaps are complete.

## Acceptance

- The manifest builder preserves the distinction between ready core wiring and verified closure.
- Cross-milestone closure remains blocked by tests/static analysis when verification statuses are absent.

## Verification Commands

- `flutter test example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart`

## Result

Added focused regression coverage for P2-P5 core summary closure and verification blockers at the production manifest builder layer.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

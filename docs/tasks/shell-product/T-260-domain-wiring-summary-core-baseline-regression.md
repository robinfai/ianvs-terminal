# T-260 Domain wiring summary core baseline regression

## Goal

Add regression coverage for `LocalTerminalDomainWiringSummary` so P2-P5 core callback baselines summarize as ready while advanced gaps remain visible under all-operation contracts.

## Scope

- Update `example/test/shell/local_terminal_domain_wiring_summary_test.dart`.
- Build P2-P5 core baseline wiring with complete callbacks.
- Assert each summary is ready, has no missing operations, and can produce a closeable milestone manifest when tests/analysis are supplied.
- Build all-operation wiring with only core callbacks and assert representative advanced gaps remain visible.

## Non-goals

- Do not mark P2-P5 verified in real completion evidence.
- Do not run tests in this task.
- Do not claim advanced workspace/productivity/policy/visual gaps are complete.

## Acceptance

- Domain summaries preserve the current core-ready baseline across P2-P5.
- Advanced gaps remain visible at the cross-domain summary layer.

## Verification Commands

- `flutter test example/test/shell/local_terminal_domain_wiring_summary_test.dart`

## Result

Added focused regression coverage for P2-P5 core baseline summaries and advanced gap reporting.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Real milestone closure still requires executed and recorded verification evidence.

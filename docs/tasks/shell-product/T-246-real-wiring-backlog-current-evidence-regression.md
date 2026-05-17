# T-246 Real wiring backlog current evidence regression

## Goal

Add regression coverage for `LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified` so the current real-wiring backlog evidence cannot silently regress to pending placeholders.

## Scope

- Update `example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`.
- Assert T-164 through T-168 are blocked on verification in the current implemented-unverified factory.
- Assert T-169 remains controlled by verification evidence blockers.

## Non-goals

- Do not mark any wiring task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The direct backlog evidence factory is covered independently from `LocalTerminalCurrentCompletionState`.
- The test preserves the distinction between implemented-but-unverified wiring and verified closure.

## Verification Commands

- `flutter test example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`

## Result

Added direct regression coverage for the current implemented-but-unverified backlog evidence factory.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Full objective closure still requires the complete verification plan.

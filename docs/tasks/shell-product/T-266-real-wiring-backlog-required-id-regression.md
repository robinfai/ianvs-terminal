# T-266 Real wiring backlog required id regression

## Goal

Add regression coverage proving real-wiring backlog evidence builders emit every required T-164 through T-169 task id expected by the final completion evidence gate.

## Scope

- Update `example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`.
- Compare default backlog evidence task ids against `LocalTerminalCompletionEvidenceReport.requiredBacklogTaskIds`.
- Compare current implemented-but-unverified backlog evidence task ids against the same required id set.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The default backlog evidence builder emits all required task ids.
- The current implemented-but-unverified backlog evidence builder emits all required task ids.
- Future changes cannot accidentally omit T-165 through T-168 without focused test coverage failing.

## Verification Commands

- `flutter test example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`

## Result

Added focused regression coverage tying real-wiring backlog evidence builders to the final required backlog id gate.

## Verification

Not run. The test was updated but not executed in this session.

## Remaining Risks

- The updated test may require formatting.
- Real closure still requires executed and recorded verification evidence.

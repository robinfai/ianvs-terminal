# T-263 Completion evidence report required backlog gate

## Goal

Tighten final completion evidence so the objective cannot close unless every required real-wiring backlog task from T-164 through T-169 is present and verified.

## Scope

- Update `example/lib/features/shell/local_terminal_completion_evidence_report.dart`.
- Require T-164, T-165, T-166, T-167, T-168, and T-169 in `canCloseObjective`.
- Expose missing required backlog task ids in JSON.
- Update `example/test/shell/local_terminal_completion_evidence_report_test.dart`.

## Non-goals

- Do not mark any real backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- A clean production wiring bundle with only partial backlog evidence cannot close the objective.
- A clean production wiring bundle with all six required backlog tasks verified can close the objective.
- Missing required backlog task ids are visible in JSON diagnostics.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_evidence_report_test.dart`

## Result

`LocalTerminalCompletionEvidenceReport` now requires all T-164 through T-169 backlog task ids before `canCloseObjective` can return true.

## Verification

Not run. The test was updated but not executed in this session.

## Remaining Risks

- The updated test may require formatting.
- Real closure still requires executed and recorded verification evidence.

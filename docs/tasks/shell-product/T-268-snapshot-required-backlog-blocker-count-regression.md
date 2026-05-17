# T-268 Snapshot required backlog blocker count regression

## Goal

Add regression coverage proving shell UI wiring snapshots expose the final required backlog blocker count.

## Scope

- Update `example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart`.
- Assert `blockedBacklogItemCount` mirrors `LocalTerminalCompletionEvidenceReport.requiredBacklogBlockerCount`.
- Assert the JSON payload exports the same count.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- Snapshot count semantics stay aligned with final completion evidence report semantics.
- UI diagnostics do not regress to counting only explicitly blocked backlog items.

## Verification Commands

- `flutter test example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart`

## Result

Added focused snapshot regression coverage for the required backlog blocker count.

## Verification

Not run. The test was updated but not executed in this session.

## Remaining Risks

- The updated test may require formatting.
- Real closure still requires executed and recorded verification evidence.

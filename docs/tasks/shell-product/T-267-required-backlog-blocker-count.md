# T-267 Required backlog blocker count

## Goal

Ensure completion diagnostics count both blocked backlog items and missing required real-wiring backlog task ids.

## Scope

- Update `LocalTerminalCompletionEvidenceReport` with `requiredBacklogBlockerCount`.
- Include the count in report JSON.
- Use the count for `LocalTerminalShellUiWiringSnapshot.blockedBacklogItemCount`.
- Update completion evidence report tests.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- Partial backlog evidence reports missing required ids as blocker count.
- Pending/blocked backlog evidence still contributes to the same count.
- Snapshot backlog blocker count no longer undercounts missing required ids.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_evidence_report_test.dart example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart`

## Result

Added a required backlog blocker count and wired shell UI snapshots to use it.

## Verification

Not run. The tests were updated but not executed in this session.

## Remaining Risks

- The updated tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

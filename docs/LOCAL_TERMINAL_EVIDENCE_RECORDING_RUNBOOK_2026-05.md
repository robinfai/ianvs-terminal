# Local Terminal Evidence Recording Runbook

Date: 2026-05-16

Purpose: define the operational steps for turning real production wiring and
verification output into final completion evidence for T-169.

This runbook does not claim that any evidence has been collected.

## Preconditions

- T-164 through T-168 production wiring is implemented.
- `LocalTerminalProductionWiringBundle.fromDomainCallbacks(...)` can be built
  from real callbacks.
- `LocalTerminalVerificationPlanRecords.defaultPending()` is available as the
  starting point for required verification gates. Its default records expose
  the current all-automated, broader, and macOS integration command metadata.
- `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md`,
  `docs/LOCAL_TERMINAL_TEST_TARGETS_2026-05.md`, and
  `docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` are available.
- `docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md` is available
  for recording real command and manual results before conversion into code
  evidence.
- `docs/LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md` is available
  for converting filled ledger rows into `LocalTerminalVerificationGateRecord`
  values.
- `docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md` is available as
  the single operator handoff for final verification execution.

## Recording sequence

1. Build the production wiring bundle from real callbacks.
2. Rerun the currently blocked broader batch:
   `bash tools/local_terminal_verification_capture.sh run broader`.
3. If broader passes, either rerun all automated gates with
   `bash tools/local_terminal_verification_capture.sh run all-automated` or
   explicitly carry forward the same-session focused-batch evidence already
   recorded in the ledger.
4. Run the macOS integration batch:
   `bash tools/local_terminal_verification_capture.sh run integration`.
5. Fill the manual verification template with real observed results.
6. Record command/manual results in the verification evidence ledger.
7. Convert each command/manual result into a `LocalTerminalVerificationGateRecord`.
8. Start from `LocalTerminalVerificationPlanRecords.defaultPending()`.
9. Apply all real records with `LocalTerminalVerificationEvidenceRecorder.recordAll(...)`.
10. Convert verification evidence to T-169 backlog evidence with
   `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)`.
11. Mark T-164 through T-168 backlog items verified only after their production
   wiring acceptance criteria and verification evidence are satisfied.
12. Build `LocalTerminalRealWiringBacklogEvidence`.
13. Build `LocalTerminalCompletionEvidenceReport`.
14. Update `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` with
    real evidence references.

## Gate-to-record mapping

| Gate | Record source | Status rule |
| --- | --- | --- |
| Formatting | Expanded `dart format` output covering app, integration/test-driver/tool files, and local packages | `passed` only if command exits cleanly after final edits. |
| Static analysis | `flutter analyze` output | `passed` only if analyzer has no blocking issues. |
| Unit tests | `bash tools/local_terminal_verification_capture.sh run all-automated` or carried-forward focused evidence plus a successful `broader` rerun | `passed` only if required focused and broader unit scopes pass. |
| Widget tests | `bash tools/local_terminal_verification_capture.sh run broader` output plus focused diagnostics evidence | `passed` only if UI focus/diagnostic behavior passes after the latest visibility fix. |
| Integration tests | `bash tools/local_terminal_verification_capture.sh run integration` output | `passed` only if the macOS-targeted app smoke and real PTY acceptance targets pass. |
| Manual local shell smoke | Filled manual template | `passed` only if every required smoke row is successful. |
| Manual paste/focus safety | Filled manual template | `passed` only if policy/focus rows are successful. |
| Manual multipane behavior | Filled manual template | `passed` only if pane/focus/empty-state rows are successful. |
| Manual notification behavior | Filled manual template | `passed` only if focus/target policy rows are successful. |
| Manual hotkey-window failure path | Filled manual template | `passed` only if success or visible failure state is observed. |

## Failure handling

- If a command fails, record the gate as `failed` with the failing output lines.
- If a manual gate cannot be executed, record it as `skipped`; it remains a
  blocker unless scope is explicitly changed.
- If a gate is not attempted, leave it as `pending`.
- Do not remove a required gate to force closure.
- Do not mark T-169 verified until every required gate is `passed`.

## Final closure check

The objective can close only when:

- `LocalTerminalCompletionEvidenceReport.canCloseObjective == true`.
- `LocalTerminalProductionWiringManifest.canCloseAll == true`.
- T-164 through T-169 backlog items are all `verified`.
- `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` contains real
  evidence references for every required row.

## Current status

Verification execution has captured evidence in
`build/local-terminal-verification/20260516T145142Z-all-automated` plus latest
reruns. Formatting, static analysis, focused completion/P1/P2-P5/
cross-milestone, and verification-evidence batches passed. Latest `broader`
passed in `build/local-terminal-verification/20260516T171406Z-broader` and
latest integration passed in
`build/local-terminal-verification/20260516T171644Z-integration`.
Manual/integration-backed gates have passing ledger evidence. The remaining
work is converting ledger rows into canonical evidence records.

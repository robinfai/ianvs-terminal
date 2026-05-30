# Local Terminal Final Verification Handoff

Date: 2026-05-16

Purpose: give the final operator a single entry point for executing the
remaining verification loop for the local terminal objective.

This handoff is not verification evidence. It must not be used to mark T-169 or
the overall objective complete.

## Current Completion State

Current decision: **verified**.
Verification execution was authorized on 2026-05-16 and automated batches were
run through the capture helper. The latest successful evidence directories are
`build/local-terminal-verification/20260516T171224Z-static-analysis`,
`build/local-terminal-verification/20260516T171406Z-broader`, and
`build/local-terminal-verification/20260516T171644Z-integration`.

Optional navigation helper:

```sh
bash tools/local_terminal_verification_status.sh
```

The helper prints verification handoff links only; it does not run verification.
All helper script side effects are indexed in
`LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md`.
Machine-readable verification metadata is available in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`.
Manifest maintenance rules are documented in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md`.

What exists:

- P0-P5 execution plans.
- Competitor coverage matrix.
- Completion audit checklist and current audit snapshot.
- Production wiring checklist and implementation status records.
- Real-wiring backlog gate for T-164 through T-169.
- Diagnostics surfaces for blocked and missing backlog evidence.
- Verification command plan, readiness checklist, evidence ledger, record
  examples, command batches, failure triage log, manual template, and evidence
  recording runbook.

Latest verification evidence:

- Formatting passed; the latest expanded 2026-05-31 scope audit reported
  `Formatted 287 files (0 changed)`.
- Latest static analysis passed with `No issues found!` in
  `20260516T171224Z-static-analysis`.
- Focused completion diagnostics passed 45/45.
- P1 action wiring passed 33/33.
- Cross-milestone production wiring passed 8/8.
- P2 workspace passed 21/21.
- P3 productivity passed 26/26.
- P4 policy passed 22/22.
- P5 visual passed 33/33.
- Verification evidence passed 13/13 in
  `20260516T171327Z-verification-evidence`.
- Latest broader `flutter test example/test` passed with 601 passing tests plus
  1 skipped test in `20260516T171406Z-broader`.
- Latest integration passed with smoke 4/4 and real PTY 7/7 in
  `20260516T171644Z-integration`.
- Manual/integration-backed gates are recorded as passed in the evidence
  ledger for local shell smoke, paste/focus safety, multipane behavior,
  notification behavior, and hotkey-window failure path.

What is still missing:

- No required T-169 closure evidence remains missing for the current
  local-terminal baseline.
- Optional advanced visual/productivity/policy hardening remains follow-up
  scope outside the required closure baseline.

## Required Reading Order

Before running verification, read:

1. `LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`
2. `LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md`
3. `LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md`
4. `LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`
5. `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`
6. `LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`
7. `LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md`
8. `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`

## Execution Sequence

Current execution sequence:

1. Automated focused evidence has been captured in
   `build/local-terminal-verification/20260516T145142Z-all-automated`.
2. Broader test evidence has been captured in
   `build/local-terminal-verification/20260516T171406Z-broader`.
3. Integration evidence has been captured in
   `build/local-terminal-verification/20260516T171644Z-integration`.
4. Manual/integration-backed gates have been recorded in the ledger.
5. Ledger entries have been converted into
   `LocalTerminalVerificationGateRecord` values by
   `LocalTerminalVerificationPlanRecords.latestPassed()`.
6. Verification evidence is rebuilt through
   `LocalTerminalVerificationPlanRecords.latestPassed().toRecorder()`.
7. T-169 evidence is rebuilt from the verified verification evidence.
8. T-164 through T-168 are verified by
   `LocalTerminalRealWiringBacklogEvidence.currentVerified(...)`.
9. The completion evidence report is rebuilt by
   `LocalTerminalCurrentCompletionState.verified(...)`.
10. The completion audit checklist references the final code evidence.

Optional helper:

```sh
bash tools/local_terminal_verification_batches.sh list
bash tools/local_terminal_verification_batches.sh print all-automated
bash tools/local_terminal_verification_batches.sh run all-automated
```

Use the helper only when verification execution is explicitly allowed. It does
not record evidence automatically.

To capture future run output for ledger entry:

```sh
bash tools/local_terminal_verification_capture.sh run all-automated
```

Captured output still must be summarized in the evidence ledger, and failures
must be triaged in the failure log. Future captured runs also write a
`ledger-entry.md` template next to `output.log`; keep its gate status pending
until the output satisfies the gate rule.

## Stop Conditions

Stop and record a blocker if:

- Formatting fails.
- Static analysis fails.
- A focused test batch fails.
- Broader tests fail and the failure is relevant to P0-P5 closure.
- An integration or manual gate cannot be executed.
- A manual gate reveals a product behavior mismatch.
- Any required verification gate remains pending, failed, or skipped.
- A required verification command cannot be executed.

Do not skip a failed earlier batch and continue to claim closure.
Record failed batches in
`LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.

## Closure Criteria

The objective can be considered for closure only when:

- Every required verification gate is recorded as `passed`.
- T-164 through T-169 backlog evidence is present and verified.
- `LocalTerminalCompletionEvidenceReport.canCloseObjective == true`.
- `LocalTerminalProductionWiringManifest.canCloseAll == true`.
- The audit checklist contains real evidence references for every required row.
- No known blocker remains.

## Final Report Shape

When the verification loop completes, report:

- Commands run.
- Exit statuses.
- Tests passed or failed.
- Manual gates passed or failed.
- Ledger updates.
- T-164 through T-169 evidence status.
- Whether the completion report can close.
- Remaining risks.

If anything fails, report the first blocking failure and the smallest next fix.

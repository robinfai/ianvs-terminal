# Local Terminal Verification Readiness Checklist

Date: 2026-05-16

Purpose: record whether each required verification gate has an executable
entry point and what evidence is still missing before the local terminal
objective can close.

This checklist does not run verification and does not claim any gate passed.
It complements `LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md`.
Real command and manual results should be recorded in
`LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
Conversion examples are documented in
`LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`.
Copy-ready command batches are documented in
`LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`.

## Readiness Legend

| State | Meaning |
| --- | --- |
| Ready to run | Command or manual template exists, and the remaining work is to execute and record results. |
| Partially ready | Some entry points exist, but scope or evidence capture still needs tightening before closure. |
| Not ready | No sufficient execution or evidence path exists yet. |
| Passed | Real passing evidence has been recorded. |

## Gate Readiness

| Required gate | Entry point | Readiness | Missing before closure |
| --- | --- | --- | --- |
| Formatting | `dart format example/lib example/test` from `LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` | Passed | `build/local-terminal-verification/20260516T145142Z-all-automated`: `Formatted 252 files (0 changed)`. |
| Static analysis | `flutter analyze` from `LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` | Passed | `build/local-terminal-verification/20260516T145142Z-all-automated`: `No issues found!`. |
| Completion evidence tests | `example/test/shell/local_terminal_*completion*_test.dart` plus explicit diagnostics files from T-245 through T-272 | Passed | Focused completion suite passed 45/45 in `20260516T145142Z-all-automated`. |
| P1 action wiring tests | `example/test/shell/shell_action_*test.dart` plus action-domain router/domain summary tests | Passed | Focused P1 suite passed 33/33 in `20260516T145142Z-all-automated`. |
| P2 workspace tests | `example/test/workspace` | Passed | P2 workspace suite passed 21/21 in `20260516T145142Z-all-automated`. |
| P3 productivity tests | `example/test/productivity` | Passed | P3 productivity suite passed 26/26 in `20260516T145142Z-all-automated`. |
| P4 policy tests | `example/test/policies` | Passed | P4 policy suite passed 22/22 in `20260516T145142Z-all-automated`. |
| P5 visual tests | `example/test/visual` | Passed | P5 visual suite passed 33/33 in `20260516T145142Z-all-automated`. |
| Verification evidence tests | `example/test/shell/local_terminal_verification_*test.dart` | Passed | Verification-evidence suite passed 10/10 in `20260516T145142Z-all-automated`. |
| UI diagnostics widget tests | `example/test/shell/local_terminal_completion_diagnostics_panel_test.dart` and related diagnostics tests | Passed | Focused diagnostics passed in `20260516T145142Z-all-automated`; broader widget coverage passed in `20260516T171406Z-broader`. |
| Broader project tests | `flutter test example/test` | Passed | `build/local-terminal-verification/20260516T171406Z-broader`: exit 0; 600 passing tests plus 1 skipped test; `All tests passed!`. |
| Automated integration smoke | `bash tools/local_terminal_verification_capture.sh run integration` | Passed | `build/local-terminal-verification/20260516T171644Z-integration`: exit 0; smoke 4/4 and real PTY acceptance 7/7 passed. Optional `vttest_gui_test.dart` remains external-binary supplement only. |
| Local shell smoke | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | Passed | Manual/integration-backed ledger evidence records local shell launch, command output, tab/split, and close recovery. |
| Paste/focus safety | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | Passed | Manual/integration-backed ledger evidence records multiline confirmation, read-only block, focus path, and automated paste policy coverage. |
| Multipane behavior | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | Passed | Manual/integration-backed ledger evidence records split/focus/resize/swap, zoom fix coverage, and close recovery. |
| Notification behavior | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | Passed | Broader and real PTY evidence cover command-finished, bell, activity, trigger notification, wrapped preview, and focus/target policy. |
| Hotkey-window failure path | `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` | Passed | Broader evidence covers bridge invocation plus simulated unregistered status with visible `Hotkey window unavailable` feedback. |
| Evidence recording | `LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md` and `LocalTerminalVerificationEvidenceRecorder` | Ready to run after verification | Recorded gate statuses with command/manual evidence still need conversion into T-169 backlog evidence. |

## Current Readiness Decision

The project has passing evidence for formatting, static analysis, focused
automated gates, broader `flutter test example/test`, and macOS integration.
The objective is not ready to close because the captured evidence still needs
conversion into canonical verification records.

The manual/integration-backed gates have passing ledger evidence, including
notification and hotkey-window simulation notes.

## Closure Guard

Do not mark T-169, the real-wiring backlog, or the overall objective complete
from this checklist alone. A gate moves from ready to passed only after real
command output or manual observation is recorded and converted into
`LocalTerminalVerificationEvidence`.

## Recommended Execution Order

Use the same sequence as the command plan:

1. Rerun broader project tests with
   `bash tools/local_terminal_verification_capture.sh run broader`.
2. Run integration/smoke with
   `bash tools/local_terminal_verification_capture.sh run integration`.
3. Run manual gates.
4. Convert evidence ledger rows into verification evidence.
5. Rebuild T-169, T-164 through T-168, and final completion report evidence.

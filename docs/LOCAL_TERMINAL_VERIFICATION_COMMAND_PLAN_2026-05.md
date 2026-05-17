# Local Terminal Verification Command Plan

Date: 2026-05-16

Purpose: define the concrete verification evidence needed before T-169 and the
overall local terminal objective can close.

This plan does not run verification. It defines what must be run and what
evidence must be recorded after production wiring is complete.

Verification readiness, including which gates are ready to run versus merely
planned, is tracked in
`LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md`.
Real command and manual outputs should be written into
`LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md` before converting them
into code evidence records.
Conversion examples are documented in
`LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`.
Copy-ready command batches are documented in
`LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`.
The full final verification handoff is
`LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md`.

## Verification rule

Required gates must be recorded as `passed` in
`LocalTerminalVerificationEvidence`. Pending, failed, skipped, or missing gates
remain blockers.

## Command gates

| Gate | Command | Required evidence | Notes |
| --- | --- | --- | --- |
| Formatting | `dart format example/lib example/test` | Command exits successfully after production wiring edits | Run after final code edits, not before. |
| Static analysis | `flutter analyze` | Command exits successfully with zero blocking analyzer issues | Run from repository root unless project conventions require `example/`. |
| Unit tests | Focused `flutter test` commands for shell/config/workspace/productivity/policies/visual foundation and wiring tests plus `flutter test example/test` broader scope | Passing test output covering P0-P5 closure/manifests/callback gates | Focused groups passed in `20260516T145142Z-all-automated`; latest broader passed in `20260516T171406Z-broader`. |
| Widget tests | Existing shell widget tests plus new command-menu/shortcut/focus diagnostics tests, including broader `example/test` widget coverage | Passing output showing UI actions do not leak input and diagnostics render correctly | Focused diagnostics passed; latest broader widget coverage passed in `20260516T171406Z-broader`. |
| Integration tests | `bash tools/local_terminal_verification_capture.sh run integration` | Passing output for app smoke plus macOS real PTY lifecycle behavior | Passed in `20260516T171644Z-integration`. The batch builds debug `native/core`, runs from `example` so desktop plugins are registered, and executes the two macOS integration files sequentially. Optional `vttest_gui_test.dart` remains external-binary supplement only. |

## Manual or integration gates

| Gate | Scenario | Required evidence |
| --- | --- | --- |
| Local shell smoke | Launch local `/bin/zsh` or `/bin/bash`, create/close tab, split pane, run a simple command | Recorded result with date, shell, and observed behavior. |
| Paste/focus safety | Test paste, multiline paste, large paste confirmation, read-only paste block, focus preservation | Recorded result showing policy cannot be bypassed. |
| Multipane behavior | Split, focus next/previous, resize, swap, zoom, close pane, close last pane/tab | Recorded result showing focus fallback and empty state behavior. |
| Notification behavior | Bell, command-finished, activity, silence/prompt-ready where configured | Recorded result showing focus policy and notification target policy are honored. |
| Hotkey-window failure path | Trigger hotkey window success or simulate/observe permission/platform failure | Recorded result showing failure state is visible instead of silent. |

## Evidence mapping

| Evidence item | Target model field |
| --- | --- |
| Test command output | `LocalTerminalVerificationEvidenceItem.evidence` |
| Analyzer output | `LocalTerminalVerificationEvidenceItem.evidence` |
| Format output | `LocalTerminalVerificationEvidenceItem.evidence` |
| Manual test notes | `LocalTerminalVerificationEvidenceItem.notes` |
| Known unresolved issue | `LocalTerminalVerificationEvidenceItem.status = failed` plus evidence/notes |
| Explicitly deferred required gate | Keep status `skipped`; it remains a blocker until scope is changed |

## Closure sequence

1. Complete T-164 through T-168 production wiring.
2. Run formatting.
3. Run static analysis.
4. Run focused unit tests.
5. Run widget and integration tests.
6. Execute manual/integration gates.
7. Populate `LocalTerminalVerificationEvidence`.
8. Convert verification evidence to T-169 through
   `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)`.
9. Build `LocalTerminalCompletionEvidenceReport`.
10. Update `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` with real
    command/manual evidence.

## Current status

Verification was authorized and partially executed. Formatting, static
analysis, focused completion, P1, cross-milestone, P2, P3, P4, P5, and
verification-evidence batches have passing captured evidence in
`build/local-terminal-verification/20260516T145142Z-all-automated`.

The remaining automated blocker has been resolved. Latest broader passed in
`20260516T171406Z-broader`, integration/smoke passed in
`20260516T171644Z-integration`, and manual/integration-backed gates are recorded
as passed in the evidence ledger. Canonical evidence conversion remains.

## Added focused test target mapping

Use `docs/LOCAL_TERMINAL_TEST_TARGETS_2026-05.md` to choose focused test groups for P0-P5 foundation, production wiring, diagnostics, and verification artifacts. Focused tests are useful triage evidence, but final closure still requires every required verification gate to pass.

T-245 adds a specific focused regression in
`example/test/shell/local_terminal_current_completion_state_test.dart` for the
implemented-but-unverified T-164 through T-168 backlog evidence. Include it in
the first focused completion-test command.

T-246 adds direct regression coverage in
`example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart` for
the same implemented-but-unverified backlog evidence factory. Include it in the
first focused completion-test command as well.

T-247 adds snapshot-factory regression coverage in
`example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart`
so UI diagnostics surfaces preserve the same current evidence. Include it in the
first focused completion-test command as well.

T-248 adds facade-report regression coverage in
`example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart` for the
same current evidence. Include it in the first focused completion-test command
as well.

T-249 adds P1 default action-set baseline regression coverage in
`example/test/shell/shell_action_production_action_set_test.dart`. Include it in
the focused P1 action wiring command.

T-250 adds typed production callback baseline regression coverage in
`example/test/shell/shell_action_production_callbacks_test.dart`. Include it in
the focused P1 action wiring command.

T-251 adds production wiring-state baseline regression coverage in
`example/test/shell/shell_action_production_wiring_state_test.dart`. Include it
in the focused P1 action wiring command.

T-252 adds production executor baseline regression coverage in
`example/test/shell/shell_action_production_executor_test.dart`. Include it in
the focused P1 action wiring command.

T-253 adds production runtime-adapter baseline regression coverage in
`example/test/shell/shell_action_production_runtime_adapter_test.dart`. Include
it in the focused P1 action wiring command.

T-254 adds production wiring-report and audit-snapshot baseline regression
coverage in `example/test/shell/shell_action_production_wiring_report_test.dart`
and `example/test/shell/shell_action_production_audit_snapshot_test.dart`.
Include them in the focused P1 action wiring command.

T-255 adds production closure-manifest baseline regression coverage in
`example/test/shell/shell_action_production_closure_manifest_test.dart`. Include
it in the focused P1 action wiring command.

T-256 adds P2 workspace production callback baseline regression coverage in
`example/test/workspace/local_workspace_production_callbacks_test.dart`. Include
it in the focused P2 workspace wiring command.

T-257 adds P3 productivity production callback baseline regression coverage in
`example/test/productivity/shell_productivity_production_callbacks_test.dart`.
Include it in the focused P3 productivity wiring command.

T-258 adds P4 policy production callback baseline regression coverage in
`example/test/policies/local_terminal_policy_production_callbacks_test.dart`.
Include it in the focused P4 policy wiring command.

T-259 adds P5 visual production callback baseline regression coverage in
`example/test/visual/local_terminal_visual_production_callbacks_test.dart`.
Include it in the focused P5 visual wiring command.

T-260 adds cross-domain summary baseline regression coverage in
`example/test/shell/local_terminal_domain_wiring_summary_test.dart`. Include it
with the focused P1/P2-P5 wiring evidence commands.

T-261 adds production wiring bundle baseline regression coverage in
`example/test/shell/local_terminal_production_wiring_bundle_test.dart`. Include
it with the focused cross-milestone wiring evidence commands.

T-262 adds production manifest builder baseline regression coverage in
`example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart`.
Include it with the focused cross-milestone wiring evidence commands.

T-263 adds final completion evidence required-backlog regression coverage in
`example/test/shell/local_terminal_completion_evidence_report_test.dart`.
Include it with the focused completion evidence command.

T-264 adds missing required backlog diagnostics coverage in
`example/test/shell/local_terminal_completion_summary_test.dart` and
`example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart`.
Include it with the focused completion diagnostics command.

T-265 adds missing required backlog downstream diagnostics coverage in
`example/test/shell/local_terminal_completion_diagnostics_actions_test.dart`,
`example/test/shell/local_terminal_completion_menu_model_test.dart`, and
`example/test/shell/local_terminal_completion_command_menu_adapter_test.dart`.
Include it with the focused completion diagnostics command.

T-266 adds required backlog id regression coverage in
`example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`.
Include it with the focused completion evidence command.

T-267 adds required backlog blocker-count coverage in
`example/test/shell/local_terminal_completion_evidence_report_test.dart` and
`example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart`. Include
it with the focused completion evidence and diagnostics commands.

T-268 adds explicit shell UI snapshot regression coverage in
`example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart` for the
required backlog blocker count. Include it with the focused completion
diagnostics command.

T-269 adds shell UI facade required backlog blocker-count coverage in
`example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart` and keeps
`example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart` aligned
with the facade getter. Include it with the focused completion diagnostics
command.

T-271 adds missing required backlog diagnostics coverage in
`example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart`,
`example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart`,
and `example/test/shell/local_terminal_completion_diagnostics_panel_test.dart`.
Include it with the focused completion diagnostics command.

T-272 adds missing required backlog diagnostics coverage in
`example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart`.
Include it with the focused completion diagnostics command.

## Added manual verification template

Use `docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` to record local shell smoke, paste/focus safety, multipane behavior, notification behavior, and hotkey-window failure-path observations before converting them into `LocalTerminalVerificationGateRecord` values.

## Added evidence recording runbook

Use `docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md` after running verification commands and manual gates to convert real outputs into `LocalTerminalVerificationGateRecord`, T-169 backlog evidence, and the final completion evidence report.

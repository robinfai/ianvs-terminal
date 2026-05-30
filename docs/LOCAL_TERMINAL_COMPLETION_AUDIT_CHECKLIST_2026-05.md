# Local Terminal Completion Audit Checklist

Date: 2026-05-16

Objective being audited: advance and complete all local terminal milestone plans.

This checklist is the completion gate for the P0-P5 local terminal execution
plan. It maps the explicit planning requirements, implementation artifacts,
production wiring gates, and verification gates to concrete evidence. It should
be filled from real file state and command output before claiming the objective
is complete.

Current audit snapshot: `LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md`.
Verification readiness: `LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md`.
Verification evidence ledger: `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
Verification record examples: `LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`.
Final verification handoff: `LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md`.

## Completion rule

The objective is complete only when every required row below has concrete
evidence and no blocker. Foundation artifacts are useful evidence, but they do
not close a row unless the row explicitly asks only for foundation work.

## Prompt-to-artifact checklist

| Requirement | Required evidence | Current evidence | Status | Blocker |
| --- | --- | --- | --- | --- |
| One execution plan per milestone | `docs/LOCAL_TERMINAL_P0_EXECUTION_PLAN_2026-05.md` through `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md` | P0-P5 plan docs exist, are indexed by `docs/LOCAL_TERMINAL_EXECUTABLE_PLAN_2026-05.md`, and are covered by the verified P0 boundary manifest in `LocalTerminalCurrentCompletionState.verified` | Verified | None. |
| Competitor-derived features covered | `docs/LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md` | Coverage matrix maps competitor signals to P0-P5, tasks, artifacts, wiring status, and follow-up scope; required closure baseline is verified by ledger, latest broader, and integration evidence | Verified | Advanced follow-ups remain outside the current closure baseline. |
| P0 local-terminal boundaries closed | `LocalTerminalP0BoundaryClosureManifest` and reviewed docs | `local_terminal_p0_boundary_closure_manifest.dart` defines the closure state; `LocalTerminalCurrentCompletionState.verified` uses all required P0 boundary flags and verified milestone status | Verified | None. |
| P1 action/config production closure | `ShellActionProductionClosureManifest` and `LocalTerminalProductionMilestoneManifest.p1ActionConfig` | Action registry, config, binding, diagnostics, report, snapshot, closure manifest artifacts, default action-set baseline regression coverage from T-249, typed callback baseline regression coverage from T-250, wiring-state baseline regression coverage from T-251, executor baseline regression coverage from T-252, runtime-adapter baseline regression coverage from T-253, report/snapshot baseline regression coverage from T-254, closure-manifest baseline regression coverage from T-255, and `ShellScreen` production command/shortcut dispatch are wired through the current required baseline; focused P1 automated evidence passed in `build/local-terminal-verification/20260516T145142Z-all-automated`; latest broader and integration reruns passed in `20260516T171406Z-broader` and `20260516T171644Z-integration`; manual command-menu observations were recorded in the evidence ledger | Verified in ledger | Canonical evidence conversion is recorded by `LocalTerminalVerificationPlanRecords.latestPassed()`. |
| P2 workspace production closure | `LocalWorkspaceProductionWiring` converted through `LocalTerminalDomainWiringSummary` | Workspace models/reducers/repositories exist; `SessionController` and `ShellScreen` now wire tab, split, focus, close, resize, swap, zoom, duplicate-cwd, and reopen-closed-tab behavior; T-256 adds core callback baseline regression coverage while preserving advanced layout gaps; manual split/focus/grow/swap was observed; zoom was fixed and covered by focused phase4 plus latest broader; integration smoke covers close/empty-state recovery | Verified in ledger | Canonical evidence conversion is recorded by `LocalTerminalVerificationPlanRecords.latestPassed()`. |
| P3 productivity production closure | `ShellProductivityProductionWiring` converted through `LocalTerminalDomainWiringSummary` | Productivity models/reducers/runtime controller exist; search, prompt navigation, command-output copy/select, recent directory, paste history, instant replay, read-only, autocomplete, auto composer, clear scrollback, and scrollback export dispatch are wired; T-257 adds core callback baseline regression coverage while preserving advanced productivity gaps; manual paste/read-only/focus observations and latest broader coverage verify the current baseline | Verified in ledger | Canonical evidence conversion is recorded by `LocalTerminalVerificationPlanRecords.latestPassed()`. |
| P4 policy production closure | `LocalTerminalPolicyProductionWiring` converted through `LocalTerminalDomainWiringSummary` | Policy models/reducers/dispatcher exist; read-only enforcement, advanced paste/paste history paths, notification toggles, and persisted notification preferences are wired; T-258 adds core callback baseline regression coverage while preserving advanced policy gaps; multiline paste confirmation, read-only paste block, notification behavior, and hotkey-window visible failure are now verified by manual/integration-backed ledger evidence and latest broader coverage | Verified in ledger | Canonical evidence conversion is recorded by `LocalTerminalVerificationPlanRecords.latestPassed()`. |
| P5 visual production closure | `LocalTerminalVisualProductionWiring` converted through `LocalTerminalDomainWiringSummary` | Visual models/repositories/exporter/applier exist; theme picker, two-pane layout template, pane sizing/zoom, historical scrollback export, and clear-scrollback runtime/native plumbing are wired; T-259 adds core callback baseline regression coverage while preserving advanced visual gaps; pane layout/zoom and theme/export baseline coverage passed in latest broader | Verified in ledger | Advanced visual follow-ups remain out of closure baseline; canonical evidence conversion is recorded by `LocalTerminalVerificationPlanRecords.latestPassed()`. |
| Cross-milestone closure gate | `LocalTerminalProductionWiringManifestBuilder` output with `canCloseAll: true` | Builder and manifest exist; `LocalTerminalCurrentCompletionState.verified` builds a closeable bundle and `LocalTerminalCompletionEvidenceReport.canCloseObjective` is covered by focused tests | Closed | None. |
| Required real-wiring backlog gate | `LocalTerminalCompletionEvidenceReport.requiredBacklogTaskIds` and `canCloseObjective` | T-164 through T-169 are present and verified through `LocalTerminalRealWiringBacklogEvidence.currentVerified`, `LocalTerminalVerificationPlanRecords.latestPassed()`, and focused `canCloseObjective` regression coverage | Closed | None. |
| Production wiring checklist satisfied | `docs/LOCAL_TERMINAL_PRODUCTION_WIRING_CHECKLIST_2026-05.md` rows closed with evidence | Current task records T-230 and T-239 show no known action-level implementation blocker for the required baseline; final verification and current verified backlog evidence are recorded | Verified | None. |
| Unit tests passed | Relevant `flutter test` / `dart test` output covering P0-P5 foundation, production wiring artifacts, and terminal packages | Focused completion/P1/P2-P5/cross-milestone/verification-evidence suites passed in `build/local-terminal-verification/20260516T145142Z-all-automated`; latest broader `bash tools/local_terminal_verification_capture.sh run broader` passed in `build/local-terminal-verification/20260516T171406Z-broader` with 601 passing tests plus 1 skipped test; latest verification-evidence rerun passed 13/13 in `build/local-terminal-verification/20260516T171327Z-verification-evidence`; 2026-05-31 package audit passed `flutter test packages/ianvs_terminal/test` 92/92 and `dart test packages/ianvs_pty/test` 8/8; latest focused current-state/facade verification tests passed after `currentVerified` wiring | Passed | None. |
| Static analysis passed | `flutter analyze` or equivalent output after production wiring | Latest rerun after paste, zoom, hotkey visible-failure, and verified completion-state changes passed: `No issues found!`; captured static-analysis evidence remains `build/local-terminal-verification/20260516T171224Z-static-analysis` | Passed | None. |
| Formatting is clean | Expanded `dart format` output after edits | `build/local-terminal-verification/20260516T145142Z-all-automated`: `Formatted 252 files (0 changed)`; later touched files were individually formatted, and the 2026-05-31 scope audit confirmed app, integration/test-driver/tool, and package formatting with `Formatted 287 files (0 changed)` | Passed/updated | None. |
| Manual/integration gates complete | Smoke/manual evidence from `docs/LOCAL_TERMINAL_FEATURE_PLAN.md` test plan | Latest integration passed in `build/local-terminal-verification/20260516T171644Z-integration`: macOS smoke 4/4 and real PTY acceptance 7/7. Manual/integration-backed ledger rows are passed for local shell smoke, paste/focus safety, multipane behavior, notification behavior, and hotkey-window failure path. | Passed | None. |

## Required completion evidence

Before marking the objective complete, collect all of the following:

1. A populated `LocalTerminalP0BoundaryClosureManifest` with documentation
   review evidence.
2. A populated `ShellActionProductionClosureManifest` with real production
   callbacks and passing verification.
3. P2-P5 `LocalTerminalDomainWiringSummary` values from real production wiring,
   not placeholders.
4. A `LocalTerminalProductionWiringManifestBuilder` result with `canCloseAll:
   true`.
5. Passing test output for the relevant unit/widget/integration scope.
6. Passing static analysis output.
7. Formatting confirmation after all code edits.
8. Manual or integration evidence for local shell smoke, paste/focus safety,
   multipane behavior, notification behavior, and hotkey-window failure paths.

## Current conclusion

The required local-terminal closure baseline is verified. Current state has
broad P0-P5 planning, foundation, production callback contracts, closure
manifests, audit checklists, core production UI/runtime wiring for the required
local-terminal surface, passing automated, integration, and
manual/integration-backed evidence, canonical verification records through
`LocalTerminalVerificationPlanRecords.latestPassed()`, and a closeable
`LocalTerminalCurrentCompletionState.verified(...)` report.

Selected advanced visual/productivity/policy hardening remains follow-up scope
outside the required closure baseline.

## Added real wiring backlog dependency

The next required execution surface is `docs/LOCAL_TERMINAL_REAL_WIRING_BACKLOG_2026-05.md`.
T-164 through T-169 must be completed before this audit checklist can be marked closed.

## Added completion evidence report gate

Final closure should use `example/lib/features/shell/local_terminal_completion_evidence_report.dart`. The objective cannot close unless `canCloseObjective` is true, which requires a closeable production wiring bundle and verified backlog items.

## Added real wiring backlog evidence gate

Final closure should build backlog evidence through `example/lib/features/shell/local_terminal_real_wiring_backlog_evidence.dart`. T-164 through T-169 default to pending and must be explicitly marked verified with evidence before `canCloseObjective` can pass.

## Added ShellScreen wiring spec dependency

T-164 through T-168 should follow `docs/LOCAL_TERMINAL_SHELLSCREEN_WIRING_SPEC_2026-05.md` when populating production callbacks. The spec is not closure evidence by itself; it defines the production targets and required evidence.

## Added verification evidence gate

T-169 verification should record command/manual outcomes through `example/lib/features/shell/local_terminal_verification_evidence.dart`. Required gates are not closed by being skipped or omitted; they must be passed or remain blockers.

## Added verification backlog bridge gate

T-169 backlog evidence should be created from `LocalTerminalVerificationEvidence` through `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)`. Pending, failed, or skipped required verification gates must remain blockers in the final completion evidence report.

## Added default verification gate dependency

T-169 should initialize verification with `LocalTerminalVerificationEvidence.defaultRequiredPending(...)` so unit, widget, integration, manual, static-analysis, and formatting gates all start as explicit blockers until real evidence is recorded.

## Added current completion state gate

Diagnostic tooling can use `example/lib/features/shell/local_terminal_current_completion_state.dart` to render the current blocked state. It is intentionally conservative and does not close the objective without explicit production wiring and verification evidence.

## Added completion summary gate

Diagnostic output can use `example/lib/features/shell/local_terminal_completion_summary.dart` to show blocked milestones, blocked real-wiring backlog items, and blocked verification gates. Summary output is explanatory only; it does not replace real wiring or verification evidence.

## Added completion controller diagnostic entry

Diagnostic surfaces can use `example/lib/features/shell/local_terminal_completion_controller.dart` to expose the current blocked state and summary. This controller is not completion evidence unless it is backed by real production wiring and verification evidence.

## Added completion diagnostics view model

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_view_model.dart` to present blocked milestones, blocked real-wiring tasks, and blocked verification gates. It is explanatory only and does not replace real completion evidence.

## Added completion diagnostics action surface

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_actions.dart` to display blocked completion state as read-only items. This surface is explanatory only and does not satisfy production wiring or verification evidence by itself.

## Added completion menu model

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_menu_model.dart` to render blocked completion state in a command menu or developer panel. This remains explanatory and does not replace real production wiring or verification evidence.

## Added completion command-menu adapter

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_command_menu_adapter.dart` to render blocked completion state as grouped command-menu sections. This adapter is explanatory only and does not satisfy production wiring or verification evidence by itself.

## Added completion diagnostics bundle

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_bundle.dart` as the single read-only entry point for blocked completion summary, menu model, command-menu sections, and JSON output. It remains explanatory only and does not replace real production wiring or verification evidence.

## Added completion shell command-menu diagnostics adapter

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_shell_command_menu_diagnostics.dart` to reuse command-menu disabled-reason rendering for blocked completion entries. This is explanatory only and does not replace real production wiring or verification evidence.

## Added verification command plan dependency

T-169 should follow `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` when collecting test, analysis, formatting, manual, and integration evidence. The plan itself is not passing evidence.

## Added shell UI wiring facade

Future ShellScreen diagnostics can use `example/lib/features/shell/local_terminal_shell_ui_wiring_facade.dart` after real production callbacks are populated. The facade is read-only and is not closure evidence without real wiring and verification data.

## Added shell UI wiring snapshot

Diagnostic UI or logs can use `example/lib/features/shell/local_terminal_shell_ui_wiring_snapshot.dart` to expose blocked completion counts, summary text, and facade JSON. The snapshot is explanatory only and does not replace production wiring or verification evidence.

## Added Shell UI wiring handoff

Future production wiring should follow `docs/LOCAL_TERMINAL_SHELL_UI_WIRING_HANDOFF_2026-05.md` so ShellScreen uses the stable bundle/facade/snapshot/diagnostics surfaces. The handoff is not completion evidence by itself.

## Added Shell UI wiring export surface

Future production UI wiring should import high-level diagnostics and wiring objects through `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart` where possible. This export surface is not completion evidence by itself.

## Added completion diagnostics panel

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_panel.dart` to display blocked completion title, counts, and grouped diagnostics. This panel is explanatory only and does not replace real production wiring or verification evidence.

## Added completion diagnostics presentation model

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_presentation.dart` to keep display mode separate from completion evidence. This model is explanatory only and does not satisfy production wiring or verification evidence by itself.

## Added completion diagnostics presentation resolver

Diagnostic UI can use `example/lib/features/shell/local_terminal_completion_diagnostics_presentation_resolver.dart` to select presentation mode from a snapshot. This resolver is explanatory only and does not replace real production wiring or verification evidence.

## Added verification evidence recorder

T-169 can use `example/lib/features/shell/local_terminal_verification_evidence_recorder.dart` to record command/manual outcomes gate by gate. Recording evidence does not close verification unless every required gate is explicitly passed.

## Added verification batch recording

T-169 can use `LocalTerminalVerificationEvidenceRecorder.recordAll(...)` with `LocalTerminalVerificationGateRecord` values to apply multiple command/manual outcomes at once. Unrecorded required gates remain blockers.

## Added verification plan records

T-169 can initialize verification recording with `LocalTerminalVerificationPlanRecords.defaultPending()`, which mirrors the verification command plan and keeps every required gate pending until real evidence is recorded.

## Added pending completion snapshot factory

Diagnostic tooling can use `example/lib/features/shell/local_terminal_pending_completion_snapshot_factory.dart` to build the default blocked snapshot from verification command-plan records. This preserves required gate metadata but is not completion evidence.

## Added test target mapping

T-169 should use `docs/LOCAL_TERMINAL_TEST_TARGETS_2026-05.md` to map focused test commands to P0-P5 evidence. The mapping is not passing evidence; command output must still be recorded through verification evidence.

## Added manual verification template

T-169 manual/integration evidence should be recorded with `docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`. The template is not evidence until populated with real observed results.

## Added evidence recording runbook

Final closure should follow `docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md` when converting real production wiring, command output, and manual verification results into completion evidence. The runbook is not evidence by itself.

## Added ShellScreen first-patch checklist

The first production patch should follow `docs/LOCAL_TERMINAL_SHELLSCREEN_PATCH_CHECKLIST_2026-05.md`. Completing that diagnostics-only patch will not close the objective; it is an incremental production integration step before real action/domain callbacks and verification evidence.

## Added current wiring backlog evidence update

T-239 updates `example/lib/features/shell/local_terminal_current_completion_state.dart`
so T-164 through T-168 report implemented-but-unverified wiring evidence instead
of generic pending placeholders. This improves diagnostics but does not satisfy
verification.

## Added competitor coverage status refresh

T-240 updates `docs/LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md` so
the competitor-derived feature matrix reflects broad current wiring coverage
while preserving verification and advanced follow-up gaps.

## Added current completion evidence regression tests

T-245 adds focused coverage in
`example/test/shell/local_terminal_current_completion_state_test.dart` for the
current implemented-but-unverified completion-state evidence.

T-246 adds direct coverage in
`example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart` for
the current implemented-but-unverified real-wiring backlog evidence factory.

T-247 adds coverage in
`example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart`
so UI diagnostics snapshots preserve the current implemented-but-unverified
evidence.

T-248 adds coverage in
`example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart` so the
facade-level completion report preserves the same current evidence.

T-249 adds coverage in
`example/test/shell/shell_action_production_action_set_test.dart` for the
current default P1 production action baseline and key alias mappings.

T-250 adds coverage in
`example/test/shell/shell_action_production_callbacks_test.dart` proving the
typed production callback surface can satisfy the current default P1 action
baseline.

T-251 adds coverage in
`example/test/shell/shell_action_production_wiring_state_test.dart` proving the
production wiring state is ready when the current default P1 action baseline is
satisfied by typed callbacks.

T-252 adds coverage in
`example/test/shell/shell_action_production_executor_test.dart` proving the
production executor can execute representative alias-backed P1 baseline actions
when wiring is ready.

T-253 adds coverage in
`example/test/shell/shell_action_production_runtime_adapter_test.dart` proving
the runtime adapter external-executor path can execute representative
alias-backed P1 baseline actions when wiring is ready.

T-254 adds coverage in
`example/test/shell/shell_action_production_wiring_report_test.dart` and
`example/test/shell/shell_action_production_audit_snapshot_test.dart` proving
the report and snapshot layers stay clean for the current default P1 baseline.

T-255 adds coverage in
`example/test/shell/shell_action_production_closure_manifest_test.dart` proving
the closure manifest keeps tests and static analysis as blockers even when the
current default P1 wiring baseline is clean.

T-256 adds coverage in
`example/test/workspace/local_workspace_production_callbacks_test.dart` proving
the current core P2 workspace callback baseline can be ready while advanced
workspace gaps remain visible under the all-operations contract.

T-257 adds coverage in
`example/test/productivity/shell_productivity_production_callbacks_test.dart`
proving the current core P3 productivity callback baseline can be ready while
advanced productivity gaps remain visible under the all-operations contract.

T-258 adds coverage in
`example/test/policies/local_terminal_policy_production_callbacks_test.dart`
proving the current core P4 policy callback baseline can be ready while advanced
policy gaps remain visible under the all-operations contract.

T-259 adds coverage in
`example/test/visual/local_terminal_visual_production_callbacks_test.dart`
proving the current core P5 visual callback baseline can be ready while advanced
visual gaps remain visible under the all-operations contract.

T-260 adds coverage in
`example/test/shell/local_terminal_domain_wiring_summary_test.dart` proving
P2-P5 core baselines summarize as ready and advanced gaps remain visible at the
cross-domain summary layer.

T-261 adds coverage in
`example/test/shell/local_terminal_production_wiring_bundle_test.dart` proving
P2-P5 core baselines assemble into a closeable bundle only when verification
inputs are supplied.

T-262 adds coverage in
`example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart`
proving P2-P5 core summaries close only when verification statuses are supplied
to the production manifest builder.

T-263 adds coverage in
`example/test/shell/local_terminal_completion_evidence_report_test.dart` proving
the final completion report cannot close unless every required T-164 through
T-169 backlog task is present and verified.

T-264 adds coverage in
`example/test/shell/local_terminal_completion_summary_test.dart` and
`example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart`
proving missing required backlog task ids are visible in summary and diagnostics
outputs.

T-265 adds coverage in
`example/test/shell/local_terminal_completion_diagnostics_actions_test.dart`,
`example/test/shell/local_terminal_completion_menu_model_test.dart`, and
`example/test/shell/local_terminal_completion_command_menu_adapter_test.dart`
proving missing required backlog task ids propagate to downstream diagnostics
surfaces.

T-266 adds coverage in
`example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`
proving real-wiring backlog evidence builders emit every required T-164 through
T-169 task id expected by the final completion gate.

T-267 adds coverage in
`example/test/shell/local_terminal_completion_evidence_report_test.dart` proving
backlog blocker counts include both blocked backlog items and missing required
backlog ids.

T-268 adds coverage in
`example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart` proving
shell UI snapshot counts use the same required backlog blocker count.

T-269 adds coverage in
`example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart` proving the
shell UI wiring facade exposes the same required backlog blocker count.

These tests are coverage targets only until they are executed and recorded in
verification evidence.

## Latest verification loop status

The automated verification loop was executed through
`bash tools/local_terminal_verification_capture.sh run all-automated`.

Latest full-run evidence directory:
`build/local-terminal-verification/20260516T145142Z-all-automated`.

Passing evidence from that run:

- Expanded `dart format` gate across app, integration/test-driver/tool files,
  and local packages: latest 2026-05-31 scope audit reported
  `Formatted 287 files (0 changed)`.
- `flutter analyze`: `No issues found!`.
- Completion diagnostics suite: 45/45 passed.
- P1 action wiring suite: 33/33 passed.
- Cross-milestone production wiring suite: 8/8 passed.
- P2 workspace suite: 21/21 passed.
- P3 productivity suite: 26/26 passed.
- P4 policy suite: 22/22 passed.
- P5 visual suite: 33/33 passed.
- Verification evidence suite: 13/13 passed in the latest rerun; all required gates passed.

Current blocker: none.

Final closure evidence:

- Broader `flutter test example/test` passed in
  `build/local-terminal-verification/20260516T171406Z-broader`.
- Integration passed in
  `build/local-terminal-verification/20260516T171644Z-integration` after the
  batch was corrected to build the native core, run from `example`, and execute
  the two integration files sequentially.
- Manual/integration-backed verification observations have been recorded in the
  evidence ledger.
- Captured ledger rows are represented by `LocalTerminalVerificationPlanRecords.latestPassed()`.

Closure status:

- T-169 is verified.
- T-164 through T-168 are verified by ledger evidence, manual/integration-backed gates, and current verified backlog evidence.
- `LocalTerminalCompletionEvidenceReport.canCloseObjective` is now covered by `LocalTerminalCurrentCompletionState.verified` with latest passed verification evidence.

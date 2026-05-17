# Local Terminal Milestone Execution Plans Index

来源：`docs/LOCAL_TERMINAL_FEATURE_PLAN.md` 的 P0-P5 里程碑。  
口径：每一个里程碑独立维护一份可执行计划，而不是混在一份总计划里。

## Milestone Plans

1. [P0 Documentation And Boundaries](LOCAL_TERMINAL_P0_EXECUTION_PLAN_2026-05.md)
2. [P1 Action And Config Foundation](LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md)
3. [P2 Local Workspace](LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md)
4. [P3 Shell Productivity](LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md)
5. [P4 Clipboard, Notifications, Hotkey Window](LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md)
6. [P5 Visual And Advanced Local Features](LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md)

## Cross-Milestone Rules

- 严格保持本地 terminal 范围：macOS local shell、tabs、panes、profiles、config、shell integration、workspace UX。
- SSH、remote domain、SFTP、serial、协作 Web session、plugin ecosystem v1、renderer rewrite 均不进入这些里程碑。
- 每个里程碑必须独立满足自己的验收项后，才能作为后续里程碑的可靠前置。
- 涉及输入、粘贴、focus、selection 的任务必须保留现有 terminal protected contracts。
- 新增配置和 action 必须可测试、可降级、可诊断。

## Current Baseline

- `T-077-shell-profile-sheets-extraction` 已完成：Profiles / Dynamic Profiles sheet 已从 `ShellScreen` 抽离。
- `T-078-action-registry-foundation` 已完成：`TerminalActionId` 与 action registry 骨架已建立。
- 因此 P1 不再从零开始，而是继续补齐 keybinding、conflict diagnostics、local config schema 和兼容迁移。

## Added coverage audit

- `docs/LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md` maps the competitor-derived local terminal feature surface from `docs/LOCAL_TERMINAL_FEATURE_PLAN.md` to P0-P5 milestones, shell-product tasks, current artifacts, and remaining completion gaps.

## Added production wiring checklist

- `docs/LOCAL_TERMINAL_PRODUCTION_WIRING_CHECKLIST_2026-05.md` defines the P1-P5 production wiring gates that must close before the local terminal plan can be considered complete.

## Added cross-milestone production wiring manifest

- `example/lib/features/shell/local_terminal_production_wiring_manifest.dart` defines a P1-P5 closure manifest that requires each included milestone to have ready production wiring, passing tests, passing static analysis, and no blockers before the overall local terminal plan can close.

## Added domain wiring summary

- `example/lib/features/shell/local_terminal_domain_wiring_summary.dart` converts P2-P5 production callback wiring into cross-milestone manifest inputs, preserving missing operations as blockers and requiring explicit test/static-analysis status before any milestone can close.

## Added production wiring manifest builder

- `example/lib/features/shell/local_terminal_production_wiring_manifest_builder.dart` combines the P1 action closure manifest and P2-P5 domain wiring summaries into the cross-milestone production wiring manifest. Missing domain summaries are blockers, and tests/static-analysis status must be explicit.

## Added P0 boundary closure manifest

- `example/lib/features/shell/local_terminal_p0_boundary_closure_manifest.dart` adds P0 documentation/boundary closure state and blocks the cross-milestone manifest builder when P0 closure evidence is missing.

## Added completion audit checklist

- `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` maps the active objective to concrete P0-P5 evidence requirements and records that current state is not complete until production wiring and verification evidence exist.

## Added real wiring backlog

- `docs/LOCAL_TERMINAL_REAL_WIRING_BACKLOG_2026-05.md` defines the next execution phase after foundation: T-164 through T-169 wire P1-P5 production callbacks, populate closure manifests, and collect verification evidence.

## Added action-domain router

- `example/lib/features/shell/local_terminal_action_domain_router.dart` routes P1 action callbacks through P2-P5 domain production wiring, preventing duplicate callback registration and keeping missing domain operations visible to action binding audits.

## Added production wiring bundle

- `example/lib/features/shell/local_terminal_production_wiring_bundle.dart` assembles P0 boundary evidence, P2-P5 domain callbacks, P1 action routing, action closure, domain summaries, and the cross-milestone production manifest from one entry point.

## Added completion evidence report

- `example/lib/features/shell/local_terminal_completion_evidence_report.dart` combines the production wiring bundle with real wiring backlog statuses and exposes the final `canCloseObjective` gate.

## Added real wiring backlog evidence builder

- `example/lib/features/shell/local_terminal_real_wiring_backlog_evidence.dart` converts T-164 through T-169 task evidence into completion backlog items for the final objective closure report.

## Added verification evidence model

- `example/lib/features/shell/local_terminal_verification_evidence.dart` captures required verification gates and keeps pending, failed, or skipped required gates as blockers for final closure.

## Added verification backlog bridge

- `LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(...)` connects verification gate output to T-169 backlog closure, keeping incomplete verification as final objective blockers.

## Added default verification gates

- `LocalTerminalVerificationEvidence.defaultRequiredPending(...)` creates the full required verification gate set as pending evidence, and `gatePassed(...)` now returns false for missing required gates.

## Added current completion state

- `example/lib/features/shell/local_terminal_current_completion_state.dart` builds a conservative blocked completion report from pending P0/P1-P5/verification evidence, useful for showing why the objective cannot yet close.

## Added completion summary

- `example/lib/features/shell/local_terminal_completion_summary.dart` renders completion evidence into plain-text and JSON-compatible blocked/closeable summaries for audit and diagnostic surfaces.

## Added completion controller

- `example/lib/features/shell/local_terminal_completion_controller.dart` exposes completion state, summary text, JSON output, and the final `canCloseObjective` flag from one diagnostic facade.

## Added completion diagnostics view model

- `example/lib/features/shell/local_terminal_completion_diagnostics_view_model.dart` converts completion controller state into UI-friendly diagnostic sections for blocked milestones, real-wiring backlog, and verification gates.

## Added completion diagnostics action surface

- `example/lib/features/shell/local_terminal_completion_diagnostics_actions.dart` flattens completion diagnostics into read-only UI action items for command-menu or developer-panel rendering.

## Added completion menu model

- `example/lib/features/shell/local_terminal_completion_menu_model.dart` adapts completion diagnostics into read-only menu entries for command-menu or developer-panel rendering.

## Added completion command-menu adapter

- `example/lib/features/shell/local_terminal_completion_command_menu_adapter.dart` groups completion diagnostics into read-only command-menu sections for future ShellScreen or developer-panel rendering.

## Added completion diagnostics bundle

- `example/lib/features/shell/local_terminal_completion_diagnostics_bundle.dart` bundles completion controller, summary, menu model, command-menu adapter, and JSON diagnostics into one read-only entry point.

## Added completion shell command-menu diagnostics adapter

- `example/lib/features/shell/local_terminal_completion_shell_command_menu_diagnostics.dart` adapts completion menu entries into command-menu disabled-reason diagnostics while avoiding fake action ids.

## Added verification command plan

- `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` defines the commands, manual scenarios, and evidence mapping required before T-169 and final objective closure.

## Added shell UI wiring facade

- `example/lib/features/shell/local_terminal_shell_ui_wiring_facade.dart` exposes production wiring evidence, summary, diagnostics, and menu state from one read-only UI-facing facade.

## Added shell UI wiring snapshot

- `example/lib/features/shell/local_terminal_shell_ui_wiring_snapshot.dart` packages the shell UI wiring facade into a timestamped read-only payload with blocked milestone, backlog, and verification counts.

## Added Shell UI wiring handoff

- `docs/LOCAL_TERMINAL_SHELL_UI_WIRING_HANDOFF_2026-05.md` documents the stable high-level entry points and integration rules for future ShellScreen production wiring.

## Added Shell UI wiring exports

- `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart` provides a stable high-level import surface for future ShellScreen wiring and diagnostics integration.

## Added completion diagnostics panel

- `example/lib/features/shell/local_terminal_completion_diagnostics_panel.dart` renders a read-only Flutter panel for blocked completion diagnostics from `LocalTerminalShellUiWiringSnapshot`.

## Added completion diagnostics presentation model

- `example/lib/features/shell/local_terminal_completion_diagnostics_presentation.dart` defines read-only presentation state for inline panel, modal sheet, command-menu section, or developer-panel diagnostics display.

## Added completion diagnostics presentation resolver

- `example/lib/features/shell/local_terminal_completion_diagnostics_presentation_resolver.dart` resolves completion diagnostics presentation mode from a shell UI wiring snapshot and preferred display mode.

## Added verification evidence recorder

- `example/lib/features/shell/local_terminal_verification_evidence_recorder.dart` records verification command/manual outcomes from default pending gates and produces T-169 backlog evidence.

## Added verification batch recording

- `LocalTerminalVerificationEvidenceRecorder.recordAll(...)` records multiple verification gate outcomes in one immutable update while preserving pending gates as blockers.

## Added verification plan records

- `example/lib/features/shell/local_terminal_verification_plan_records.dart` provides default pending records for all required verification gates and converts them to the verification evidence recorder.

## Added pending completion snapshot factory

- `example/lib/features/shell/local_terminal_pending_completion_snapshot_factory.dart` builds default blocked shell UI wiring snapshots from verification plan records and preserves command/manual gate metadata.

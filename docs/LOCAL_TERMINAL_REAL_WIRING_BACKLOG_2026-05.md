# Local Terminal Real Wiring Backlog

Date: 2026-05-16

Purpose: convert the P0-P5 foundation and closure manifests into concrete
production wiring work. This backlog is the next execution surface after the
foundation phase.

## Current state

Foundation artifacts exist for P0-P5 plans, competitor coverage, action/config,
workspace, productivity, policy, visual features, production callback gates, and
cross-milestone closure manifests. Core production wiring has also been added
across `ShellScreen`, `SessionController`, preferences, runtime, and native
scrollback request paths for the current required local-terminal baseline.

The work is not complete because verification evidence has not been collected
and selected advanced or policy-hardening paths remain follow-up scope.

## Execution order

1. Wire P1 action production callbacks into the current shell dispatch path.
   Status: core required baseline wired, verification pending.
2. Wire P2 workspace callbacks into real tab/pane/layout behavior.
   Status: core workspace behavior wired, verification pending.
3. Wire P3 productivity callbacks into shell integration, search, scrollback,
   and read-only behavior.
   Status: core productivity behavior wired, verification pending.
4. Wire P4 policy callbacks into paste, clipboard, notifications, and hotkey
   window behavior.
   Status: mixed foundation/wired; verification and policy-hardening pending.
5. Wire P5 visual callbacks into theme, layout template, export, and advanced
   visual behavior.
   Status: mixed foundation/wired; verification and advanced follow-up pending.
6. Populate P0-P5 closure manifests from real wiring and verification evidence.
   Status: T-164 through T-168 now report implemented-but-unverified evidence;
   T-169 remains pending.
7. Run and record the required tests, static analysis, formatting, and manual or
   integration gates.

## Backlog

| Task | Domain | Production target | Closure evidence |
| --- | --- | --- | --- |
| T-164 | P1 action/config | Shell action dispatch path, command menu, shortcut bridge, runtime external executor | `ShellActionProductionClosureManifest.canClose == true` with real callbacks and passing verification |
| T-165 | P2 workspace | Shell tab/pane/layout methods | `LocalWorkspaceProductionWiring.isReady == true` and P2 milestone manifest closeable |
| T-166 | P3 productivity | Prompt navigation, command output, search, read-only, scrollback | `ShellProductivityProductionWiring.isReady == true` and P3 milestone manifest closeable |
| T-167 | P4 policy | Paste/clipboard policy, notification dispatch, hotkey window | `LocalTerminalPolicyProductionWiring.isReady == true` and P4 milestone manifest closeable |
| T-168 | P5 visual | Theme picker/import/export, layout template, scrollback export, graphics policy, advanced UI | `LocalTerminalVisualProductionWiring.isReady == true` and P5 milestone manifest closeable |
| T-169 | P0-P5 verification | Test, analysis, format, manual/integration evidence | `LocalTerminalProductionWiringManifest.canCloseAll == true` backed by real command/manual evidence |

## Non-goals for the wiring phase

- Do not introduce SSH, remote domains, serial, SFTP, or collaboration features.
- Do not rewrite the terminal renderer as a prerequisite.
- Do not mark optional advanced visual/productivity items complete unless their
  callbacks are populated and verified.
- Do not treat manifests or task files as completion evidence without real
  production wiring and verification output.

## Completion rule

The backlog is complete only when `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`
can be updated with real evidence for every row and the cross-milestone manifest
reports `canCloseAll: true`.

## Added action-domain router

T-170 adds `example/lib/features/shell/local_terminal_action_domain_router.dart`, which converts P2-P5 domain production wiring into P1 shell action callbacks. Real ShellScreen wiring should populate domain callbacks first, then route them through this adapter so action-layer closure and domain-layer closure agree on missing operations.

## Added production wiring bundle

T-171 adds `example/lib/features/shell/local_terminal_production_wiring_bundle.dart`, the preferred assembly point for real wiring: populate P2-P5 domain callbacks, route them into P1 actions, and produce the cross-milestone manifest from one bundle.

## Added completion evidence report

T-172 adds `example/lib/features/shell/local_terminal_completion_evidence_report.dart`, which combines the production wiring bundle with T-164 through T-169 backlog status. Final objective closure requires the production manifest to close and every backlog item to be verified.

## Added real wiring backlog evidence builder

T-173 adds `example/lib/features/shell/local_terminal_real_wiring_backlog_evidence.dart`, which turns T-164 through T-169 statuses into completion backlog items. All tasks default to pending and must be explicitly marked verified before final objective closure can pass.

## Added ShellScreen wiring spec

T-174 adds `docs/LOCAL_TERMINAL_SHELLSCREEN_WIRING_SPEC_2026-05.md`, the callback map for wiring T-164 through T-168 into real ShellScreen, SessionController, settings, export, and runtime behavior.

## Added verification evidence model

T-175 adds `example/lib/features/shell/local_terminal_verification_evidence.dart`, which records unit/widget/integration/manual/static-analysis/formatting evidence. Required gates remain blockers unless they are explicitly marked passed with evidence.

## Added verification backlog bridge

T-176 connects `LocalTerminalVerificationEvidence` to T-169 backlog evidence. T-169 can be marked verified only when every required verification gate is passed; pending, failed, or skipped required gates remain blockers.

## Added default verification gates

T-177 adds `LocalTerminalVerificationEvidence.defaultRequiredPending(...)`, which creates a complete pending verification gate set for T-169. Missing required gates are no longer considered passed.

## Added current completion state

T-178 adds `example/lib/features/shell/local_terminal_current_completion_state.dart`, a conservative blocked report builder that assumes no P0 review, no production callbacks, and pending verification gates unless explicit evidence is supplied.

## Added completion summary

T-179 adds `example/lib/features/shell/local_terminal_completion_summary.dart`, which renders the current completion evidence into readable blocked/closeable summary text for developer diagnostics and completion audits.

## Added completion controller

T-180 adds `example/lib/features/shell/local_terminal_completion_controller.dart`, a small facade for current completion state, readable summary, JSON output, and `canCloseObjective` diagnostics. It does not close any backlog item by itself.

## Added completion diagnostics view model

T-181 adds `example/lib/features/shell/local_terminal_completion_diagnostics_view_model.dart`, a UI-friendly diagnostics model for blocked milestones, blocked real-wiring tasks, and blocked verification gates.

## Added completion diagnostics actions

T-182 adds `example/lib/features/shell/local_terminal_completion_diagnostics_actions.dart`, which flattens completion diagnostics into read-only action items for command-menu or developer-panel rendering.

## Added completion menu model

T-183 adds `example/lib/features/shell/local_terminal_completion_menu_model.dart`, which adapts completion diagnostics into read-only menu entries for a future command menu or developer diagnostics panel.

## Added completion command menu adapter

T-184 adds `example/lib/features/shell/local_terminal_completion_command_menu_adapter.dart`, which groups completion diagnostics into read-only command-menu sections for a future ShellScreen command menu or developer diagnostics panel.

## Added completion diagnostics bundle

T-185 adds `example/lib/features/shell/local_terminal_completion_diagnostics_bundle.dart`, a single read-only entry point for completion summary, menu model, command-menu sections, and JSON diagnostics.

## Added completion shell command menu diagnostics

T-186 adds `example/lib/features/shell/local_terminal_completion_shell_command_menu_diagnostics.dart`, which adapts blocked completion menu entries into shell command menu disabled-reason diagnostics without fabricating terminal action ids.

## Added verification command plan

T-187 adds `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md`, which maps required verification gates to concrete commands or manual scenarios and defines the evidence needed before T-169 can close.

## Added shell UI wiring facade

T-188 adds `example/lib/features/shell/local_terminal_shell_ui_wiring_facade.dart`, a read-only facade that exposes production wiring evidence, completion summary, diagnostics view model, diagnostics action group, and menu state from the same completion evidence report.

## Added shell UI wiring snapshot

T-189 adds `example/lib/features/shell/local_terminal_shell_ui_wiring_snapshot.dart`, a timestamped read-only snapshot over the shell UI wiring facade with blocked milestone, backlog, and verification counts for UI/log diagnostics.

## Added Shell UI wiring handoff

T-190 adds `docs/LOCAL_TERMINAL_SHELL_UI_WIRING_HANDOFF_2026-05.md`, which identifies the high-level bundle/facade/snapshot/diagnostics entry points future ShellScreen wiring should use instead of low-level manifest internals.

## Added Shell UI wiring exports

T-191 adds `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart`, the preferred high-level import surface for future ShellScreen production wiring and diagnostics integration.

## Added completion diagnostics panel

T-192 adds `example/lib/features/shell/local_terminal_completion_diagnostics_panel.dart`, a reusable read-only Flutter panel for blocked completion diagnostics from a shell UI wiring snapshot.

## Added completion diagnostics presentation model

T-193 adds `example/lib/features/shell/local_terminal_completion_diagnostics_presentation.dart`, a read-only presentation model for choosing inline panel, modal sheet, command-menu section, or developer-panel display of blocked completion diagnostics.

## Added completion diagnostics presentation resolver

T-194 adds `example/lib/features/shell/local_terminal_completion_diagnostics_presentation_resolver.dart`, a read-only resolver that keeps completion diagnostics display-mode policy out of future ShellScreen wiring branches.

## Added verification evidence recorder

T-195 adds `example/lib/features/shell/local_terminal_verification_evidence_recorder.dart`, an immutable recorder for updating default pending verification gates with command/manual outcomes and converting them into T-169 backlog evidence.

## Added verification evidence batch recording

T-196 adds batch recording support to `LocalTerminalVerificationEvidenceRecorder`, allowing T-169 command/manual outcomes to be applied as a list of gate records while unrecorded required gates remain pending.

## Added verification plan records

T-197 adds `example/lib/features/shell/local_terminal_verification_plan_records.dart`, default pending records for every required verification gate, mirroring the verification command plan and feeding directly into the verification evidence recorder.

## Added pending completion snapshot factory

T-198 adds `example/lib/features/shell/local_terminal_pending_completion_snapshot_factory.dart`, which creates a default blocked shell UI wiring snapshot from verification plan records rather than anonymous pending verification gates.

## Added test target mapping

T-199 adds `docs/LOCAL_TERMINAL_TEST_TARGETS_2026-05.md`, which maps P0-P5 foundation and wiring artifacts to focused test target groups and command-order guidance for T-169.

## Added manual verification template

T-200 adds `docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`, a fill-in template for T-169 manual/integration gates and conversion into verification evidence records.

## Added evidence recording runbook

T-201 adds `docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md`, the operational sequence for converting real production wiring and verification output into T-169 backlog evidence and final completion evidence.

## Added ShellScreen first-patch checklist

T-202 adds `docs/LOCAL_TERMINAL_SHELLSCREEN_PATCH_CHECKLIST_2026-05.md`, defining the first safe production patch: render read-only blocked completion diagnostics in ShellScreen without changing terminal behavior.

## Added current implemented-unverified evidence

T-239 updates the current completion state so T-164 through T-168 show
implemented-but-unverified production wiring evidence instead of generic pending
placeholders. T-169 verification remains the blocker.

## Added competitor coverage matrix refresh

T-240 updates the competitor coverage matrix to reflect broad core production
wiring while keeping verification and advanced follow-up gaps explicit.

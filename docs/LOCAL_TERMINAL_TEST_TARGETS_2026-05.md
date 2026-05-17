# Local Terminal Test Targets

Date: 2026-05-16

Purpose: map the local terminal P0-P5 foundation and wiring artifacts to focused
test targets for T-169 verification.

This document does not claim that tests have passed. It defines what should be
run after real production wiring is complete.

## Focused test groups

| Gate | Suggested target | Coverage |
| --- | --- | --- |
| P0/P1 closure and diagnostics | `example/test/shell/local_terminal_*completion*_test.dart` | Completion state, implemented-but-unverified backlog evidence, required backlog gate, missing backlog diagnostics, summary, diagnostics, menu model, command-menu adapter, snapshot, facade, production wiring bundle, manifest builder, and pending snapshot factory. |
| P1 action wiring | `example/test/shell/shell_action_*test.dart` plus `example/test/shell/local_terminal_action_domain_router_test.dart` and `example/test/shell/local_terminal_domain_wiring_summary_test.dart` | Action production callbacks, default production action baseline, binding builder, binding diagnostics, runtime adapter, dispatch report, closure manifest, action-domain routing, and P2-P5 domain summary conversion. |
| P2 workspace wiring | `example/test/workspace/*workspace*_test.dart` | Workspace model, reducer, repository, core production callback baseline, advanced workspace gaps, and missing-operation reporting. |
| P3 productivity wiring | `example/test/productivity/*productivity*_test.dart` | Productivity state, reducers, runtime controller, recent items, core production callback baseline, advanced productivity gaps, search/output/read-only operations. |
| P4 policy wiring | `example/test/policies/*policy*_test.dart` | Paste decisions, policy reducer, notification dispatcher, core policy production callback baseline, advanced policy gaps, hotkey-window state. |
| P5 visual wiring | `example/test/visual/*visual*_test.dart` | Theme repository, layout templates, scrollback export, graphics store, visual reducer, core visual production callback baseline, advanced visual gaps. |
| Verification evidence | `example/test/shell/local_terminal_verification_*test.dart` | Required gates, recorder, batch recording, plan records, T-169 backlog bridge. |
| UI diagnostics widget | `example/test/shell/local_terminal_completion_diagnostics_panel_test.dart` | Read-only Flutter panel rendering from shell UI wiring snapshot. |

## Suggested focused command order

Run after T-164 through T-168 production wiring is complete:

```sh
flutter test example/test/shell/local_terminal_*completion*_test.dart
flutter test example/test/shell/shell_action_*test.dart example/test/shell/local_terminal_action_domain_router_test.dart
flutter test example/test/workspace
flutter test example/test/productivity
flutter test example/test/policies
flutter test example/test/visual
flutter test example/test/shell/local_terminal_verification_*test.dart
flutter test example/test/shell/local_terminal_completion_diagnostics_panel_test.dart
```

Then run the broader project tests required by the repository's normal release
bar:

```sh
flutter test example/test
```

Do not mark T-169 verified from focused tests alone unless they cover every
required closure row in
`docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`.

## Evidence recording

For each command, record:

- Command string.
- Exit status.
- Short output summary.
- Failing test names, if any.
- Follow-up blocker or fix task.

Use `LocalTerminalVerificationEvidenceRecorder.recordAll(...)` to convert the
results into `LocalTerminalVerificationEvidence`.

## Current status

Test target plan created. T-245 adds focused regression coverage for current
completion-state wiring evidence. T-246 adds direct regression coverage for the
current real-wiring backlog evidence factory. T-247 adds snapshot-factory
coverage so UI diagnostics surfaces preserve the same current evidence. T-248
adds facade-report coverage for the same evidence. T-249 adds P1 default action
set baseline regression coverage. T-250 adds typed production callback baseline
coverage. T-251 adds production wiring-state baseline readiness coverage. T-252
adds production executor baseline alias execution coverage. T-253 adds runtime
adapter external-executor baseline alias execution coverage. T-254 adds wiring
report and audit snapshot baseline readiness coverage. T-255 adds closure
manifest baseline verification-gate coverage. No test command has been run in
this session.

T-256 adds focused P2 workspace production callback baseline coverage and keeps
advanced workspace gaps visible under the all-operations contract.

T-257 adds focused P3 productivity production callback baseline coverage and
keeps advanced productivity gaps visible under the all-operations contract.

T-258 adds focused P4 policy production callback baseline coverage and keeps
advanced policy gaps visible under the all-operations contract.

T-259 adds focused P5 visual production callback baseline coverage and keeps
advanced visual gaps visible under the all-operations contract.

T-260 adds cross-domain summary coverage for P2-P5 core baselines and advanced
gap reporting.

T-261 adds production wiring bundle coverage for P2-P5 core baseline assembly,
routed action execution, and verification blockers.

T-262 adds production manifest builder coverage for P2-P5 core summaries and
verification blockers.

T-263 tightens final completion evidence so all T-164 through T-169 backlog task
ids must be present and verified before `canCloseObjective` can close.

T-264 surfaces missing required backlog task ids through summary and diagnostics
view model outputs.

T-265 extends missing required backlog diagnostics coverage into diagnostics
action items, menu entries, and command-menu sections.

T-266 ties real-wiring backlog evidence builders to the final required T-164
through T-169 backlog id gate.

T-267 adds a required backlog blocker count so diagnostics count both blocked
backlog items and missing required backlog ids.

T-268 adds shell UI snapshot coverage so `blockedBacklogItemCount` mirrors the
final required backlog blocker count.

T-269 exposes the same required backlog blocker count from the shell UI wiring
facade and keeps snapshot counts aligned with the facade.

T-271 adds diagnostics surface coverage so missing required backlog task ids
remain visible through the diagnostics bundle, presentation model, and Flutter
panel.

T-272 adds shell command-menu diagnostics coverage so missing required backlog
task ids remain visible after completion menu entries are adapted into disabled
reasons.

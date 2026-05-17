# Local Terminal Production Wiring Checklist

Date: 2026-05-16

Purpose: convert the remaining P1-P5 foundation work into concrete production
wiring gates. This checklist should be used before claiming that the local
terminal plan is complete.

## Completion rule

The plan is not complete until every applicable row below is wired to production
UI/runtime behavior and verified. Foundation models, reducers, repositories, or
runtime controllers are necessary evidence, but they are not sufficient by
themselves.

## P1 action/config wiring

| Gate | Production target | Foundation artifacts | Evidence required before closing |
| --- | --- | --- | --- |
| Action registry drives every user-facing action | `ShellScreen` menus, command menu, toolbar, shortcuts | `shell_action_registry.dart`, `shell_action_dispatcher.dart`, `shell_action_pipeline.dart` | Existing direct callbacks are either replaced by action dispatch or explicitly justified as terminal-internal behavior. |
| Runtime bindings are registered | `ShellScreen` and `SessionController` callbacks | `shell_action_runtime_bindings.dart` | Missing binding check returns empty for the supported user-facing action set. |
| Shortcut bridge owns app shortcuts | `ShellScreen` focus/input path | `local_terminal_key_event_resolver.dart`, `shell_shortcut_bridge.dart` | App shortcuts trigger actions only when allowed and do not write unintended characters to the terminal. |
| Command menu shows disabled reasons | Command menu UI | `shell_command_menu_model.dart`, `shell_command_menu_adapter.dart`, `shell_command_menu_diagnostics.dart` | Disabled actions display user-readable reasons, including shell-integration-disabled and no-pane/no-tab cases. |
| Config loading feeds runtime state | App startup/session creation | `local_terminal_config_loader.dart`, `local_terminal_config_preferences_adapter.dart` | Old profiles/preferences remain readable and local config changes affect the intended hot-reload/new-session boundaries. |

## P2 workspace wiring

| Gate | Production target | Foundation artifacts | Evidence required before closing |
| --- | --- | --- | --- |
| Tab lifecycle uses workspace model | `ShellScreen` tab creation/close/reopen | `local_workspace_models.dart`, `local_workspace_action_reducer.dart` | New/close/reopen tab behavior matches existing UX and last-tab close reaches the intended empty state. |
| Pane operations use workspace model | Split/focus/resize/swap/zoom/close UI | `TerminalPaneNode`, workspace reducer | Active pane, focus fallback, resize bounds, swap, and zoom behavior remain stable. |
| Same-cwd intent creates real sessions | New tab/split callbacks | `TerminalPaneSessionIntent`, productivity cwd state | Cwd inheritance works when shell integration is available and degrades clearly when unavailable. |
| Workspace layout persists locally only | Workspace save/load paths | `local_workspace_repository.dart` | Restored layouts contain no SSH/remote/serial/SFTP concepts. |

## P3 productivity wiring

| Gate | Production target | Foundation artifacts | Evidence required before closing |
| --- | --- | --- | --- |
| Shell integration events update productivity state | Session shell integration event flow | `shell_productivity_runtime_controller.dart`, productivity reducer | Prompt marks, cwd, command status, recent commands, recent directories, and command output ranges are populated from real events. |
| Prompt/output actions hit real terminal ranges | Prompt navigation, select/copy command output | productivity models/reducer | Actions are disabled when unavailable and operate on the expected scrollback ranges when available. |
| Search/block affordances use production scrollback | Search UI and scrollback controller | search/block models | Normal search and block-scoped search do not break focus, selection, or scrollback. |
| Read-only and clear scrollback affect real terminal behavior | Send-text/paste path and terminal controller | productivity reducer/runtime state | Read-only blocks all text send/paste paths; clear scrollback invokes the real terminal clear path. |

## P4 policy wiring

| Gate | Production target | Foundation artifacts | Evidence required before closing |
| --- | --- | --- | --- |
| Paste policy gates every paste path | Paste, advanced paste, paste history, bracketed paste | `local_terminal_paste_decision.dart`, policy reducer | Large/multiline/read-only cases cannot bypass the policy decision. |
| Paste history persists under policy | Paste history UI/repository | paste history policy models | History respects max size and disabled-state behavior. |
| Notifications use real terminal/session events | Bell, command finished, activity, silence | `local_terminal_notification_dispatcher.dart` | Focus policy and target policy are honored before any notification is emitted. |
| Hotkey window policy and failure state are visible | `WindowBridge.toggleHotkeyWindow()` path | hotkey policy/failure models | Permission/platform failures are surfaced as visible state instead of silent no-ops. |

## P5 visual and advanced local feature wiring

| Gate | Production target | Foundation artifacts | Evidence required before closing |
| --- | --- | --- | --- |
| Theme picker/import/export updates app/session appearance | Theme settings UI and profile/session appearance | `local_terminal_theme_repository.dart`, visual reducer | Theme changes apply at the intended boundary and import/export uses the local config contract. |
| Layout templates apply to workspace model | Layout template UI/action | layout template repository/applier | Applying a template produces a local workspace layout without remote state. |
| Scrollback export reads real terminal data | Export action/UI | `local_terminal_scrollback_exporter.dart` | Exported output matches the requested scrollback or command-output range. |
| Graphics storage policy is configurable | Advanced visual/settings path | `local_terminal_graphics_store.dart` | Policy is stored and enforced where graphics data is retained. |
| Advanced UI items are explicitly scoped | Command pane, timestamps, scrollback editor | advanced visual/productivity models | Each item has its own UI/runtime task before implementation is claimed. |

## Required verification gates

| Gate | Minimum evidence |
| --- | --- |
| Unit tests | Focused tests for action/config/workspace/productivity/policy/visual models and reducers. |
| Widget tests | Command menu/shortcut focus safety, split/focus behavior, paste confirmation, shell-integration-disabled states, and hotkey failure feedback. |
| Integration/manual | Local `/bin/zsh` or `/bin/bash` smoke, IME + paste + resize, multipane resize/search, command-finished notification, hotkey permission/failure path. |
| Static checks | Flutter/Dart analysis after production wiring is complete. |

## Current state

Current state is wired-but-unverified for the core required local-terminal
baseline. Most P1-P5 rows have supporting foundation artifacts and production
UI/runtime wiring through `ShellScreen`, `SessionController`, preferences,
runtime, or native request paths. The checklist is still not closed because the
verification gates have not been run in this session and selected advanced or
policy-hardening rows remain follow-up scope.

## Added production action-set gate

The production binding phase now has a default supported action set in `example/lib/features/shell/shell_action_production_action_set.dart`. Before closing P1 production wiring, the action set must resolve without unknown required names and its binding audit must report no missing required actions.

## Added production binding-builder gate

Production wiring should register `ShellScreen` / `SessionController` callbacks through `example/lib/features/shell/shell_action_production_binding_builder.dart`. The build result must have no unknown binding names, no unknown required action names, and no missing required runtime bindings before P1 can be closed.

## Added production binding diagnostics gate

Production wiring must surface `example/lib/features/shell/shell_action_production_binding_diagnostics.dart` results when binding closure fails. Blocking diagnostics must be zero before P1 action/config wiring can be considered closed.

## Added typed production callback gate

Production wiring should populate `example/lib/features/shell/shell_action_production_callbacks.dart` instead of hand-writing action-name maps. The resulting build/audit diagnostics are the closure evidence for the P1 action callback surface.

## Added production wiring-state gate

Production wiring should expose `example/lib/features/shell/shell_action_production_wiring_state.dart` as the single state object for action callback closure. P1 action/config wiring cannot close until `isReady` is true for the supported production action set and blocking diagnostics are empty.

## Added production executor gate

Production dispatch should use `example/lib/features/shell/shell_action_production_executor.dart` or an equivalent adapter so actions are not invoked while blocking wiring diagnostics remain. Callback exceptions must be surfaced as structured production execution failures.

## Added production runtime-adapter gate

Production dispatch should pass through `example/lib/features/shell/shell_action_production_runtime_adapter.dart` or an equivalent boundary so runtime-facing code receives `ShellActionBindingResult` without depending on binding audit or diagnostics internals.

## Added production wiring-report gate

Production wiring should expose `example/lib/features/shell/shell_action_production_wiring_report.dart` for developer diagnostics or completion audit output. P1 action wiring cannot close while the report contains blocking items.

## Added production dispatch-report gate

Production action dispatch should emit or expose `example/lib/features/shell/shell_action_production_dispatch_report.dart` data for diagnostics. This makes action execution failures auditable after ShellScreen/runtime integration.

## Added production audit-snapshot gate

Production action wiring should expose `example/lib/features/shell/shell_action_production_audit_snapshot.dart` when closing P1. The snapshot must report `canCloseP1ActionWiring: true` and no blocking wiring report items before P1 action wiring is complete.

## Added production closure-manifest gate

P1 action wiring closure should use `example/lib/features/shell/shell_action_production_closure_manifest.dart`. Wiring readiness is not enough: the closure manifest must also record passing tests and passing static analysis.

## Added P2 workspace production callback gate

P2 workspace production wiring should populate `example/lib/features/workspace/local_workspace_production_callbacks.dart` from real ShellScreen tab/pane/layout methods. P2 cannot close while required workspace operations are missing production callbacks.

## Added P3 productivity production callback gate

P3 productivity production wiring should populate `example/lib/features/productivity/shell_productivity_production_callbacks.dart` from real prompt navigation, command output, search, read-only, and scrollback methods. P3 cannot close while required productivity operations are missing production callbacks.

## Added P4 policy production callback gate

P4 policy production wiring should populate `example/lib/features/policies/local_terminal_policy_production_callbacks.dart` from real paste, clipboard, notification, and hotkey-window paths. P4 cannot close while required policy operations are missing production callbacks.

## Added P5 visual production callback gate

P5 visual production wiring should populate `example/lib/features/visual/local_terminal_visual_production_callbacks.dart` from real theme, layout-template, scrollback export, graphics policy, and advanced UI paths. P5 cannot close while required visual operations are missing production callbacks.

## Added cross-milestone production wiring manifest gate

Overall P1-P5 completion should use `example/lib/features/shell/local_terminal_production_wiring_manifest.dart`. The full plan cannot close unless every included milestone reports ready wiring, passing tests, passing static analysis, and no blockers.

## Added domain wiring-summary gate

P2-P5 production callback wiring should be converted through `example/lib/features/shell/local_terminal_domain_wiring_summary.dart` before feeding the cross-milestone manifest. Missing operations must remain blockers, and tests/analysis status must be explicit.

## Added production wiring manifest-builder gate

Overall production wiring closure should be assembled through `example/lib/features/shell/local_terminal_production_wiring_manifest_builder.dart`. Missing P2-P5 summaries must block closure, and no milestone may default tests or static analysis to passing.

## Added P0 boundary closure gate

Overall closure now includes `example/lib/features/shell/local_terminal_p0_boundary_closure_manifest.dart`. The full plan cannot close if P0 documentation, roadmap alignment, remote exclusions, per-milestone plans, competitor coverage, or production wiring checklist evidence is missing.

## Added completion audit checklist gate

Final objective closure should use `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` before declaring completion. Foundation artifacts, manifests, or task counts are insufficient without real production wiring and verification evidence.

## Added current wiring evidence gate

T-239 updates current completion evidence so T-164 through T-168 report
implemented-but-unverified wiring. Treat this as a stronger diagnostic signal
than foundation-only coverage, but not as closure evidence.

## Added status refresh dependency

T-241 refreshes the completion audit and real wiring backlog to match the
current wired-but-unverified state. This checklist remains open until formatting,
analysis, tests, and manual/integration gates provide passing evidence.

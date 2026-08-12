# Local Terminal Competitor Coverage Matrix

Date: 2026-05-16

Source of truth: `docs/LOCAL_TERMINAL_FEATURE_PLAN.md`.

This matrix maps the competitor-derived local terminal ideas into the current
P0-P5 execution plan, task files, and implementation artifacts. It is a coverage
matrix, not a completion claim.

## Legend

| Status | Meaning |
| --- | --- |
| Planned | Covered by the milestone plan, but no durable implementation artifact yet. |
| Foundation | Model, reducer, repository, adapter, or runtime-controller foundation exists. |
| Wired | Connected to production UI/runtime path. |
| Verified | Relevant tests or analysis were run and passed after the implementation. |
| Excluded | Intentionally out of local-terminal scope. |

Current summary: the competitor-derived feature surface is broadly covered by
P0-P5, foundation artifacts, and current production wiring records. Core
P1-P5 local-terminal actions now have `ShellScreen`, `SessionController`,
runtime/native, or preference-store wiring where applicable. The required
local-terminal closure baseline is verified; the remaining gap is deeper
follow-up for advanced/non-core capabilities.

## Competitor signals to milestone coverage

| Competitor-derived capability | Source signal | Milestone | Tasks | Current artifacts | Status | Remaining work |
| --- | --- | --- | --- | --- | --- | --- |
| Versioned local config, import-like layering, reload boundaries | Alacritty, Ghostty, WezTerm | P1 | T-080, T-081, T-102, T-124 | `local_terminal_config_models.dart`, `local_terminal_config_repository.dart`, `local_terminal_config_bootstrap.dart`, `local_terminal_config_loader.dart` | Wired | Verify exact-current schema rejection/no-mutation and runtime reload boundaries. |
| Stable action registry and unified action ids | Ghostty, WezTerm, Windows Terminal, kitty | P1 | T-078, T-079, T-095, T-230 | `shell_action_registry.dart`, `shell_action_production_action_set.dart`, `shell_action_production_action_name_resolver.dart` | Wired | Verify every production menu, command palette entry, and shortcut dispatches through the registry without fallback regressions. |
| Configurable keybindings with conflict diagnostics | Ghostty, WezTerm, Windows Terminal | P1 | T-079, T-082, T-083, T-122, T-123, T-230 | `local_terminal_keybinding_resolver.dart`, `local_terminal_key_event_resolver.dart`, `shell_shortcut_bridge.dart`, `ShellScreen` shortcut production dispatch | Wired | Verify app shortcuts do not leak text into the terminal and user-configured conflicts remain visible. |
| Command palette / action browser / launcher semantics | Windows Terminal, kitty, Hyper | P1 | T-046, T-098, T-108, T-120, T-121, T-140, T-230 | `shell_command_menu_model.dart`, `shell_command_menu_adapter.dart`, `shell_command_menu_diagnostics.dart`, `shell_action_view_models.dart`, `ShellScreen` production command menu entries | Wired | Run widget/manual checks for menu visibility, runtime errors, and user-visible feedback. |
| Action execution pipeline and side-effect boundary | Ghostty action model, WezTerm action model | P1 | T-114, T-116, T-117, T-118, T-119, T-136, T-137, T-138, T-139, T-230 | `shell_action_dispatcher.dart`, `shell_action_side_effect_plan.dart`, `shell_action_side_effect_executor.dart`, `shell_action_pipeline.dart`, `shell_action_runtime_controller.dart`, `shell_action_test_harness.dart`, `shell_action_error_diagnostics.dart`, `ShellActionProductionRuntimeAdapter` | Wired | Run focused shell action tests and manual fallback-path checks. |
| Tabs, panes, pane tree, split/focus/resize/swap/zoom | WezTerm, Windows Terminal, Zellij, Tabby | P2 | T-084, T-085, T-086, T-096, T-099, T-109, T-227, T-228, T-229, T-231 | `local_workspace_models.dart`, `local_workspace_repository.dart`, `local_workspace_action_reducer.dart`, `SessionController`, `ShellScreen` pane production callbacks | Wired | Verify focus fallback, close-last-pane behavior, pane resize persistence expectations, and layout restore behavior. |
| Same-cwd tab/split and local workspace restore | kitty, WezTerm, Wave, iTerm2 | P2 | T-087, T-099, T-134, T-230 | `TerminalPaneSessionIntent`, workspace repository, runtime persistence hook, `duplicateCurrentCwd` production dispatch | Wired | Verify shell-integration-derived cwd accuracy and fallback behavior when cwd is unavailable. |
| Prompt marks, command status, recent commands/directories | kitty, iTerm2, Warp | P3 | T-088, T-092, T-101, T-110, T-112, T-131, T-135, T-208, T-217 | `shell_productivity_models.dart`, `shell_productivity_reducer.dart`, `shell_recent_items_repository.dart`, `shell_productivity_action_reducer.dart`, `shell_productivity_runtime_controller.dart`, `ShellScreen` prompt navigation/recent directory dispatch | Wired | Verify shell integration events, disabled states when integration is off, and recent directory command insertion. |
| Block-scoped search, command output selection/copy, sticky command context | Warp, Wave, kitty | P3 | T-089, T-101, T-110, T-131, T-208, T-216 | productivity search/block models and reducers, `ShellScreen` search/output selection/copy dispatch | Wired | Verify scrollback focus, selected command output bounds, and copy output contents. |
| Read-only mode and clear scrollback as product actions | Ghostty, Warp, Konsole | P3 | T-095, T-101, T-110, T-119, T-232, T-235, T-236 | read-only action ids, `TerminalInputController` read-only guard, `TerminalRuntimeController.clearScrollback`, native clear-scrollback request | Wired | Verify every send-text/paste/mouse path respects read-only and native clear scrollback matches expected terminal semantics. |
| Clipboard and paste policy, bracketed/large/multiline paste safety | iTerm2, GNOME Terminal, existing terminal conventions | P4 | T-090, T-093, T-106, T-111, T-129, T-133, T-210, T-211 | `local_terminal_policy_models.dart`, `local_terminal_paste_decision.dart`, policy reducer, paste runtime hook, paste history and advanced paste production dispatch | Foundation/Wired | Verify all paste paths route through the intended policy decisions and expose confirmation UI for large/multiline paste. |
| Notifications and activity/silence monitors | Konsole, iTerm2, Ghostty | P4 | T-090, T-105, T-111, T-130, T-226, T-238 | `local_terminal_notification_dispatcher.dart`, policy models/reducer, notification runtime hook, persisted `TerminalAppNotifications` toggles | Wired | Verify real bell/command/activity events, focus policy, preference persistence, and silence-monitor follow-up scope. |
| Hotkey window / quick terminal policy and failure state | Ghostty quick terminal, iTerm2 hotkey window | P4 | T-090, T-097, T-119, T-230 | hotkey policy/failure state, runtime state integration, `toggleHotkeyWindow` action alias | Foundation/Wired | Verify macOS hotkey-window settings, `WindowBridge` behavior, and permission/platform failures in UI. |
| Theme preset selection, import/export, paired light/dark theme | Ghostty, Hyper, Tabby, Alacritty | P5 | T-091, T-103, T-115, T-132, T-223 | `local_terminal_visual_models.dart`, `local_terminal_theme_repository.dart`, visual reducer, theme picker runtime hook, `openThemePicker` production dispatch | Foundation/Wired | Verify theme picker/session appearance and split import/export or profile-level theme override into explicit follow-up tasks. |
| Split divider, active/inactive pane visual policy | Hyper, Tabby, WezTerm | P5 | T-045, T-049, T-056, T-091, T-115, T-227, T-229 | Hyper shell docs/tasks, visual models/reducer, pane zoom and sizing state | Foundation/Wired | Reconcile older Hyper UI work with the new local workspace model and verify visual state changes. |
| Layout templates and save/load layouts | Zellij, WezTerm, Wave | P5/P2 | T-094, T-113, T-126, T-127, T-224 | layout template models, repository, applier, runtime integration hook, two-pane layout production dispatch | Foundation/Wired | Verify template application and split save/load layouts into explicit runtime/UI follow-up if needed. |
| Scrollback export / save output | Konsole, Warp, kitty | P5/P3 | T-104, T-128, T-233, T-237 | `local_terminal_scrollback_exporter.dart`, scrollback export runtime hook, native historical scrollback export request, `ShellScreen` export dispatch | Wired | Verify historical scrollback contents, destination policy, visible-frame fallback, and failure messaging. |
| Graphics/image storage policy | Ghostty, kitty | P5 | T-107 | `local_terminal_graphics_store.dart`, graphics storage policy model | Foundation | Keep as advanced configurable policy; do not require renderer rewrite before local core features land. |
| Timestamps, command pane, scrollback editor, local tmux/coprocess conveniences | iTerm2, Warp, Wave, WezTerm | P5 | T-094 plus future UI-specific slices | advanced visual/productivity models | Planned/Foundation | Split into explicit UI/runtime tasks before claiming implementation. |
| Modern shell chrome and first-run/product polish | Hyper, Tabby | P0/P5 | T-044, T-045, T-046, T-047, T-048, T-049, T-056 | Hyper target/gap/boundary docs and shell-product tasks | Planned/Foundation | Keep as shell-layer polish; do not modify protected terminal semantics without regression coverage. |
| Dynamic/profile sheets and default profile cleanup | iTerm2 profile workflows, GNOME Terminal preferences | P0/P1 | T-057, T-058, T-077 | profile/default-profile task lineage | Foundation | Align profile UI with new local config schema and verify migration/default selection. |

## Explicit exclusions preserved from competitor analysis

| Excluded capability | Competitor source | Reason |
| --- | --- | --- |
| SSH profiles, SSH env, SSH terminfo, SSH agent automation | Ghostty, Tabby, iTerm2 | Out of the local-terminal scope for this plan. |
| Remote domains, remote multiplexing, serial domains | WezTerm, Tabby | Would expand the product into remote/session infrastructure before local workspace is complete. |
| SFTP, Telnet, browser-shared terminal, collaboration/cloud sync | Tabby, Wave | Not part of the local macOS terminal product goal. |
| Plugin ecosystem v1, JS/CSS customization ecosystem | Hyper, Zellij | Premature boundary expansion; local action/config/workspace model comes first. |
| AI/workflow widgets | Warp | Useful later, but explicitly outside v1 local terminal core. |
| Renderer rewrite as a prerequisite | kitty/Ghostty graphics-related features | Current plan is product/config/runtime shell layer first; renderer work is not a blocker for P0-P5 foundation. |

## Follow-ups outside the required closure baseline

1. Some production wiring is intentionally shallow and still needs UX/runtime
   hardening, especially paste confirmation UI, hotkey-window platform failure
   UI, theme import/export, layout save/load, and scrollback export policy.
2. Advanced P5 items such as command pane, timestamps, and scrollback editor are
   represented at planning/model level but need explicit UI/runtime tasks before
   they can be considered implemented.
3. Config loading, profile migration, and keybinding conflict diagnostics still
   need focused verification against existing preferences and shortcut behavior.

## Conclusion

The P0-P5 plan now covers the competitor-derived local terminal feature surface
that was marked as worth absorbing. The required local-terminal closure baseline
is verified; selected advanced follow-up remains for non-core capabilities.

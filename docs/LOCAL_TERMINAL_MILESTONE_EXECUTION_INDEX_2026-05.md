# Local Terminal Milestone Execution Index

Date: 2026-05-16

Purpose: provide a direct index for the P0-P5 execution plans and make clear
how competitor-derived local-terminal capabilities are mapped into those plans.
This is an index and traceability document, not a completion claim.

## Direct Answer

Yes: each local-terminal milestone has its own execution plan.

The competitor-derived capabilities that were marked as worth absorbing are
broadly represented across P0-P5. Some are wired into production paths, some are
foundation-only, and some advanced items remain explicit follow-ups. Completion
still requires the verification gates in
`LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md`.

## Milestone To Execution Plan

| Milestone | Execution plan | Primary responsibility | Competitor-derived feature surface |
| --- | --- | --- | --- |
| P0 Documentation And Boundaries | `LOCAL_TERMINAL_P0_EXECUTION_PLAN_2026-05.md` | Freeze local-first scope, non-goals, task rules, and acceptance boundaries. | Preserve useful local-terminal ideas while excluding SSH, remote domains, SFTP, serial, collaboration, and cloud sync from the current plan. |
| P1 Action And Config Foundation | `LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md` | Action ids, registry, keybindings, config schema, migration, diagnostics, command menu, and dispatch pipeline. | Ghostty/WezTerm/Windows Terminal/kitty style action models, configurable keybindings, command palette, local config layering, and conflict diagnostics. |
| P2 Local Workspace | `LOCAL_TERMINAL_P2_EXECUTION_PLAN_2026-05.md` | Local tabs, panes, splits, focus, resize, swap, zoom, close/reopen, same-cwd intent, and local layout persistence. | WezTerm/Windows Terminal/Zellij/Tabby style tabs, pane trees, split operations, same-cwd workflows, and local layout restore. |
| P3 Shell Productivity | `LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md` | Shell integration gates, prompt navigation, command output selection/copy, recent items, search, clear scrollback, and read-only mode. | kitty/iTerm2/Warp/Wave style prompt marks, command ranges, recent directories, block/search workflows, read-only actions, and scrollback productivity. |
| P4 Clipboard, Notifications, Hotkey Window | `LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md` | Clipboard/paste policy, paste history, OSC52 policy, notification rules, activity monitors, and hotkey window state. | iTerm2/GNOME/Konsole/Ghostty style paste safety, multiline/large paste confirmation, notification focus policy, activity/bell signals, and quick terminal behavior. |
| P5 Visual And Advanced Local Features | `LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md` | Themes, pane visual policy, layout templates, scrollback export, graphics storage policy, timestamps, command pane, and advanced visual/productivity surfaces. | Ghostty/Hyper/Tabby/Alacritty/Zellij/Wave style theme presets, active pane visuals, layout templates, scrollback export, command panes, timestamps, and advanced local polish. |

## Source Documents

| Document | Role |
| --- | --- |
| `LOCAL_TERMINAL_FEATURE_PLAN.md` | Product-level feature source of truth. |
| `LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md` | Maps competitor-derived capability signals to milestones, tasks, artifacts, status, and remaining work. |
| `LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` | Defines the closure checklist and distinguishes foundation, wired, and verified states. |
| `LOCAL_TERMINAL_MILESTONE_IMPLEMENTATION_STATUS_2026-05.md` | Summarizes implementation status across P0-P5. |
| `LOCAL_TERMINAL_REAL_WIRING_BACKLOG_2026-05.md` | Tracks the real wiring backlog, including T-164 through T-169 closure evidence. |
| `LOCAL_TERMINAL_PRODUCTION_WIRING_CHECKLIST_2026-05.md` | Tracks production UI/runtime wiring gates. |
| `LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` | Defines the required format, static analysis, test, and manual verification gates. |
| `LOCAL_TERMINAL_TEST_TARGETS_2026-05.md` | Maps implementation areas to focused test targets. |

## Competitor Coverage Position

The current plan includes the main local-terminal capabilities that were judged
worth absorbing from competitor analysis:

- Local config, config migration, and guarded local-only schema.
- Stable action ids, command palette, shortcut dispatch, and keybinding conflict diagnostics.
- Tabs, panes, splits, focus, resize, swap, zoom, close/reopen, same-cwd launch, and local layout restore.
- Prompt navigation, command output selection/copy, recent directories, search, clear scrollback, and read-only mode.
- Paste safety, paste history, bracketed paste, OSC52 policy, notification rules, and hotkey window state.
- Theme presets, pane visual policy, layout templates, scrollback export, graphics storage policy, timestamps, command pane, and visual polish.

The plan intentionally excludes or defers competitor capabilities that would
expand scope beyond the local-terminal product line:

- SSH profiles, remote domains, SFTP, serial sessions, and browser/cloud collaboration.
- Plugin ecosystem v1 and JS/CSS customization as a prerequisite.
- AI workflow widgets before the local action/config/workspace/productivity core is stable.
- Renderer rewrite or graphics protocol parity as a prerequisite for P0-P5 closure.

## Current Closure Interpretation

Do not treat this index as proof that P0-P5 are complete.

Current state remains:

- P0-P5 plans exist and are traceable.
- The competitor-derived local feature surface is broadly mapped.
- Core P1-P5 wiring is broadly present but still unverified.
- Several advanced local capabilities remain foundation-only or follow-up scope.
- Final closure is blocked until formatting, static analysis, focused tests,
  broader tests, and manual/integration evidence are executed and recorded.

## Maintenance Rule

When a new competitor-derived idea is added:

1. Classify it as local core, local advanced, future ecosystem, or excluded remote/cloud scope.
2. Map local core items to P1-P4 unless they are purely visual/advanced.
3. Map local visual or advanced productivity items to P5 or a future explicit milestone.
4. Add or update a task file instead of silently expanding an existing task.
5. Update the competitor coverage matrix and this index if the milestone mapping changes.

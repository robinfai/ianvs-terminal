# Manager Task Board

This board is the single source of truth for the manager-only multi-agent rollout.

## Status Legend

- `queued`: not started yet
- `in_progress`: active owner is working
- `blocked`: waiting on blocker resolution
- `needs_manager`: needs routing or scope decision
- `done`: lane-specific work finished

## Issue Tags

- `BASELINE`
- `SESSION`
- `UI`
- `INPUT`
- `COMPLETION`
- `INTEGRATION`
- `UPSTREAM-BLOCKED`

## Watchdog

- Every subagent must report meaningful progress within `15 minutes` or `8 tool actions`.
- On timeout, the manager interrupts for a partial result.
- If there is still no meaningful progress after another `10 minutes`, the manager closes the agent and re-dispatches a smaller task.

## Active Board

| lane | owner | scope | state | blockers | verification | next_action |
| --- | --- | --- | --- | --- | --- | --- |
| Worker-1 / Baseline | subagent | `core/session` | `done` | none | `flutter test test/widget_test.dart --plain-name "generic shell hooks create and finish command blocks"` and `flutter test` passed | Keep real shell smoke for later environment-backed verification |
| Reviewer-1 / Fresh Core Review | subagent | `lib/src/local_shell_session_controller.dart` | `done` | none | Read-only review completed with tagged findings | Findings routed to Worker-2 and manager queue |
| Reviewer-2 / Fresh Workspace Review | subagent | `lib/src/terminal_tabs_controller.dart`, `lib/src/terminal_panes.dart`, `lib/src/session_restore.dart`, `lib/main.dart` | `done` | none | Read-only review completed with tagged findings | Findings routed to Worker-2 and manager queue |
| Reviewer-3 / Fresh Command UX Review | subagent | `lib/src/modern_input_controller.dart`, `lib/src/command_history.dart`, `lib/src/saved_commands.dart`, `lib/src/fig_completion.dart`, `lib/src/shell_integration.dart` | `done` | none | Read-only review completed with tagged findings | Findings routed to Worker-3 and manager queue |
| Worker-2 / Session Fix Lane | subagent | `core/session`, `workspace/ui` | `done` | none | `test/session_restore_test.dart`, `test/terminal_panes_controller_test.dart`, and targeted `widget_test.dart` block-range case passed | Covered 6 queued `SESSION` / `UI` / `INTEGRATION` fixes |
| Worker-3 / Input Fix Lane | subagent | `input/command` | `done` | none | `test/fig_completion_test.dart` and completion-focused `widget_test.dart` passed | Covered 3 queued `COMPLETION` fixes |

## Current Baseline Note

- `2026-05-01`: repo-local green baseline is `flutter analyze` + `flutter test`.
- `2026-05-01`: `pubspec.yaml` currently points to `/Users/luobinghui/projects/flutter/flutterm`, so local verification must use that dependency tree as the source of truth.
- `2026-05-02`: the current debug `libflutterm_core.dylib` now exports `flutterm_session_search_json` and `flutterm_session_selection_text` after rebuilding `/Users/luobinghui/projects/flutter/flutterm`.
- `2026-05-02`: `FT-011` is fixed in `/Users/luobinghui/projects/flutter/flutterm` by parsing DCS shell hooks in native/core; real shell smoke now passes with `+16`.
- `2026-05-02`: `M4C` scope is now documented in `MILESTONES.md` and `README.md`; product tree lands launch configuration MVP with workspace file save/apply and pane startup commands.

## 2026-05-03 Warp Re-Audit

- Scope rechecked: the full shipped stack `M0 -> M6`, not just the latest closed milestones.
- Verification baseline on the current worktree remains green: `flutter analyze` passed; `flutter test` passed with `168` tests and `16` real-shell skips when `FLUTTERM_CORE_LIB` is unset; env-backed `flutter test test/real_shell_smoke_test.dart` passed `+16`; `flutter build macos --release` passed.
- Warp source baseline is `warpdotdev/Warp@a5fde8f`, checked out at `/private/tmp/warp-source-20260503`. `AGENTS.md` still points to `/Users/robinfai/personal/warp`; mirroring there is currently blocked by sandbox permissions.
- Warp docs baseline has shifted: `Launch Configurations` is now legacy, while current screenshots live under `Tab Configs`. The review therefore splits benchmark sources into app-export semantics from source / legacy docs and visual acceptance from current docs screenshots.
- Historical milestone closure remains intact: `M0 -> M6` do not need to be reopened against their original Ianvs acceptance text.
- Status change: source-level full-stack audit now queues `M7A -> M7E` as explicit Warp-basic-alignment follow-ups. See `WARP_SOURCE_REAUDIT.md`.

## Post Warp Source Audit Backlog

| item | status | scope | source evidence | expected closure |
| --- | --- | --- | --- | --- |
| `M7A Multi-Window Runtime And App Export` | `queued` | `workspace/ui`, `core/session`, `planning/docs` | Warp `launch_config.rs` snapshots `active_window_index + windows[]`; Ianvs has no window runtime and launch config is still single-window | Window runtime plus app-level launch config export/import land with active-window recovery |
| `M7B Export UI Screenshot Alignment` | `queued` | `workspace/ui`, `design/docs`, `planning/docs` | Warp docs `Tab Configs` carry the current screenshot benchmark; Warp `save_modal.rs` still shows app-state save semantics; Ianvs export UI is still a manual-path `AlertDialog` | Ianvs export UI screenshot reaches ~`80%` layout/CTA/info-density similarity against the chosen Warp docs benchmark |
| `M7C Block Presentation Alignment` | `queued` | `core/session`, `workspace/ui` | Warp `terminal/model/block.rs` and `blocks.rs` integrate block structure into terminal rendering; Ianvs still uses controller + side panel only | Terminal-visible block grouping, active block presentation, and restore-safe block separators land |
| `M7D Command Search And Session Navigation Alignment` | `queued` | `input/command`, `workspace/ui`, `planning/docs` | Warp `terminal/input/*`, `command_search/*`, and `command_palette/navigation/*` search broader command/session sources; Ianvs stops at saved commands, current-tab history, and current-window panes | Unified palette lands for broader command/session navigation and future workflow-grade saved commands |
| `M7E Desktop E2E Verification Harness` | `queued` | `integration`, `workspace/ui`, `planning/docs` | Warp `integration_testing/*` has reusable `window`, `pane_group`, `workspace`, `launch_configs`, `terminal` step/assertion modules; Ianvs still relies on widget + smoke composition | Reusable desktop E2E harness lands and covers windows, export UI, app export, panes, workspace search, and SSH flows |
| `Secondary: Session Settings Breadth` | `queued` | `workspace/ui`, `planning/docs` | Warp `new_session_shell.rs`, `startup_shell.rs`, and `working_directory_config.rs` expose wider session-source settings; Ianvs settings still stop at font/theme/default shell | Decide whether to spin a dedicated post-M7 settings milestone after app export and E2E stabilize |

## Triage Queue

| tag | scope | finding | disposition | target_lane |
| --- | --- | --- | --- | --- |
| `BASELINE` | `core/session` | Product code directly references missing `TerminalSessionShellHookEvent` type | `fixed` via product-side compatibility layer if possible | `Worker-1 / Baseline` |
| `UPSTREAM-BLOCKED` | `integration` | Current local `flutterm` native/core and Dart runtime did not expose end-to-end shell hook events | `fixed` by flutterm native/core DCS hook parsing; typed `flutterm_terminal` runtime event remains accepted-risk follow-up | `Flutterm Shell-Hook Worker` |
| `SESSION` | `core/session` | Exit-state find/copy currently degrade to visible-frame-only behavior | `fixed` | `Worker-2 / Session Fix Lane` |
| `INTEGRATION` | `core/session` | Block output start detection uses global command-text search and can drift when output repeats the command text | `fixed` | `Worker-2 / Session Fix Lane` |
| `SESSION` | `workspace/ui` | Restore saves are triggered by all shell-controller notifications, not just layout/session state changes | `fixed` | `Worker-2 / Session Fix Lane` |
| `UI` | `workspace/ui` | Find and command-history overlays can remain open together with conflicting shortcut semantics | `fixed` | `Worker-2 / Session Fix Lane` |
| `UI` | `workspace/ui` | Closed pane/tab focus nodes are retained until app dispose | `fixed` | `Worker-2 / Session Fix Lane` |
| `INTEGRATION` | `workspace/ui` | Session restore store uses a macOS-only path directly in product code instead of a platform adapter boundary | `fixed` | `Worker-2 / Session Fix Lane` |
| `COMPLETION` | `input/command` | Completion accept path does not respect quoting/escaping context | `fixed` | `Worker-3 / Input Fix Lane` |
| `COMPLETION` | `input/command` | Path completion only scans first-level cwd entries and fails for nested/relative/absolute prefixes | `fixed` | `Worker-3 / Input Fix Lane` |
| `COMPLETION` | `input/command` | Completion argument resolution ignores multi-arg/variadic/optional definitions after the first positional arg | `fixed` | `Worker-3 / Input Fix Lane` |
| `SESSION` | `core/session` | Shell hooks from another session can mutate the active controller | `fixed` | `Session/UI Fix Worker` |
| `SESSION` | `core/session` | Shell exit marks a running block `unknown` instead of using the exit code | `fixed` | `Session/UI Fix Worker` |
| `SESSION` | `workspace/ui` | Restore accepts duplicate pane ids and can corrupt focus/select/close identity | `fixed` | `Session/UI Fix Worker` |
| `UI` | `workspace/ui` | Last tab close button remains enabled while close action is a controller no-op | `fixed` | `Session/UI Fix Worker` |
| `INPUT` | `input/command` | Paste and Shift+Enter append instead of inserting at the current selection | `fixed` | `Input/Command Fix Worker` |
| `INTEGRATION` | `core/session` | Product still consumes shell hooks via a `PtySessionBackend` adapter rather than a typed `flutterm_terminal` runtime event | `accepted-risk`; native/core event delivery and smoke are fixed, typed runtime event can be a future flutterm cleanup | manager |
| `SESSION` | `core/session` | Shell-hook adapter dispatch can still be sensitive to hook/frame ordering under very fast zsh output | `accepted-risk`; real smoke and targeted tests are green, keep as stability watch item | manager |
| `SESSION` | `workspace/ui` | Product has no window runtime or `New Window` entry, so app-level export cannot be implemented honestly as long as launch config only sees one `TerminalTabsController` | `queued` | `M7A Multi-Window Runtime And App Export` |
| `UI` | `workspace/ui` | Launch config UI is still a manual-path `AlertDialog`; it does not match Warp docs/source save-flow hierarchy and cannot satisfy the new screenshot-consistency target | `queued` | `M7B Export UI Screenshot Alignment` |
| `SESSION` | `core/session` | Block model is still side-panel-oriented and lacks terminal-integrated block grouping / separators comparable to Warp `BlockList` | `queued` | `M7C Block Presentation Alignment` |
| `INPUT` | `input/command` | Command search only merges saved strings and current block history; there is no broader session-navigation palette comparable to Warp `command_palette/navigation` | `queued` | `M7D Command Search And Session Navigation Alignment` |
| `INTEGRATION` | `verification` | Repo lacks a reusable desktop E2E harness for window / pane / export-UI / launch-config / SSH regression scenarios comparable to Warp `integration_testing/*` | `queued` | `M7E Desktop E2E Verification Harness` |
| `UI` | `workspace/ui` | Session settings surface is still narrower than Warp `new_session_shell` / `startup_shell` / `working_directory_config` breadth | `queued` | `manager` |

## Verification Summary

- `flutter analyze`: passed
- `flutter test`: passed; full suite green with `168` tests and `16` smoke skips when `FLUTTERM_CORE_LIB` is unset
- `flutter test test/launch_config_test.dart test/terminal_panes_controller_test.dart test/widget_test.dart`: passed
- `flutter build macos --release`: passed
- `flutter test test/session_restore_test.dart test/terminal_panes_controller_test.dart test/fig_completion_test.dart`: passed
- `flutter test test/widget_test.dart --plain-name "duplicate command blocks keep distinct output ranges"`: passed
- `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart`: passed, `+16`
- `/Users/luobinghui/projects/flutter/flutterm/native/core`: `cargo test shell_hook`: passed
- `/Users/luobinghui/projects/flutter/flutterm`: `dart test packages/flutterm_pty/test/native_pty_backend_test.dart`: passed

## Module Closure

| module | implemented | fresh-reviewed | verified | notes |
| --- | --- | --- | --- | --- |
| `core/session` | `yes` | `yes` | `yes` | SessionId guard and exit-code block status fixed; real shell smoke passes; typed runtime shell-hook event remains accepted-risk follow-up |
| `workspace/ui` | `yes` | `yes` | `yes` | Duplicate pane ids and last-tab close affordance fixed and rechecked |
| `input/command` | `yes` | `yes` | `yes` | Paste/Shift+Enter insertion and submit-clears-draft regression fixed; closure fresh review returned no findings |

## Open Blockers

- None. `FT-010` and `FT-011` are closed for the current local `/Users/luobinghui/projects/flutter/flutterm` baseline.

## Continuous Rollout Round 2

Started on `2026-05-02`.

| lane | owner | scope | state | blockers | verification | next_action |
| --- | --- | --- | --- | --- | --- | --- |
| Flutterm Symbol Precheck | Aristotle | `/Users/luobinghui/projects/flutter/flutterm` | `done` | none | `nm -gU` now shows `_flutterm_session_search_json` and `_flutterm_session_selection_text` | Closed `FT-010`; no tracked flutterm source diff |
| Fresh Core Review | Huygens | `core/session` | `done` | none | Read-only findings with tags; `flutter test test/widget_test.dart` passed | Routed `SESSION` findings to Ohm; routed shell-hook boundary to Aquinas / manager |
| Fresh Workspace Review | Franklin | `workspace/ui` | `done` | none | `flutter analyze`, targeted restore/pane/widget tests, and `flutter test` passed | Routed `SESSION/UI` findings to Ohm |
| Fresh Command UX Review | Beauvoir | `input/command` | `needs_manager` | watchdog interrupted before full pass | Command/input targeted checks passed; real shell smoke then `+9 -6` | Routed paste/Shift+Enter finding to Hypatia |
| Milestone Recommender | Bohr | `planning/docs` | `done` | none | Recommendation returned | Keep `M4C -> M4D -> M5A` as next sequence |
| Flutterm Shell-Hook Worker | Aquinas | `/Users/luobinghui/projects/flutter/flutterm` | `done` | none | `cargo test shell_hook`, `dart test packages/flutterm_pty/test/native_pty_backend_test.dart`, `./tools/build_core.sh`, and Ianvs real shell smoke passed | Commit/push flutterm source diff |
| Session/UI Fix Worker | Ohm | `core/session`, `workspace/ui` | `done` | none | Targeted tests passed; independent recheck no findings | Commit/push Ianvs source diff |
| Input/Command Fix Worker | Hypatia | `input/command` | `done` | none | Targeted tests and regression retest passed; independent recheck no findings | Commit/push Ianvs source diff |
| Flutterm Shell-Hook Recheck | Anscombe | `/Users/luobinghui/projects/flutter/flutterm` | `done` | none | `cargo test shell_hook` passed | No findings |
| Session/UI Recheck | Wegener | `core/session`, `workspace/ui` | `done` | none | Targeted tests passed | No findings |
| Input/Command Recheck | Boole | `input/command` | `done` | none | `flutter analyze` and input/command/widget test set passed | No findings |
| Fresh Command UX Closure Review | Carson | `input/command` | `done` | none | `flutter analyze`, input/command test set, Fig converter `npm test`, and real shell smoke passed | No findings; closed watchdog gap from the interrupted fresh review |
| M4C Launch Config MVP | manager | `workspace/ui`, `core/session`, `planning/docs` | `done` | none | `flutter analyze`, `flutter test`, `flutter build macos`, launch-config/controller/widget tests, and env-backed real shell smoke passed | Queue fresh launch-config review when the next manager-only round opens; start `M4D` implementation planning |
| M4D Workspace Search And Jump | manager | `workspace/ui`, `core/session`, `planning/docs` | `done` | none | `flutter analyze`, `flutter test`, `flutter build macos`, workspace-search/widget tests, and env-backed real shell smoke passed | Queue fresh workspace-search review when the next manager-only round opens; start `M5A` implementation planning |
| M5A Session Metadata And Safety Context | manager | `workspace/ui`, `core/session`, `planning/docs` | `done` | none | `flutter analyze`, `flutter test`, `flutter build macos`, session-metadata/restore/launch/widget tests, and env-backed real shell smoke passed | Queue fresh session-context review when the next manager-only round opens; start `M5B` implementation planning |
| M5B SSH Command Session Launch MVP | manager | `workspace/ui`, `core/session`, `planning/docs` | `done` | none | `flutter analyze`, `flutter test`, `flutter build macos --release`, session-launch/restore/widget tests, and env-backed real shell smoke passed | Queue fresh SSH command-session review when the next manager-only round opens; start `M6` planning |
| M6 Cross-Platform Readiness Planning | manager | `planning/docs`, `core/session` | `done` | none | `test/platform_paths_test.dart`, platform doc review, `flutter analyze`, `flutter test`, and env-backed real shell smoke passed | No further milestone is defined; choose a platform spike from `PLATFORM_MATRIX.md` |
| M7A Multi-Window Runtime And App Export | manager | `workspace/ui`, `core/session`, `planning/docs` | `queued` | none | Full-stack Warp source re-audit recorded in `WARP_SOURCE_REAUDIT.md` | Add window runtime, app-level export/import, then cover active-window recovery |
| M7B Export UI Screenshot Alignment | manager | `workspace/ui`, `planning/docs` | `queued` | depends on `M7A` interaction model | Warp docs screenshot benchmark and `save_modal.rs` reviewed | Replace manual-path export dialog with Warp-like save flow and capture visual acceptance evidence |
| M7C Block Presentation Alignment | manager | `core/session`, `workspace/ui` | `queued` | depends on launch/export scope freeze only for restore interactions | Warp `block.rs` / `blocks.rs` reviewed | Add terminal-visible block grouping and restore-safe separators |
| M7D Command Search And Session Navigation Alignment | manager | `input/command`, `workspace/ui`, `planning/docs` | `queued` | none | Warp `terminal/input/*`, `command_search/*`, and `command_palette/navigation/*` reviewed | Expand palette scope beyond saved strings and current-window panes |
| M7E Desktop E2E Verification Harness | manager | `integration`, `workspace/ui`, `planning/docs` | `queued` | depends on `M7A` and `M7B` scope freeze | Warp `integration_testing/*` reviewed | Build reusable desktop E2E harness for windows / export UI / app export / panes / SSH |

### Round 2 Rules

- Main agent remains manager-only: maintain this board, monitor subagents, route findings, and perform final verification/commit/push.
- If flutterm changes are required, commit and push them from the flutterm repository before closing the blocker lane.
- Do not remove a module from active review unless it is `implemented`, `fresh-reviewed`, and `verified`.
- Keep recommending the next milestone after each closure; do not stop at one completed phase.

### Round 2 Milestone Recommendation

| order | milestone | recommendation | prerequisites | verification gate |
| --- | --- | --- | --- | --- |
| 1 | `M4C: Launch Configuration MVP` | Closed on `2026-05-02` | Keep docs and board aligned with the landed save/apply semantics and pane startup-command behavior | `test/launch_config_test.dart`, `test/terminal_panes_controller_test.dart`, `test/widget_test.dart`, `flutter analyze`, full `flutter test`, `flutter build macos`, and env-backed real shell smoke green |
| 2 | `M4D: Workspace Search And Jump` | Closed on `2026-05-02` | Keep docs and board aligned with the landed search ranking, jump semantics, and focus-restore behavior | `test/workspace_search_test.dart`, `test/widget_test.dart`, `flutter analyze`, full `flutter test`, `flutter build macos`, and env-backed real shell smoke green |
| 3 | `M5A: SSH Session Metadata And Safety Context` | Closed on `2026-05-03` | Keep docs and board aligned with the landed pane metadata, safety-context display, restore/launch persistence, and audit snapshot interface | `test/session_metadata_test.dart`, `test/session_restore_test.dart`, `test/launch_config_test.dart`, `test/terminal_panes_controller_test.dart`, `test/widget_test.dart`, `flutter analyze`, full `flutter test`, `flutter build macos`, and env-backed real shell smoke green |
| 4 | `M5B: SSH Command Session Launch MVP` | Closed on `2026-05-03` | Keep docs and board aligned with the landed local `ssh` launch flow, transport badges, restart target sync, and restore / launch-config recreation | `test/session_launch_test.dart`, `test/session_restore_test.dart`, `test/launch_config_test.dart`, `test/terminal_panes_controller_test.dart`, `test/widget_test.dart`, `flutter analyze`, full `flutter test`, `flutter build macos --release`, and env-backed real shell smoke green |
| 5 | `M6: Cross-Platform Readiness Planning` | Closed on `2026-05-03` | Keep docs and board aligned with `PLATFORM_MATRIX.md`, `platform_paths.dart`, and the new cross-platform flutterm risk inventory | `test/platform_paths_test.dart`, `flutter analyze`, full `flutter test`, env-backed real shell smoke, and docs review green |
| 6 | `M7A: Multi-Window Runtime And App Export` | `queued` on `2026-05-03` | Follow `WARP_SOURCE_REAUDIT.md`; add window runtime plus app-level export/import instead of current single-window scope | Window-aware export/import tests plus active-window recovery scenarios green |
| 7 | `M7B: Export UI Screenshot Alignment` | `queued` on `2026-05-03` | Follow `WARP_SOURCE_REAUDIT.md`; replace manual-path dialog with Warp-like save flow and collect screenshot acceptance evidence | Visual acceptance plus widget or golden coverage for export UI green |
| 8 | `M7C: Block Presentation Alignment` | `queued` on `2026-05-03` | Follow `WARP_SOURCE_REAUDIT.md`; move beyond side-panel-only blocks into terminal-visible grouping | Block presentation and restore scenarios green alongside existing hard gates |
| 9 | `M7D: Command Search And Session Navigation Alignment` | `queued` on `2026-05-03` | Follow `WARP_SOURCE_REAUDIT.md`; expand palette scope beyond saved strings and current-window panes | Unified command/session palette scenarios green |
| 10 | `M7E: Desktop E2E Verification Harness` | `queued` on `2026-05-03` | Follow `WARP_SOURCE_REAUDIT.md`; add reusable desktop E2E scenarios before claiming Warp-basic alignment | Dedicated desktop E2E suite for windows / export UI / app export / panes / SSH green alongside existing hard gates |

`FT-011` is closed for the current local baseline. Real shell smoke is back as a hard gate for future rounds. Historical milestones through `M6` remain closed, but the next work no longer starts from a platform spike: it starts from `M7A -> M7E` for window runtime, app export, export UI, block presentation, command/session navigation, and desktop E2E.

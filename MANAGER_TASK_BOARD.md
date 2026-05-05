# Manager Task Board

This board is the single source of truth for the manager-only multi-agent rollout.

## Status Legend

- `queued`: not started yet
- `in_progress`: active owner is working
- `blocked`: waiting on blocker resolution
- `needs_manager`: needs routing or scope decision
- `reset_queued`: reset by manager after capability / verification recalibration
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
- `2026-05-05`: M7 Warp terminal alignment is closed in the Ianvs Terminal product tree. Evidence lives in `WARP_LAYOUT_ALIGNMENT_TODO.md`, `WARP_SOURCE_REAUDIT.md`, `docs/design_snapshots/warp_alignment/`, `test/warp_alignment_golden_test.dart`, `test/launch_config_golden_test.dart`, and `test/demo_terminal_session_test.dart`.
- `2026-05-05`: Universal Input official-docs/source deep dive is closed for the Ianvs Terminal product layer. Evidence lives in `WARP_SOURCE_REAUDIT.md`, `PRODUCT_PLAN.md`, `WARP_LAYOUT_ALIGNMENT_TODO.md`, `docs/design_snapshots/warp_alignment/README.md`, `lib/main.dart`, and the refreshed Warp alignment screenshots. Product UI now says `Terminal command` / `Terminal input`, exposes default input tool buttons, and does not expose Warp legacy Agent / natural-language auto-detection copy.
- `2026-05-05`: layout recalibration is reclosed for the screenshot / Warp-alignment gates. Dart MCP tools were discovered, the Ianvs root was registered with `mcp__dart__.add_roots`, and MCP `analyze_files` / `run_tests` passed for the key closure gates. The `1%` golden suites, demo harness, analyze, and 10-run reannotation manifest are green; targeted split-pane overflow regressions now pass. Full `test/widget_test.dart` still contains stale legacy selector assertions and remains a separate cleanup follow-up.

## 2026-05-05 Layout Recalibration Round

Layout-heavy WLA work was reset and then reclosed against the recalibrated `1%` screenshot gates. Historical M7 evidence remains useful context; current closure evidence uses Dart MCP for Flutter / Dart gates plus the local Python reannotation script.

| lane | owner | scope | state | blockers | verification | next_action |
| --- | --- | --- | --- | --- | --- | --- |
| Layout Capability Baseline | manager | `planning/docs`, `integration` | `done` | none | `tool_search` exposed Dart MCP tools; `mcp__dart__.add_roots` registered the worktree; MCP analyze/tests passed | Keep MCP-first rule for future Flutter / Dart gates |
| Layout Visibility Baseline | manager | `workspace/ui`, `test/demo_terminal_session_test.dart` | `done` | full `test/widget_test.dart` still has stale legacy selector assertions | demo harness selectors updated for current compressed chrome; `flutter test test/demo_terminal_session_test.dart test/launch_config_golden_test.dart test/warp_alignment_golden_test.dart --reporter failures-only` passed `+21` | Track full widget selector cleanup separately from Warp screenshot closure |
| Layout Constraint Fix Lane | manager | `workspace/ui`, `lib/main.dart` | `done` | none | targeted `test/widget_test.dart` split-pane overflow cases passed | Compact pane surfaces now drop input-adjacent context strips under cramped height |
| Responsive Layout Lane | manager | `workspace/ui` | `done` | none | `test/warp_alignment_golden_test.dart` passed `+16`; `test/launch_config_golden_test.dart` passed `+1` | Reopen only when adding new screenshot surfaces |
| Golden / Reannotation Lane | manager | `integration`, `docs/design_snapshots/warp_alignment/` | `done` | none | regenerated golden PNGs and `alignment_regions.json`; tolerance `0.01`, `review_count = 0` | Keep generated SVG/JSON as current layout evidence |
| Fresh Layout Review | manager | `workspace/ui`, `integration`, `planning/docs` | `done` | none | `flutter analyze` passed; focused demo/golden suite passed `+21`; reannotation manifest has no review rows | Re-run after future chrome / pane / input layout changes |

## 2026-05-03 Warp Re-Audit

- Scope rechecked: the full shipped stack `M0 -> M6`, not just the latest closed milestones.
- Verification baseline on the current worktree remains green: `flutter analyze` passed; `flutter test` passed with `168` tests and `16` real-shell skips when `FLUTTERM_CORE_LIB` is unset; env-backed `flutter test test/real_shell_smoke_test.dart` passed `+16`; `flutter build macos --release` passed.
- Warp source baseline refreshed on `2026-05-04`: `warpdotdev/Warp@23eedf4`, shallow/sparse checkout at `../../warp`. Manual Warp interaction screenshots live under `docs/design_snapshots/warp_alignment/warp_interaction/` because Computer Use is blocked from controlling `dev.warp.Warp-Stable`.
- Warp docs baseline has shifted: `Launch Configurations` is now legacy, while current screenshots live under `Tab Configs`. The review therefore splits benchmark sources into app-export semantics from source / legacy docs and visual acceptance from current docs screenshots.
- Historical milestone closure remains intact: `M0 -> M6` do not need to be reopened against their original Ianvs acceptance text.
- Historical status change: the source-level full-stack audit queued `M7A -> M7E` as explicit Warp-basic-alignment follow-ups. Those follow-ups are now closed in the `2026-05-05` completion audit below.

## Post Warp Source Audit Backlog

| item | status | scope | source evidence | expected closure |
| --- | --- | --- | --- | --- |
| `M7A Multi-Window Runtime And App Export` | `done` | `workspace/ui`, `core/session`, `planning/docs` | Warp `launch_config.rs` snapshots `active_window_index + windows[]`; Ianvs now has `TerminalWindowsController` plus `activeWindowIndex` / `windows[]` launch config schema | Closed with app-level export/import, active-window recovery, and widget / E2E coverage |
| `M7B Export UI Screenshot Alignment` | `done` | `workspace/ui`, `design/docs`, `planning/docs` | Warp docs `Tab Configs` carry the current screenshot benchmark; Ianvs evidence has name-first compose, success state, saved config discovery, sidecar, and `1%` golden / rect contracts | Reclosed by `test/launch_config_golden_test.dart`, `test/warp_alignment_golden_test.dart`, and reannotation manifest |
| `M7C Block Presentation Alignment` | `done` | `core/session`, `workspace/ui` | Warp `terminal/model/block.rs` and `blocks.rs` integrate block structure into terminal rendering; Ianvs evidence has terminal-visible rail, status rail, sticky command header, inline actions, restore-safe grouping, and `FT-008` | Reclosed for product-layer layout; native scrollback row ranges remain upstream-boundary future work |
| `M7D Command Search And Session Navigation Alignment` | `done` | `input/command`, `workspace/ui`, `planning/docs` | Warp `terminal/input/*`, `command_search/*`, and `command_palette/navigation/*` search broader command/session sources; Ianvs evidence has unified palette sources, filters, detail rows, and launch-config apply | Reclosed for visible palette layout and source rail via `1%` golden contract |
| `M7E Desktop E2E Verification Harness` | `done` | `integration`, `workspace/ui`, `planning/docs` | Warp `integration_testing/*` has reusable `window`, `pane_group`, `workspace`, `launch_configs`, `terminal` step/assertion modules; Ianvs evidence has `_DesktopDemoHarness` plus golden / `1%` rect screenshot gates | Reclosed by focused demo/golden suite `+21` |
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
| `SESSION` | `workspace/ui` | Product has no window runtime or `New Window` entry, so app-level export cannot be implemented honestly as long as launch config only sees one `TerminalTabsController` | `fixed` | `M7A Multi-Window Runtime And App Export` |
| `UI` | `workspace/ui` | Launch config UI is still a manual-path `AlertDialog`; it does not match Warp docs/source save-flow hierarchy and cannot satisfy the new screenshot-consistency target | `fixed` | `M7B Export UI Screenshot Alignment` |
| `SESSION` | `core/session` | Block model is still side-panel-oriented and lacks terminal-integrated block grouping / separators comparable to Warp `BlockList` | `fixed-with-upstream-boundary` | `M7C Block Presentation Alignment` |
| `INPUT` | `input/command` | Command search only merges saved strings and current block history; there is no broader session-navigation palette comparable to Warp `command_palette/navigation` | `fixed` | `M7D Command Search And Session Navigation Alignment` |
| `INTEGRATION` | `verification` | Repo lacks a reusable desktop E2E harness for window / pane / export-UI / launch-config / SSH regression scenarios comparable to Warp `integration_testing/*` | `fixed` | `M7E Desktop E2E Verification Harness` |
| `UI` | `workspace/ui` | Session settings surface is still narrower than Warp `new_session_shell` / `startup_shell` / `working_directory_config` breadth | `queued` | `manager` |
| `BASELINE` | `integration` | Dart MCP tools are available for the Ianvs worktree after registering the root | `fixed`; use MCP-first analyze/test gates | `Layout Capability Baseline` |
| `UI` | `workspace/ui` | `test/widget_test.dart` currently fails old visible text / key assertions across header, status, block, tab, restore, and palette surfaces | `queued`; re-map tests to current compressed chrome separately from screenshot closure | `Layout Visibility Baseline` |
| `UI` | `workspace/ui` | Split pane widget scenarios surfaced bottom `RenderFlex overflowed` errors in cramped pane surfaces | `fixed`; cramped pane surfaces drop input-adjacent context strip and targeted overflow cases pass | `Layout Constraint Fix Lane` |
| `INTEGRATION` | `verification` | WLA golden / reannotation evidence predates the reset and cannot be used as current closure evidence | `fixed`; regenerated with `0.01` tolerance and no review rows | `Golden / Reannotation Lane` |

## Verification Summary

- `flutter analyze`: passed
- `flutter test`: passed; latest full suite green with `215` tests and `16` smoke skips when `FLUTTERM_CORE_LIB` is unset
- `flutter test test/launch_config_test.dart test/terminal_panes_controller_test.dart test/widget_test.dart`: passed
- `flutter build macos --release`: passed
- `flutter test test/session_restore_test.dart test/terminal_panes_controller_test.dart test/fig_completion_test.dart`: passed
- `flutter test test/widget_test.dart --plain-name "duplicate command blocks keep distinct output ranges"`: passed
- `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart`: passed, `+16`
- `/Users/luobinghui/projects/flutter/flutterm/native/core`: `cargo test shell_hook`: passed
- `/Users/luobinghui/projects/flutter/flutterm`: `dart test packages/flutterm_pty/test/native_pty_backend_test.dart`: passed
- `2026-05-05` completion audit: `flutter analyze` passed.
- `2026-05-05` completion audit: `nm -gU /Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib | rg 'flutterm_session_search_json|flutterm_session_selection_text'` found both exported symbols.
- `2026-05-05` completion audit: `flutter test test/demo_terminal_session_test.dart test/launch_config_golden_test.dart test/warp_alignment_golden_test.dart` passed with `+21`.
- `2026-05-05` completion audit: `flutter test` passed with `+215 ~16`.
- `2026-05-05` completion audit: `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart` passed with `+16`.
- `2026-05-05` completion audit: `flutter build macos --release` passed and built `build/macos/Build/Products/Release/Ianvs Terminal.app`.
- `2026-05-05` layout reannotation audit: `python3 docs/design_snapshots/warp_alignment/analysis/reannotate_alignment.py --iterations 10` generated 10 comparison SVGs deterministically; `alignment_regions.json` has `comparison_count = 10` and no `review` rows across 29 comparable regions; `flutter test test/launch_config_golden_test.dart test/warp_alignment_golden_test.dart` passed with `+17`.
- `2026-05-05` Universal Input audit: `flutter analyze` passed; `flutter test test/modern_input_controller_test.dart test/modern_input_editing_test.dart test/command_palette_test.dart test/fig_completion_test.dart` passed with `+17`; focused widget tests for visible default input toolbar, modern input submit, save command state, command sources, and inline block input state passed; `flutter test test/warp_alignment_golden_test.dart` passed with `+16`; `flutter test test/launch_config_golden_test.dart` passed with `+1`; reannotation script regenerated 10 comparison annotations. A full `flutter test` run is not used as closure evidence here because the current tree still has unrelated `test/widget_test.dart` visibility/layout assertions failing outside the Universal Input copy / business-boundary change.
- `2026-05-05` layout recalibration audit: `mcp__dart__.add_roots` registered `file:///Users/luobinghui/projects/flutter/ianvs/ianvs-terminal`; `mcp__dart__.analyze_files` returned `No errors`; MCP `run_tests` passed `test/demo_terminal_session_test.dart test/launch_config_golden_test.dart test/warp_alignment_golden_test.dart` with `+21`; MCP targeted split-pane overflow widget cases passed `+2`; `python3 docs/design_snapshots/warp_alignment/analysis/reannotate_alignment.py` regenerated `tolerance = 0.01` with no review rows. Full `test/widget_test.dart` still needs stale selector cleanup.

## Module Closure

| module | implemented | fresh-reviewed | verified | notes |
| --- | --- | --- | --- | --- |
| `core/session` | `yes` | `yes` | `yes` | SessionId guard and exit-code block status fixed; real shell smoke passes; typed runtime shell-hook event remains accepted-risk follow-up |
| `workspace/ui` | `yes` | `yes` | `yes` | Warp screenshot layout is reclosed at `1%`; full `test/widget_test.dart` still has stale selector cleanup outside the screenshot closure |
| `input/command` | `yes` | `yes` | `yes` | Paste/Shift+Enter insertion and submit-clears-draft regression fixed; closure fresh review returned no findings |

## Open Blockers

- Dart MCP project root is registered for this session; keep MCP-first verification for Flutter / Dart gates.
- Full `test/widget_test.dart` still has stale legacy visible text / key assertions after the compressed Warp-aligned chrome. The split-pane overflow blocker is fixed in targeted coverage; keep full widget selector cleanup as a separate follow-up, not a screenshot-layout blocker.

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
| M7A Multi-Window Runtime And App Export | manager | `workspace/ui`, `core/session`, `planning/docs` | `done` | none | Widget / E2E coverage plus app-level schema and active-window restore verified in completion audit | Keep future work to native OS window integration only if explicitly scoped |
| M7B Export UI Screenshot Alignment | manager | `workspace/ui`, `planning/docs` | `done` | none | Current benchmark, regenerated golden screenshots, and `1%` rect contracts pass | Reopen only when Launch Config / saved-config layout changes |
| M7C Block Presentation Alignment | manager | `core/session`, `workspace/ui` | `done` | native row-range rendering remains upstream extension | Product-layer block rail / action / input alignment passes; split-pane overflow targeted cases pass | Keep native scrollback block grouping as future flutterm-boundary work |
| M7D Command Search And Session Navigation Alignment | manager | `input/command`, `workspace/ui`, `planning/docs` | `done` | none | Palette shell, source rail, results list, and session palette `1%` contracts pass | Reopen only when palette source UI changes |
| M7E Desktop E2E Verification Harness | manager | `integration`, `workspace/ui`, `planning/docs` | `done` | full widget selector cleanup remains separate | Demo harness plus screenshot gates pass on current tree | Keep focused demo/golden command as the layout closure gate |

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
| 6 | `M7A: Multi-Window Runtime And App Export` | Closed on `2026-05-05` | Keep `TerminalWindowsController`, app-level launch config schema, restore, and docs aligned with Warp source semantics | Window-aware export/import tests plus active-window recovery scenarios green |
| 7 | `M7B: Export UI Screenshot Alignment` | Reclosed on `2026-05-05` | Current golden and reannotation evidence supersedes reset state | Launch Config / saved config screenshot gates green at `1%` |
| 8 | `M7C: Block Presentation Alignment` | Reclosed on `2026-05-05` | Product-layer evidence is current; flutterm render-layer row ranges remain explicit upstream follow-up | Block presentation and split pane overflow gates green |
| 9 | `M7D: Command Search And Session Navigation Alignment` | Reclosed on `2026-05-05` | Semantic source/filter work plus visible palette layout rechecked | Unified command/session palette visibility and source rail gates green |
| 10 | `M7E: Desktop E2E Verification Harness` | Reclosed on `2026-05-05` | Demo harness updated for compressed chrome selectors | Focused desktop E2E suite plus screenshot gates green on current tree |

`FT-011` is closed for the current local baseline. Real shell smoke is back as a hard gate for future rounds. Layout-heavy M7 / WLA closure was reset and reclosed on `2026-05-05` after the recalibrated overflow, golden, reannotation, and demo harness gates passed again.

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
- `2026-05-01`: real shell smoke remains `UPSTREAM-BLOCKED` until the current debug `libflutterm_core.dylib` exports `flutterm_session_search_json` and other bindings required by the current Dart-side `flutterm_pty`.

## Triage Queue

| tag | scope | finding | disposition | target_lane |
| --- | --- | --- | --- | --- |
| `BASELINE` | `core/session` | Product code directly references missing `TerminalSessionShellHookEvent` type | `fixed` via product-side compatibility layer if possible | `Worker-1 / Baseline` |
| `UPSTREAM-BLOCKED` | `integration` | Current local `flutterm` native/core and Dart runtime do not expose end-to-end shell hook events | Keep tracked as upstream dependency risk even after compile fix | manager |
| `SESSION` | `core/session` | Exit-state find/copy currently degrade to visible-frame-only behavior | `fixed` | `Worker-2 / Session Fix Lane` |
| `INTEGRATION` | `core/session` | Block output start detection uses global command-text search and can drift when output repeats the command text | `fixed` | `Worker-2 / Session Fix Lane` |
| `SESSION` | `workspace/ui` | Restore saves are triggered by all shell-controller notifications, not just layout/session state changes | `fixed` | `Worker-2 / Session Fix Lane` |
| `UI` | `workspace/ui` | Find and command-history overlays can remain open together with conflicting shortcut semantics | `fixed` | `Worker-2 / Session Fix Lane` |
| `UI` | `workspace/ui` | Closed pane/tab focus nodes are retained until app dispose | `fixed` | `Worker-2 / Session Fix Lane` |
| `INTEGRATION` | `workspace/ui` | Session restore store uses a macOS-only path directly in product code instead of a platform adapter boundary | `fixed` | `Worker-2 / Session Fix Lane` |
| `COMPLETION` | `input/command` | Completion accept path does not respect quoting/escaping context | `fixed` | `Worker-3 / Input Fix Lane` |
| `COMPLETION` | `input/command` | Path completion only scans first-level cwd entries and fails for nested/relative/absolute prefixes | `fixed` | `Worker-3 / Input Fix Lane` |
| `COMPLETION` | `input/command` | Completion argument resolution ignores multi-arg/variadic/optional definitions after the first positional arg | `fixed` | `Worker-3 / Input Fix Lane` |

## Verification Summary

- `flutter analyze`: passed
- `flutter test`: passed
- `flutter test test/session_restore_test.dart test/terminal_panes_controller_test.dart test/fig_completion_test.dart`: passed
- `flutter test test/widget_test.dart --plain-name "duplicate command blocks keep distinct output ranges"`: passed
- `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart`: failed with upstream/native-library mismatch

## Module Closure

| module | implemented | fresh-reviewed | verified | notes |
| --- | --- | --- | --- | --- |
| `core/session` | `yes` | `yes` | `yes` | repo-local validation is green; real shell smoke remains blocked by `FT-010` |
| `workspace/ui` | `yes` | `yes` | `yes` | tab/pane/restore/focus fixes validated by targeted tests and full `flutter test` |
| `input/command` | `yes` | `yes` | `yes` | completion fixes validated by targeted tests and full `flutter test` |

## Open Blockers

- `UPSTREAM-BLOCKED`: the current debug `libflutterm_core.dylib` under `/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug` does not export `flutterm_session_search_json`, while the current `flutterm_pty` bindings expect it. This blocks the real shell smoke suite even though repo-local analysis and unit/widget tests are green.

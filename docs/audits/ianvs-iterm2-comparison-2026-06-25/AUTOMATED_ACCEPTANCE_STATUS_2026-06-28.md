# Ianvs Terminal Automated Acceptance Status

Date: 2026-06-28

Scope: the seven unfinished buckets re-sorted from the repository docs. This file records only the items that can be accepted by automated tests or current host/Computer Use evidence. Host-only, cross-platform, hardware-specific, or product-scope decisions stay open.

## Commands Run

```sh
cd example && flutter test test/widget_test.dart test/shell/shell_screen_phase1b_test.dart test/terminal/render_terminal_viewport_test.dart
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "paste"
cd example && flutter test test/terminal_input_controller_test.dart --plain-name "paste"
cd example && flutter test test/profiles test/shell/shell_screen_phase3_test.dart --plain-name "profile"
cd example && flutter test test/widget_test.dart --plain-name "shell integration"
cd example && flutter test test/widget_test.dart --plain-name "shell status"
cd example && flutter test test/widget_test.dart --plain-name "annotations"
cd example && flutter test test/widget_test.dart --plain-name "captured output"
cd example && flutter test test/widget_test.dart --plain-name "instant replay"
cd example && flutter test test/shell/instant_replay_store_test.dart
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "hotkey"
cd example && flutter test test/widget_test.dart --plain-name "hotkey"
cd example && flutter test test/widget_test.dart --plain-name "notification"
cd example && flutter test test/widget_test.dart --plain-name "keyboard-only focus traversal"
cd example && flutter test test/widget_test.dart --plain-name "focused shell semantics"
cd example && flutter test test/widget_test.dart --plain-name toolbelt
flutter test packages/ianvs_terminal/test/terminal_config_test.dart
cd example && flutter test test/profiles/profile_repository_test.dart test/profiles/profile_editor_test.dart
cd example && flutter test test/widget_test.dart --plain-name "tab"
cd example && flutter analyze lib/features/shell test/widget_test.dart test/shell/instant_replay_store_test.dart test/shell/shell_screen_phase4_test.dart
flutter analyze packages/ianvs_terminal/lib/src/config/terminal_config.dart packages/ianvs_terminal/test/terminal_config_test.dart example/lib/features/profiles example/lib/features/shell example/lib/ui/foundation/terminal_theme_presets.dart example/test/profiles example/test/widget_test.dart
flutter analyze example/lib/features/shell/shell_screen_toolbelt.dart example/test/widget_test.dart
```

Results:

- The first command passed 196 widget/render tests.
- The paste policy command passed 4 tests.
- The terminal input paste command passed 4 tests.
- The profile/profile-shell command passed 41 tests.
- The shell integration/status reruns passed 6 and 3 widget tests.
- The annotations and captured-output reruns passed 2 and 3 widget tests.
- The instant replay workspace rerun passed; the instant replay store suite passed 13 tests.
- The hotkey reruns passed the phase4 visible-failure test and the widget bridge-invocation test.
- The notification rerun passed 7 widget tests.
- The focused keyboard traversal and Flutter semantics regressions passed.
- The Toolbelt keyboard traversal and focused semantics widget rerun passed 3 tests.
- The optional tab color config/profile/editor/tab reruns passed: terminal config passed 18 tests, profile repository/editor passed 32 tests, and the tab widget filter passed 23 tests.
- The shell feature analysis command passed.
- The optional tab color analysis command passed.
- The focused Toolbelt analysis command passed.

## Bucket Status

| Bucket | Accepted now | Evidence | Still open |
| --- | --- | --- | --- |
| 1. Known issues / accepted boundaries | Required local-terminal closure baseline remains verified; no known issue in this bucket is newly unblocked by automation. | `tools/local_terminal_verification_status.sh` points at the canonical verified records; `docs/KNOWN_ISSUES.md` already limits the remaining risks to environment, cross-platform, performance regression, and future product scope. | macOS-only, local-shell-only, no SSH/sync/plugin/native-renderer, quiet-host and cross-machine performance, cross-platform validation. |
| 2. Environment and verification risks | Local app/widget behavior for shortcuts, paste, profiles, notifications feedback, hotkey bridge call and visible failure, shell integration health, focused command-menu/search/Toolbelt semantics, and search is covered by current tests. | `test/widget_test.dart`, `test/shell/shell_screen_phase4_test.dart`, `test/terminal_input_controller_test.dart`, `test/profiles`, and existing foreground proof docs. | Flutter SDK `Failed to foreground app; open returned 1`, Codex-host frontmost ownership, `AXTree` bridge noise, and UI automation permission remain host/tooling risks. |
| 3. xterm/manual confirmation queue | Already accepted by automation or Computer Use where available: M-001 to M-005, M-007, M-008, M-010 normal fish Ctrl-C path, M-011, and first M-013 release snapshots. M-006 geometry snapping is automated at DPR 1.25, 1.5, and 2.5. | `docs/XTERM_MANUAL_CONFIRMATION_QUEUE.md`; current rerun of `test/terminal/render_terminal_viewport_test.dart`; prior Computer Use observations recorded in the queue. | M-006 real fractional-display sharpness, M-009 Windows/WSL Ctrl/CapsLock, M-012 Android physical keyboard, and M-013 quiet-host refresh. Kitty keyboard protocol remains a scope decision, not current product support. |
| 4. Roadmap M1/M2 evidence lane | M1-style automated UX and terminal probes relevant to the current docs pass in the current worktree. | Current focused test reruns plus canonical local-terminal verification evidence. | M2 host/platform/performance items that require target hardware or a quiet machine. |
| 5. Branch-only product line | Removed from `main` by design; it belongs to another branch and is no longer an acceptance item in this branch. | Main-branch cleanup already removed the related docs and roadmap references. | None in this branch. |
| 6. xterm API alignment gaps | Paste, bracketed paste, DPR snapping, shell search, global search, and current keyboard input paths have automated coverage in the current run or existing terminal-package tests. | Current focused test reruns and `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`. | Kitty keyboard protocol, platform-specific Windows/Android input delivery, and broader host-font/rendering smoke. |
| 7. UX optimization follow-ups | `T-UX-002` through `T-UX-008` have automated proof for the app-level scope: shortcut matrix, search scope/result count/regex/global search, compact tab/overflow, optional tab color, pane header/actions, profile sections, paste safety/read-only, Toolbelt IA, Toolbelt keyboard/semantics coverage, shell integration health, guided annotation/captured-output empty states, instant replay timeline/retention display, hotkey/notification diagnostics, and focused command-menu keyboard/semantics coverage. | `SHORTCUT_PROOF_MATRIX.md`, `PASTE_SAFETY_PROOF.md`, `PROFILE_EDITOR_SECTION_NAVIGATION.md`, `TOOLBELT_IA_PROOF.md`, plus the 2026-06-28 rerun commands above. | `T-UX-001` foreground proof remains host/tooling-limited; full keyboard traversal across tabs/panes/profile editor, profile focused semantics, per-profile keybinding editing, import diff/rollback, advanced parity, and full accessibility-tree proof remain future work. |

## Closeout Rule

Do not reopen an accepted item unless a new failing test, host observation, or product-scope decision changes the evidence. Remaining items should stay in the relevant host/platform/performance/product-decision documents instead of being counted as missing automated acceptance.

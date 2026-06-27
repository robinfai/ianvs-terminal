# Ianvs Terminal Toolbelt IA Proof

Date: 2026-06-25

Scope: implementation and automated proof for `T-UX-008`.

## Evidence Commands

```sh
cd example && flutter test test/widget_test.dart --plain-name "toolbelt"
cd example && flutter test test/widget_test.dart --plain-name "paste history"
cd example && flutter test test/widget_test.dart --plain-name "shell integration utilities"
cd example && flutter analyze lib/features/shell test/widget_test.dart
cd example && flutter test test/widget_test.dart
git diff --check
```

Latest results in this worktree:

- `flutter test test/widget_test.dart --plain-name "toolbelt"`: passed.
- `flutter test test/widget_test.dart --plain-name "paste history"`: passed.
- `flutter test test/widget_test.dart --plain-name "shell integration utilities"`: passed.
- `flutter analyze lib/features/shell test/widget_test.dart`: passed.
- `flutter test test/widget_test.dart`: passed, 100 tests.
- `git diff --check`: passed.

2026-06-28 rerun:

- `cd example && flutter test test/widget_test.dart test/shell/shell_screen_phase1b_test.dart test/terminal/render_terminal_viewport_test.dart`: passed, 196 tests. This includes `toolbelt opens a sidebar with terminal tool shortcuts`, `toolbelt previews shell history and paste sources`, and the paste/history/search regressions that exercise Toolbelt handoffs.

## Matrix

| Requirement | Result | Automated proof |
| --- | --- | --- |
| Make command history a first-class Toolbelt surface | Added a Commands tab with count, preview rows, an All action, and direct command insertion. | `toolbelt previews shell history and paste sources` asserts `git status` appears and tapping `toolbelt-command-history-entry-0` writes the command bytes. |
| Make recent directories a first-class Toolbelt surface | Added a Dirs tab with count, preview rows, an All action, and direct `cd` insertion through the existing shell-quoting path. | `toolbelt previews shell history and paste sources` asserts `/tmp/project` appears and tapping `toolbelt-recent-directory-entry-0` writes `cd /tmp/project`. |
| Keep captured output discoverable without leaving Toolbelt | Added an Output tab with count, preview rows, and a full-sheet Open action. | `toolbelt opens a sidebar with terminal tool shortcuts` switches to Output, asserts `ERROR 42 failed`, then opens `captured-output-sheet`. |
| Bring paste history into the same IA | Added a Paste tab with count, preview rows, and a full-sheet Open action. | `toolbelt previews shell history and paste sources` records a paste, asserts the preview text, then opens `paste-history-sheet`. |
| Preserve supporting terminal utilities | Prompt marks, tmux, coprocesses, annotations, instant replay, password manager, and completion diagnostics remain below the primary panel. | Existing `toolbelt` and `shell integration utilities` tests still pass, including completion diagnostics and utility sheets. |

## Implementation Note

`_ShellToolbelt` now receives the captured-output entries, paste-history entries, and `TerminalShellIntegrationSnapshot` instead of count-only fields. Direct Toolbelt sends use `_sendPlainTextToSession`, so read-only mode and focus handling stay centralized.

# Ianvs Terminal Paste Safety Proof

Date: 2026-06-25

Scope: automated recapture for the paste paths called out by `T-UX-007`.

## Evidence Commands

```sh
cd example && flutter test test/widget_test.dart --plain-name "paste"
cd example && flutter test test/widget_test.dart --plain-name "read-only"
cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "paste"
cd example && flutter test test/terminal_input_controller_test.dart --plain-name "paste"
```

Latest results in this worktree:

- `flutter test test/widget_test.dart --plain-name "paste"`: passed.
- `flutter test test/widget_test.dart --plain-name "read-only"`: passed.
- `flutter test test/shell/shell_screen_phase4_test.dart --plain-name "paste"`: passed.
- `flutter test test/terminal_input_controller_test.dart --plain-name "paste"`: passed.
- `flutter test test/widget_test.dart`: passed.

2026-06-28 rerun:

- `cd example && flutter test test/widget_test.dart test/shell/shell_screen_phase1b_test.dart test/terminal/render_terminal_viewport_test.dart`: passed, 196 tests. This includes command-menu paste, advanced paste, paste history, saved paste history shortcut, multiline history confirmation, and read-only paste blocking tests from `test/widget_test.dart`.
- `cd example && flutter test test/shell/shell_screen_phase4_test.dart --plain-name "paste"`: passed, 4 tests.
- `cd example && flutter test test/terminal_input_controller_test.dart --plain-name "paste"`: passed, 4 tests.

## Matrix

| Path | Expected safety behavior | Automated proof |
| --- | --- | --- |
| Command menu paste | Sends plain clipboard text to the active session when allowed. | `command menu paste sends clipboard text to the active session` asserts UTF-8 bytes reach `FakePtyBackend.writes`. |
| Multiline paste warning | Requires confirmation before sending newline or carriage-return content. | `command menu paste confirms carriage-return multiline text` asserts the confirmation dialog opens and no bytes are written before confirmation. |
| Paste history | Records allowed paste text in memory, supports persistence, and reuses entries. | `command menu paste records text for paste history reuse and persistence` covers capture, persistence toggle, and reuse. |
| Saved history shortcut | `Cmd+Shift+H` opens saved history without leaking shortcut input. | `command-shift-h opens saved paste history without leaking input` asserts the sheet opens and `FakePtyBackend.writes` stays empty until an entry is picked. |
| Multiline history entry | Requires confirmation before replaying multiline history. | `paste history confirms multiline entries before sending` asserts dialog-first behavior and cancel keeps writes empty. |
| Advanced paste | Lets users inspect and transform clipboard text before sending. | `advanced paste transforms edited clipboard text before sending` asserts edited, escaped, base64, newline-transformed bytes are sent. |
| Bracketed paste | Wraps paste bytes with bracketed-paste guards when the terminal/config policy requires it. | `local paste config can force bracketed paste wrapping` and `xterm keyboard paste uses bracketed paste when the mode is enabled` assert `ESC[200~ ... ESC[201~`. |
| Read-only command menu | Paste actions are visibly disabled and do not write while read-only is enabled. | `read-only mode disables paste actions in the command menu` asserts disabled messaging and empty PTY writes. |
| Read-only shortcut/native paste | `Cmd+V` and macOS native Paste are blocked before clipboard read and before PTY write while read-only is enabled. | `read-only mode blocks shortcut and native paste before clipboard read` asserts zero clipboard reads and zero writes, then verifies normal paste resumes after read-only is disabled. |

## Implementation Note

`_pasteToSession` now checks `_isSessionReadOnly(sessionId)` before calling `ClipboardBridge.paste()`. `_pasteTextToSession` keeps its read-only guard as a second-layer defense for delayed or indirect sends.

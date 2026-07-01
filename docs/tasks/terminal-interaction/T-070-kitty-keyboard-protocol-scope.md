# T-070 Kitty Keyboard Protocol Scope

## Goal

Decide and, if accepted, add ianvs terminal support for kitty keyboard protocol reporting without regressing existing xterm-style key handling.

## Scope

- Scope decision for kitty keyboard protocol (`CSI u` / disambiguation modes).
- Parser mode state needed to expose the enabled kitty keyboard flags.
- `TerminalInputController` output when kitty mode is enabled.
- Ctrl-C behavior under fish/newer shells when kitty keyboard mode is active.

## Non-goals

- Do not change default xterm key sequences unless a kitty mode is explicitly active.
- Do not change app-level shortcuts outside the terminal input controller.
- Do not cover Android or Windows platform-key duplication here; those belong to T-074.

## Files In Scope

- `packages/ianvs_terminal/lib/src/terminal/terminal_input_controller.dart`
- `packages/ianvs_terminal/test/terminal_input_controller_test.dart`
- `example/test/terminal_input_controller_test.dart`
- `native/core/src/model.rs`
- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/csi/keyboard.rs` implements Kitty keyboard flag query, set/add/clear, push, and pop sequences.
- `native/vendor/par-term-emu-core-rust/src/terminal/mod.rs` scopes Kitty keyboard flags and stacks across primary vs alternate screen buffers.
- `packages/ianvs_terminal/lib/src/terminal/terminal_input_controller.dart` emits `CSI u` input when kitty disambiguation/report-all flags are active while preserving default xterm key bytes when flags are zero.
- Report-all plus `Report associated text` (`flags & 16`) appends sanitized Unicode codepoint payloads to Kitty `CSI u` events; control codepoints are filtered and the flag does not force plain text keys into CSI-u unless report-all is active.
- `cd packages/ianvs_terminal && flutter test test/terminal_input_controller_test.dart --plain-name kitty` covers C0 exceptions, Ctrl-C disambiguation, modifier-only suppression, report-all modifier-only output, repeat/release event metadata, and associated text codepoint payloads.
- Computer Use manual pass on 2026-05-29, macOS 15.7.7: in fish normal mode, `sleep 10` was interrupted by ETX and the terminal showed `^C` plus `[SIGINT]`.
- Kitty keyboard support is now accepted for ianvs terminal's xterm256 surface as an opt-in protocol mode; default xterm key sequences remain unchanged when kitty flags are zero.

## Functional Acceptance

- A scope note states whether kitty keyboard protocol is in ianvs terminal's supported terminal surface. Current decision: accepted for opt-in xterm256 sessions.
- Parser tests cover enabling, adding, clearing, querying, push/pop, empty-stack reset, and alternate-screen stack isolation for the relevant kitty keyboard flags.
- Input tests cover space, enter, tab, backspace, modifier-only events, Ctrl-C under kitty mode, repeat/release metadata, and associated text payloads.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd packages/ianvs_terminal
flutter test test/terminal_input_controller_test.dart --plain-name kitty

cd ../../example
flutter test test/terminal_input_controller_test.dart --plain-name Kitty

cd ../native/core
cargo test --test session_test kitty_keyboard
```

## Manual QA

1. In fish, enable kitty keyboard protocol from the shell or a small probe script.
2. Press Ctrl-C, Enter, Tab, Backspace, Space, and modifier-only combinations.
3. Confirm the app sends the expected bytes and shell interrupt behavior still works.

## Done When

- The kitty keyboard decision is documented.
- Covered behavior has automated tests or explicit deferral.
- Related audit rows link back to this task.

## Risks / Follow-ups

- Flutter may not expose every low-level physical-key/modifier transition needed for full kitty parity on every platform.
- Flutter may report longer composition strings differently across platforms; keep platform-specific probes in T-074 if associated-text behavior diverges outside macOS.

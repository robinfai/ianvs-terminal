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

- `rg -n "kitty|CSI u|disambiguate" packages/ianvs_terminal/lib native/core/src example/test packages/ianvs_terminal/test` finds no ianvs terminal kitty keyboard protocol mode or `CSI u` input path.
- `cd packages/ianvs_terminal && flutter test test/terminal_input_controller_test.dart --plain-name "Control letters"` passes local Control A-Z C0-byte mapping, including Ctrl-C, but it does not exercise kitty mode.
- Computer Use manual pass on 2026-05-29, macOS 15.7.7: in fish normal mode, `sleep 10` was interrupted by ETX and the terminal showed `^C` plus `[SIGINT]`.
- Kitty protocol support remains a product-scope decision queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md) item M-010 before any implementation.
- The audit row is deferred until M-010 decides whether kitty keyboard protocol belongs in ianvs terminal's supported surface; default xterm key sequences remain unchanged.

## Functional Acceptance

- A scope note states whether kitty keyboard protocol is in ianvs terminal's supported terminal surface. Current decision: deferred pending M-010 product-scope confirmation.
- If in scope, parser tests cover enabling/disabling the relevant kitty keyboard flags.
- If in scope, input tests cover space, enter, tab, backspace, modifier-only events, and Ctrl-C under kitty mode.
- If out of scope, the audit rows are marked `Deferred` with an explicit rationale. Done in `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md` pending M-010.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/terminal_input_controller_test.dart --plain-name kitty

cd native/core
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

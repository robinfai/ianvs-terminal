# T-069 Synchronized Output Mode Contract

## Goal

Define and implement a ianvs terminal runtime contract for xterm synchronized output mode (`CSI ? 2026 h/l`) so writes can defer visible frame publication during synchronized-output blocks.

## Scope

- Native parser/session handling for `CSI ? 2026 h` and `CSI ? 2026 l`.
- Frame publication semantics while synchronized output is active.
- Flutter runtime/facade behavior needed to avoid stale or flickering viewport updates.
- Regression probes for xterm.js rows #5453 and #5770.

## Non-goals

- Do not change unrelated resize, scrollback, or renderer behavior.
- Do not add xterm.js addon APIs.
- Do not optimize parser throughput in this task.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/csi/mode.rs`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `rg -n "2026|synchronized" native/core/src native/vendor/par-term-emu-core-rust/src` shows a vendored parser toggle, but no ianvs terminal `TerminalFrameModes` field or runtime frame deferral contract.
- `cargo test --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml test_synchronized_updates_mode_toggle` is not currently usable on this host; it fails at link time with unresolved Python/PyO3 symbols.

## Functional Acceptance

- A native regression proves output written between `CSI ? 2026 h` and `CSI ? 2026 l` is not published as intermediate visible frames.
- Disabling synchronized output flushes the latest visible frame exactly once.
- Resize and clipboard events still flow while synchronized output is active.
- The audit rows for xterm.js #5453 and #5770 are updated with the final command evidence.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test session_test synchronized_output

cd packages/ianvs_terminal
flutter test test/terminal_runtime_controller_test.dart --plain-name synchronized
```

## Manual QA

1. Run a command that prints `CSI ? 2026 h`, rapidly writes several screen updates, then prints `CSI ? 2026 l`.
2. Confirm the terminal shows the final state without intermediate flicker.
3. Resize the window during the block and confirm the terminal remains responsive after the block ends.

## Done When

- Synchronized output has a named runtime contract and tests.
- No product code outside the scoped runtime/frame path changes.
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md` links this task and records passing verification.

## Risks / Follow-ups

- The vendored parser test target currently needs host/toolchain repair before it can be used as direct evidence.

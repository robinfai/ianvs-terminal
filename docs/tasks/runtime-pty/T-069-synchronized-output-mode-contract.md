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

- `cargo test --manifest-path native/core/Cargo.toml --test session_test synchronized_output` passes and proves output between `CSI ? 2026 h` and `CSI ? 2026 l` is not published as an intermediate frame; disabling synchronized output flushes the final visible frame; OSC 52 clipboard copy and CSI resize host callbacks still arrive before the visible synchronized frame flush.
- The vendored parser still owns the `CSI ? 2026 h/l` mode toggle and update buffer. The ianvs session contract is frame-publication level: Flutter receives only the final native frame, so no separate viewport deferral state is required. The Flutter runtime regression `terminal runtime keeps synchronized output null frames hidden until final polling frame` proves native-null synchronized frames do not emit a frame event or repaint stale content before the final frame arrives.
- `cargo test --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml test_synchronized_updates_mode_toggle` is not currently usable on this host; it fails at link time with unresolved Python/PyO3 symbols.

## Functional Acceptance

- A native regression proves output written between `CSI ? 2026 h` and `CSI ? 2026 l` is not published as intermediate visible frames. Done with `session_synchronized_output_defers_intermediate_frames_until_disable`.
- Disabling synchronized output flushes the latest visible frame exactly once. Done with `session_synchronized_output_defers_intermediate_frames_until_disable`.
- Resize and clipboard events still flow while synchronized output is active. Done with `session_synchronized_output_allows_host_events_before_visible_flush`.
- Flutter polling keeps null synchronized-output frames hidden until the native final frame is available. Done with `terminal runtime keeps synchronized output null frames hidden until final polling frame`.
- The audit rows for xterm.js #5453 and #5770 are updated with the final command evidence. Done in `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`.

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

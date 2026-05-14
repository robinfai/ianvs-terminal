# T-073 Parser, OSC, SGR, and Clipboard xterm Probes

## Goal

Add targeted parser/OSC/SGR probes for recent xterm.js fixes before changing terminal parsing behavior.

## Scope

- OSC 4 alpha query/reporting behavior.
- Individual SGR reset edge cases from xterm.js #4958.
- APC sequence handling support or explicit unsupported status.
- Color-bit/style regression from xterm.js #5856.
- OSC 52 base64 edge cases.
- Non-CSI parser regression and CSI fast-path safety probes.

## Non-goals

- Do not add JavaScript parser hook APIs.
- Do not change clipboard security policy without a separate design note.
- Do not add performance benchmarks here; parser throughput belongs to T-076.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `native/core/tests/vttest_regression_test.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/osc/color.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/osc/clipboard.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/csi/style.rs`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `native/vendor/.../osc/color.rs` supports OSC 4 set/reset, while OSC 10/11/12 query paths exist; OSC 4 query and alpha reporting are not implemented in that handler.
- `native/core` passes current OSC 52 copy/paste behavior under `cargo test --test session_test clipboard`.
- Runtime source decodes clipboard-copy payloads with `base64.decode(raw)` and does not have invalid, padded, or whitespace-sensitive edge fixtures yet.
- `rg -n "APC|apc" native/vendor/par-term-emu-core-rust/src/terminal/perform.rs native/core/src/session.rs` finds no APC dispatch surface in the flutterm runtime path.
- `cargo test --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml test_clipboard_operations` is blocked on this host by PyO3/Python linker symbols, so vendored tests cannot be used as completion evidence yet.

## Functional Acceptance

- Add native fixtures for OSC 4 query/alpha behavior or explicitly document unsupported status.
- Add xterm-derived SGR reset fixtures for each missing reset case.
- Add an APC fixture that proves support or a documented unsupported no-op.
- Add OSC 52 base64 edge-case tests for invalid payload, padding, and empty payload preservation.
- Add non-CSI parser regression fixture tied to xterm.js #5825.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test vttest_regression_test
cargo test --test session_test clipboard
cargo test --test session_test parser
```

## Manual QA

Manual QA is optional if the native fixtures cover the parser state and host callback events. If OSC 52 host clipboard behavior changes, verify copy/paste in the example app.

## Done When

- Each parser/OSC/SGR row has either a passing regression or an explicit unsupported-status decision.
- The audit table points to the exact regression command.
- No parser behavior is changed without a failing probe.

## Risks / Follow-ups

- Vendored parser tests currently have a host-linking blocker unrelated to these behaviors.

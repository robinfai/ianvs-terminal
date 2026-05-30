# T-073 Parser, OSC, SGR, and Clipboard xterm Probes

## Goal

Add targeted parser/OSC/SGR probes for recent xterm.js fixes before changing terminal parsing behavior.

## Scope

- OSC 4 alpha query/reporting behavior.
- OSC 8 overwritten hyperlink hit-target clearing.
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
- `example/test/terminal/render_terminal_viewport_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `native/vendor/.../osc/color.rs` now supports OSC 4 query responses for the RGB-backed 0-15 ANSI palette and accepts alpha-bearing color specs by parsing their RGB channels only; `cargo test --manifest-path native/core/Cargo.toml --test session_test osc4` passes.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test sgr_reset_cases` passes and pins individual SGR reset cases for bold/dim, italic, underline, blink, inverse, hidden, strikethrough, foreground/background color, overline, and underline color.
- `native/core` passes current OSC 52 copy/paste behavior under `cargo test --test session_test clipboard`.
- Runtime OSC 52 clipboard copy handling now ignores invalid base64 payloads, accepts whitespace/padded payloads, and preserves empty payloads as an empty clipboard copy.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test apc` passes and proves APC is currently an unsupported no-op: APC payload does not render into terminal rows or app events, while surrounding printable text remains intact.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test pm_and_sos` passes and proves PM/SOS non-CSI string controls are unsupported no-ops: payloads do not render or surface through app events.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test sgr_colon_truecolor` passes and proves SGR truecolor colon subparams skip the optional empty color-space-id for foreground/background RGB parsing.
- `cd example && flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport clears stale OSC 8 hit targets"` passes and proves a dirty-row overwrite removes the prior OSC 8 hyperlink hit target before tap handling.
- `cargo test --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml test_clipboard_operations` is blocked on this host by PyO3/Python linker symbols, so vendored tests cannot be used as completion evidence yet.

## Functional Acceptance

- Add native fixtures for OSC 4 query/alpha behavior or explicitly document unsupported status. Done with `session_osc4_query_reports_rgb_for_alpha_color_specs`.
- Add xterm-derived SGR reset fixtures for each missing reset case. Done with `parser_sgr_reset_cases_clear_individual_attributes`.
- Add an APC fixture that proves support or a documented unsupported no-op. Done with `session_apc_sequence_is_unsupported_noop`.
- Add a color-bit/style fixture for xterm.js #5856-style RGB parsing. Done with `session_sgr_colon_truecolor_skips_empty_color_space_id`.
- Add OSC 52 base64 edge-case tests for invalid payload, padding, and empty payload preservation. Done in `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`.
- Add an OSC 8 stale-hit-target regression for overwritten linked cells. Done in `example/test/terminal/render_terminal_viewport_test.dart`.
- Add non-CSI parser regression fixture tied to xterm.js #5825. Done with `session_pm_and_sos_sequences_are_unsupported_noops`.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test vttest_regression_test
cargo test --test session_test clipboard
cargo test --manifest-path native/core/Cargo.toml --test session_test osc4
cargo test --manifest-path native/core/Cargo.toml --test session_test sgr_reset_cases
cargo test --manifest-path native/core/Cargo.toml --test session_test apc
cargo test --manifest-path native/core/Cargo.toml --test session_test pm_and_sos
cargo test --manifest-path native/core/Cargo.toml --test session_test sgr_colon_truecolor
cargo test --test session_test parser

cd packages/ianvs_terminal
flutter test test/terminal_runtime_controller_test.dart --plain-name "OSC 52 base64 copy edge cases"
flutter test test/terminal_runtime_controller_test.dart

cd example
flutter test test/terminal/render_terminal_viewport_test.dart --plain-name "terminal viewport clears stale OSC 8 hit targets"
```

## Manual QA

Manual QA is optional if the native fixtures cover the parser state and host callback events. If OSC 52 host clipboard behavior changes, verify copy/paste in the example app.

## Done When

- Each parser/OSC/SGR row has either a passing regression or an explicit unsupported-status decision.
- The audit table points to the exact regression command.
- No parser behavior is changed without a failing probe.

## Risks / Follow-ups

- Vendored parser tests currently have a host-linking blocker unrelated to these behaviors.

# Compatibility Test Asset Inventory

This inventory records reusable Iteration 01 evidence. Counts are test source files, not test cases,
and were collected on 2026-07-21 with `rg --files`.

| Layer | Location | Files | Reusable for compatibility baseline | Current gap |
| --- | --- | ---: | --- | --- |
| Rust native/session | `native/core/tests/` | 3 | Real PTY/session lifecycle, frame diff, OSC corpus, VT220 regressions, resize/reflow, graphics | Linux/Windows host execution is absent |
| Vendored parser | `native/vendor/par-term-emu-core-rust/src/` inline tests | many modules | Parser/state behavior, Unicode cells, CSI/OSC/DCS, Sixel and Kitty parsing | Not an app/runtime E2E by itself |
| Dart FFI | `packages/ianvs_pty/test/` | 1 | Native API validation, frame/event forwarding, bounds and failure decoding | Real dynamic-library behavior is covered later by macOS integration, not this unit file |
| Flutter terminal package | `packages/ianvs_terminal/test/` | 26 | Frame decode/parity, runtime scheduling, input, focus, mouse, graphics, viewport, text cells | Physical keyboard/IME/device matrix is not automated |
| Example unit/widget | `example/test/` | 129 | Shell product, policies, session controller, viewport, profiles, workspace and macOS bridge contracts | Cannot prove real PTY or native app lifecycle alone |
| Example integration | `example/integration_test/` | 5 | macOS smoke, real PTY acceptance, render/transport profiles, real `vttest` GUI | Requires macOS Flutter device; full `vttest` case also requires the external binary |
| Root docs contracts | `test/` | 1 | Execution target, documentation link and compatibility evidence contracts | Static evidence only |
| Benchmark tests | `tools/bench/test/` | 2 | Deterministic benchmark tooling and gate behavior | Cross-machine performance baseline is absent |

## Reusable local verification helpers

| Helper | Purpose | Reuse decision |
| --- | --- | --- |
| `Makefile` | Stable `bootstrap`, `analyze`, `test`, `verify` entry points | Primary Iteration 01 gate |
| `tools/verify_flutter_terminal.sh` | Rust, Dart/Flutter, docs, benchmark, macOS smoke and real PTY chain | Primary full verification implementation |
| `tools/vttest_gui_nightly.sh` | Deterministic VT regressions plus real macOS GUI `vttest` | Reuse; Homebrew `vttest` 20251205 passed on this host on 2026-07-21, while a missing binary elsewhere must still be recorded as blocked |
| `tools/check_terminal_manual_matrix_prereqs.sh` | Host/tooling prerequisite inspection | Reuse before manual validation |
| `tools/run_release_real_pty_refresh_gate.sh` | Bounded release-app real PTY refresh verification | Reuse for release-specific changes, not required by this baseline |
| `tools/local_terminal_verification_*.sh` | Print, run and capture existing local-terminal verification batches | Reuse; captured output does not automatically become evidence |
| `tools/bench/configs/bench_ci_smoke.yaml` | Deterministic frame/runtime performance smoke | Reuse inside `make verify` |

## Fixtures now owned by Iteration 01

- Deterministic shell lifecycle fixture in `example/integration_test/real_pty_acceptance_test.dart`.
- Deterministic alternate-screen TUI fixture in the same suite; it does not depend on `vttest`.
- Unicode/width/cursor fixture using OSC 1337 UnicodeVersion and resize continuation.
- Untruncated resize replay regression and truncated transcript boundary regression in
  `native/core/tests/session_test.rs`.
- Existing OSC corpus fixture at `native/core/tests/fixtures/osc/osc_protocol_corpus_v1.json`.

## Missing or intentionally external evidence

- `vttest` is an external host dependency. The real gate passed on this host with Homebrew `vttest`
  20251205, but the deterministic alternate-screen fixture remains the portable required E2E and
  real `vttest` remains a supplemental nightly/manual gate.
- Linux and Windows app runners, PTY backends and verification lanes are absent.
- Font fallback, DPI, display switching, physical trackpad and real system notification surfaces
  require the manual matrix.
- Cross-machine CPU/RSS comparisons do not yet have a normalized baseline.
- Recording/replay infrastructure belongs to Iteration 03 and is intentionally not added here.

# T-306 Frame Delta Builder Extraction

## Goal

Continue handoff Iteration 02 with one behavior-preserving Frame slice: move Delta row candidate
scanning, cache comparison and dirty-range construction out of the native Session aggregate.

## Scope

- Define a private `DeltaFrameContext` around the common `FrameBuildContext`, pending damage,
  previous row cache and viewport shift.
- Move Delta candidate scanning, row extraction, cache updates and dirty-range merging to
  `session/frame/delta.rs`.
- Add independent module tests for changed and unchanged candidate rows.
- Preserve the existing Snapshot, damage, display projection and graphics projection behavior.
- Compare the deterministic Frame benchmark before and after the extraction.

## Non-goals

- Do not change the JSON or Protobuf Frame schema, FFI, or public Rust surface.
- Do not change row candidate, cache shift, Snapshot fallback or viewport-shift decisions.
- Do not extract Display Projection or Graphics Projection in this task.
- Do not refactor Host Protocol, resize/reflow, Parser, Recording / Replay or UI.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/frame/delta.rs`
- `native/core/src/session/frame/mod.rs`
- `docs/tasks/runtime-pty/T-306-frame-delta-builder-extraction.md`

## Functional Acceptance

- `take_frame_diff` delegates the Delta path through an explicit `DeltaFrameContext`.
- Delta candidate scanning, row comparison, cache updates and dirty-range construction no longer
  live in `session.rs`.
- Changed candidate rows emit the same rows and damage while unchanged candidates update no
  external state.
- Golden/parity output and all six deterministic benchmark correctness hashes remain unchanged.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test -- --test-threads=1

cd ../../packages/ianvs_terminal
flutter test test/terminal_frame_diff_corpus_test.dart test/terminal_frame_codec_parity_test.dart

cd ../..
make verify
```

## Result

- Added `session/frame/delta.rs` with the private `DeltaFrameContext` and `build_delta_frame`.
  The module now owns candidate-row scanning, row extraction, cache comparison/update and
  dirty-range merging for Delta frames.
- Added independent changed-candidate and unchanged-candidate module tests. Existing style-only,
  row-shift and bounded-burst Delta regressions also passed through the extracted boundary.
- Reduced `session.rs` from 9,696 to 9,630 lines without changing public Rust, FFI, JSON or
  Protobuf surfaces.
- `cargo fmt --all -- --check` and `cargo clippy --all-targets -- -D warnings` passed. Native unit
  tests increased from 110 to 112; the serialized native suite passed 112 unit tests, 1 OSC corpus
  test, 512 session tests and 3 vttest regressions.
- Default parallel native runs exposed pre-existing PTY timing interference in old burst/damage
  tests; every affected test passed independently and in the complete serialized suite. No
  production behavior or assertion was weakened to hide that scheduling sensitivity.
- Frame golden and JSON/Protobuf parity tests passed 35/35.
- Pre-extraction benchmark `build/bench-results-ci/20260721T014206Z` and post-extraction benchmark
  `build/bench-results-ci/20260721T015114Z` produced byte-identical correctness files for all six
  workload/policy pairs. Coalescing ratios and p95 frame-build / JSON-decode / apply timings were
  unchanged; only ungated host CPU/RSS samples varied.
- The first final `make verify` attempt reached macOS smoke after every earlier gate passed, but a
  transient host foreground failure left the command-palette shortcut undelivered. The identical
  smoke gate then passed 4/4 independently, and the complete `make verify` rerun passed from start
  to finish.
- That final run wrote benchmark evidence to `build/bench-results-ci/20260721T021112Z`, whose six
  correctness hashes are also byte-identical to the pre-extraction baseline. Vendored Rust passed
  1,733 tests with 1 ignored; native core passed 112 unit tests, 1 OSC corpus test, 512 session
  tests and 3 vttest regressions; `ianvs_pty` passed 22 tests; `ianvs_terminal` passed 485 tests
  with 1 intentional skip; docs passed 12; example passed 1,063; macOS smoke passed 4/4; real PTY
  passed 46/46; and Runner XCTest passed 16/16.

## Remaining Iteration 02 Work

- Extract Display Projection.
- Extract Graphics Projection.
- Keep Host Protocol, resize/reflow and Recording / Replay outside those follow-up slices.

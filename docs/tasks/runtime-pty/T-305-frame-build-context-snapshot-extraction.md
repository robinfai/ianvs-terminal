# T-305 Frame Build Context and Snapshot Extraction

## Goal

Continue handoff Iteration 02 with one behavior-preserving Frame slice: make the common frame-builder
inputs explicit and move contiguous and folded Snapshot construction out of the native Session
aggregate.

## Scope

- Define a private `FrameBuildContext` containing the immutable terminal, emulation, projection,
  viewport, scrollback and alternate-screen inputs shared by Frame builders.
- Make the existing Delta path consume the common context without moving Delta behavior in this
  task.
- Move contiguous and folded Snapshot row construction to `session/frame/snapshot.rs`.
- Add independent module tests for full-viewport and zero-height Snapshot behavior.
- Compare the deterministic Frame benchmark before and after the extraction.

## Non-goals

- Do not change the JSON or Protobuf Frame schema, FFI, or public Rust surface.
- Do not change Snapshot fallback, damage, cache, row-shift or Delta behavior.
- Do not extract Delta, Display Projection or Graphics Projection in this task.
- Do not refactor Host Protocol, resize/reflow, Parser, Recording / Replay or UI.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/frame/context.rs`
- `native/core/src/session/frame/snapshot.rs`
- `native/core/src/session/frame/mod.rs`
- `docs/tasks/runtime-pty/T-305-frame-build-context-snapshot-extraction.md`

## Functional Acceptance

- `take_frame_diff` constructs one explicit `FrameBuildContext` and the Snapshot and Delta paths
  consume it.
- Contiguous and folded Snapshot row construction no longer lives in `session.rs`.
- Snapshot still emits the complete viewport, cache state, hyperlinks and one full dirty range.
- Folded blocks still emit mapped source ranges and padded viewport rows.
- Golden/parity output and all six deterministic benchmark correctness hashes remain unchanged.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test

cd ../../packages/ianvs_terminal
flutter test test/terminal_frame_diff_corpus_test.dart test/terminal_frame_codec_parity_test.dart

cd ../..
make verify
```

## Result

- Added `session/frame/context.rs` with the private common `FrameBuildContext` and shared row-build
  result boundary. `take_frame_diff` now creates one context used by both Snapshot and the existing
  in-place Delta builder.
- Added `session/frame/snapshot.rs`; it owns contiguous/folded selection, full-viewport row and
  hyperlink collection, cached row generation and Snapshot dirty-range construction.
- Added independent contiguous and zero-height Snapshot tests. The existing folded-block test now
  enters through the same public-to-Session Snapshot builder boundary.
- Reduced `session.rs` from 9,814 to 9,696 lines without changing public Rust, FFI, JSON or Protobuf
  surfaces.
- `cargo fmt --all -- --check` and `cargo clippy --all-targets -- -D warnings` passed. Native unit
  tests increased from 108 to 110; the complete 512-test PTY session suite passed serially after two
  timing-sensitive cases also passed independently.
- Frame golden and JSON/Protobuf parity tests passed 35/35.
- Pre-extraction benchmark `build/bench-results-ci/20260721T012951Z` and post-extraction benchmark
  `build/bench-results-ci/20260721T013647Z` produced byte-identical correctness files for all six
  workload/policy pairs. Coalescing ratios and p95 frame-build / JSON-decode / apply timings were
  unchanged; only ungated host CPU/RSS samples varied.
- The final `make verify` passed and wrote benchmark evidence to
  `build/bench-results-ci/20260721T014206Z`: vendored Rust passed 1,733 tests with 1 ignored,
  native core passed 110 unit tests, 1 OSC corpus test, 512 session tests and 3 vttest regressions,
  macOS smoke passed 4/4, real PTY passed 46/46 and Runner XCTest passed 16/16.

## Remaining Iteration 02 Work

- Extract the Delta Builder behind `FrameBuildContext`.
- Extract Display Projection and Graphics Projection.
- Keep Host Protocol, resize/reflow and Recording / Replay outside those follow-up slices.

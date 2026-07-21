# T-307 Frame Display Projection Extraction

## Goal

Continue handoff Iteration 02 with one behavior-preserving Frame slice: move folded-block display
projection construction and source/display row mapping out of the native Session aggregate.

## Scope

- Move `DisplayProjection`, its row/range types and source/display mapping helpers to
  `session/frame/projection.rs`.
- Move terminal-to-display projection construction and projected source-span calculation behind
  the private Frame module boundary.
- Add independent module tests for identity and nested-fold projection behavior.
- Preserve existing Snapshot, Delta, search, block, inline-button, sized-text and graphics use of
  the projection.
- Compare the deterministic Frame benchmark before and after the extraction.

## Non-goals

- Do not change the JSON or Protobuf Frame schema, FFI, or public Rust surface.
- Do not change fold eligibility, retained-row clipping, nested-range precedence or row mapping.
- Do not extract Graphics Projection in this task.
- Do not refactor Host Protocol, resize/reflow, Parser, Recording / Replay or UI.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/frame/context.rs`
- `native/core/src/session/frame/delta.rs`
- `native/core/src/session/frame/mod.rs`
- `native/core/src/session/frame/projection.rs`
- `native/core/src/session/frame/snapshot.rs`
- `docs/tasks/runtime-pty/T-307-frame-display-projection-extraction.md`

## Functional Acceptance

- Display projection construction and all source/display row mapping primitives no longer live in
  `session.rs`.
- Identity projection keeps one display row per retained source row.
- Nested folded ranges retain the outer summary mapping and projected source span.
- Existing folded Snapshot, search, blocks, inline buttons, sized text and graphics remain
  behaviorally unchanged.
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

- Added `session/frame/projection.rs`; it now owns `DisplayProjection`, collapsed ranges,
  terminal-to-display projection construction, source/display lookup, collapsed-range
  intersection and projected source-span calculation.
- Added independent identity and nested-fold projection tests. Existing folded Snapshot, nested
  block, inline-button, search, sized-text and graphics regressions passed through the extracted
  boundary.
- Reduced `session.rs` from 9,630 to 9,468 lines without changing public Rust, FFI, JSON or
  Protobuf surfaces.
- `cargo fmt --all -- --check` and `cargo clippy --all-targets -- -D warnings` passed. Native unit
  tests increased from 112 to 114; the serialized native suite passed 114 unit tests, 1 OSC corpus
  test, 512 session tests and 3 vttest regressions.
- Frame golden and JSON/Protobuf parity tests passed 35/35.
- Pre-extraction benchmark `build/bench-results-ci/20260721T021112Z` and post-extraction benchmark
  `build/bench-results-ci/20260721T022205Z` produced byte-identical correctness files for all six
  workload/policy pairs. Coalescing ratios and p95 frame-build / JSON-decode / apply timings were
  unchanged; only ungated host CPU/RSS samples varied.
- The final `make verify` passed and wrote benchmark evidence to
  `build/bench-results-ci/20260721T022641Z`, whose six correctness hashes are also byte-identical
  to the pre-extraction baseline. Vendored Rust passed 1,733 tests with 1 ignored; native core
  passed 114 unit tests, 1 OSC corpus test, 512 session tests and 3 vttest regressions;
  `ianvs_pty` passed 22 tests; `ianvs_terminal` passed 485 tests with 1 intentional skip; docs
  passed 12; example passed 1,063; macOS smoke passed 4/4; real PTY passed 46/46; and Runner
  XCTest passed 16/16.

## Remaining Iteration 02 Work

- Extract Graphics Projection.
- Keep Host Protocol, resize/reflow and Recording / Replay outside that final follow-up slice.

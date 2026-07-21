# T-304 Frame Pipeline Damage Extraction

## Goal

Start handoff Iteration 02 with a behavior-preserving frame-pipeline slice: strengthen the structured
frame golden corpus, then move cache, damage, viewport-shift and snapshot-fallback decisions out of
the 10,303-line `session.rs` aggregate.

## Scope

- Treat the existing snapshot and delta frame corpus as the pre-refactor wire golden baseline.
- Add explicit golden coverage for graphics, blocks and hyperlinks.
- Create `native/core/src/session/frame/` without changing public module or FFI surfaces.
- Extract cached row/frame metadata, pending damage aggregation, delta candidate selection,
  viewport row-shift decisions, snapshot fallback decisions and dirty-range merging.
- Compare the deterministic frame benchmark before and after the extraction.

## Non-goals

- Do not change the JSON or Protobuf frame schema.
- Do not change snapshot/delta behavior or fallback reason strings.
- Do not refactor Host Protocol, resize/reflow, parser behavior, recording/replay or UI.
- Do not extract the full snapshot, delta, display or graphics builders in this slice.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/frame/`
- `packages/ianvs_terminal/test/terminal_frame_diff_corpus_test.dart`
- `packages/ianvs_terminal/test/fixtures/frame_diff_corpus/`
- `docs/tasks/runtime-pty/T-304-frame-pipeline-damage-extraction.md`

## Functional Acceptance

- Snapshot and delta fixtures remain schema-compatible and decode to the same public model.
- The golden corpus contains non-empty graphics, blocks and hyperlinks evidence.
- Existing snapshot fallback reason, viewport row shift, synchronized output and deferred graphics
  regressions remain green.
- `session.rs` delegates pure damage/cache decisions to `session/frame/damage.rs`.
- Benchmark hashes and configured performance gates remain green.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test

cd ../../packages/ianvs_terminal
flutter test test/terminal_frame_diff_corpus_test.dart

cd ../..
make verify
```

## Result

- Strengthened the structured frame corpus with explicit graphics, blocks and hyperlinks counts and
  a non-empty folded-block snapshot fixture. The enhanced assertion failed before fixture updates
  and passed afterward.
- Added `native/core/src/session/frame/damage.rs` and moved cached row/frame metadata, pending damage
  aggregation, delta candidate selection, cache shifting, viewport row-shift resolution, snapshot
  fallback selection and dirty-range merging behind the private `session::frame` boundary.
- Reduced `session.rs` from 10,303 to 9,814 lines. The new damage module is 591 lines including four
  focused unit tests; no public Rust, FFI, JSON or Protobuf surface changed.
- `cargo fmt --all -- --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test` passed.
  Native results were 108 unit tests, 1 OSC corpus test, 512 session tests and 3 vttest regressions.
- Frame golden and JSON/Protobuf parity tests passed 35/35.
- Pre-refactor benchmark `build/bench-results-ci/20260720T174035Z` and post-refactor benchmark
  `build/bench-results-ci/20260720T175506Z` produced identical coalescing ratios and p95
  frame/json/apply timings. All six hash comparisons were `true`; only ungated host CPU/RSS samples
  varied slightly.
- The final `make verify` passed and wrote benchmark evidence to
  `build/bench-results-ci/20260720T175822Z`; macOS smoke passed 4/4, real PTY passed 46/46 and Runner
  XCTest passed 16/16.

## Remaining Iteration 02 Work

- Define the full `FrameBuildContext` boundary.
- Extract snapshot and delta builders.
- Extract display and graphics projection.
- Keep Host Protocol, resize/reflow and Recording / Replay outside those follow-up slices.

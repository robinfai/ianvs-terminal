# T-308 Frame Graphics Projection Extraction

## Goal

Close handoff Iteration 02 with one behavior-preserving Frame slice: move graphics placement,
projection, geometry and asset snapshot gathering out of the native Session aggregate.

## Scope

- Move raw graphics placement construction and viewport clipping to
  `session/frame/graphics.rs`.
- Move folded-display graphics projection and Kitty placeholder scanning behind the private
  Frame module boundary.
- Move graphic asset id/version and pixel snapshot gathering to the Frame module while retaining
  asset cache lifecycle ownership in Session.
- Add independent module tests for identity and folded projection behavior.
- Compare the deterministic Frame benchmark before and after the extraction.

## Non-goals

- Do not change the JSON or Protobuf Frame schema, FFI, or public Rust surface.
- Do not change graphic cache retention/eviction, protocol parsing, Kitty placement semantics or
  viewport clipping behavior.
- Do not extract sized text or other non-graphics Session responsibilities.
- Do not refactor Host Protocol, resize/reflow, Parser, Recording / Replay or UI.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/frame/graphics.rs`
- `native/core/src/session/frame/mod.rs`
- `docs/tasks/runtime-pty/T-308-frame-graphics-projection-extraction.md`

## Functional Acceptance

- Raw and folded graphics placement construction, viewport geometry, Kitty placeholder scanning
  and asset snapshot gathering no longer live in `session.rs`.
- Identity projection preserves visible placement geometry.
- A graphic intersecting a collapsed source range is omitted from the projected display.
- Existing Kitty, scrollback, clipping, retransmit and asset-cache behavior remains unchanged.
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

- Added `session/frame/graphics.rs`; it now owns raw and folded-display placement construction,
  viewport clipping, Kitty placeholder geometry and graphic asset snapshot gathering. Session
  intentionally retains asset-cache lifetime and lookup ownership.
- Added independent identity and folded-range projection tests. Existing right-edge clipping,
  Kitty retransmit/cache and frame asset-byte regressions also passed through the extracted
  boundary.
- Reduced `session.rs` from 9,468 to 8,930 lines without changing public Rust, FFI, JSON or
  Protobuf surfaces.
- `cargo fmt --all -- --check` and `cargo clippy --all-targets -- -D warnings` passed. Native unit
  tests increased from 114 to 116; the serialized native suite passed 116 unit tests, 1 OSC corpus
  test, 512 session tests and 3 vttest regressions.
- Frame golden and JSON/Protobuf parity tests passed 35/35.
- Pre-extraction benchmark `build/bench-results-ci/20260721T022641Z` and post-extraction benchmark
  `build/bench-results-ci/20260721T023917Z` produced byte-identical correctness files for all six
  workload/policy pairs. Coalescing ratios and p95 frame-build / JSON-decode / apply timings were
  unchanged; only ungated host CPU/RSS samples varied.
- The final `make verify` passed and wrote benchmark evidence to
  `build/bench-results-ci/20260721T024435Z`, whose six correctness hashes are byte-identical to
  both the pre-extraction and focused post-extraction runs. Vendored Rust passed 1,733 tests with
  1 ignored; native core passed 116 unit tests, 1 OSC corpus test, 512 session tests and 3 vttest
  regressions; `ianvs_pty` passed 22 tests; `ianvs_terminal` passed 485 tests with 1 intentional
  skip; docs passed 12; example passed 1,063; macOS smoke passed 4/4; real PTY passed 46/46; and
  Runner XCTest passed 16/16.

## Final Disposition

- Iteration 02 is complete. Cache/damage, common context, Snapshot, Delta, display projection and
  graphics projection now live behind the private Frame boundary with unchanged external output.
- Host Protocol, resize/reflow and Recording / Replay remain outside this completed iteration.

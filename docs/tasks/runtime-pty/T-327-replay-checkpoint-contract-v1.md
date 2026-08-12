# T-327 Replay Checkpoint Contract v1

## Goal

Add a deterministic, backward-compatible current recording schema checkpoint marker and a
bounded native replay snapshot capability that future seek can use without
pretending timestamp-only markers are restorable state.

## Scope

- Keep live Recording capture and canonical current recording schema byte-stable.
- Add current recording schema metadata/events with one `checkpoint` event kind.
- Add a deterministic planner with an initial, periodic and final safe marker.
- Materialize markers through an optional `ianvs_pty` replay checkpoint capability.
- Capture and restore native terminal-visible replay state with session-local ids.
- Bound native retention to 64 checkpoints and 32 MiB per replay session.
- Reject capture in the middle of an incomplete VT control sequence.
- Preserve Runtime Event sequence monotonicity across restore.

## Non-goals

- Do not add seek, pause, Replay UI or playback controls.
- Do not serialize `TerminalSnapshot` or native heap state into the recording.
- Do not add graphic asset bundles or promise cross-process instant restore.
- Do not change live native capture from current recording schema.
- Do not remove legacy replay delegates or make checkpoint FFI symbols mandatory.
- Do not roll back Runtime Event queues or sequence numbers.

## Files In Scope

- `packages/ianvs_terminal/lib/src/recording/terminal_recording.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- `packages/ianvs_terminal/test/terminal_recording_checkpoint_test.dart`
- `packages/ianvs_terminal/test/terminal_recording_codec_test.dart`
- `packages/ianvs_terminal/test/terminal_replay_backend_test.dart`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `native/core/src/runtime_contract.rs`
- `native/core/tests/session_test.rs`
- `docs/recording/FORMAT_CURRENT.md`

## Contract

- Metadata, checkpoint markers and every event use the single current recording
  schema consistently.
- Checkpoint ids are non-empty, bounded and deterministic; source sequence points
  to a prior non-checkpoint event.
- Replanning an already planned recording produces canonical byte-identical NDJSON.
- The planner waits for a safe VT parser boundary, and native capture checks that
  boundary independently.
- Replay delegates without the optional capability ignore markers without losing
  output or breaking session lifecycle.
- Native checkpoint ids are opaque and session-scoped; oldest entries are evicted
  when count or estimated-byte capacity is reached.
- Restore forces a full Snapshot but leaves Runtime Event sequence monotonic.

## Functional Acceptance

- Current fixtures remain canonical and checkpoint fixtures round-trip.
- Invalid versions, cross-version events, malformed markers and unsafe boundaries
  fail explicitly.
- Initial, periodic and final markers are deterministic and bounded.
- Split OSC input does not create a checkpoint until the terminating byte arrives.
- ReplayBackend exposes materialized checkpoints when supported and remains
  compatible with legacy delegates.
- A real Dart/native bridge captures a checkpoint, mutates terminal state, restores
  it and observes the pre-mutation Frame.
- Native capacity eviction and cross-session id rejection are covered.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo test --manifest-path native/core/Cargo.toml --test session_test replay_checkpoint -- --nocapture
cargo test --manifest-path native/core/Cargo.toml --test runtime_capabilities_test
cargo build --manifest-path native/core/Cargo.toml

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_recording_checkpoint_test.dart \
  test/terminal_recording_codec_test.dart \
  test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

T-327 is closed.

- The current recording schema remains byte-stable; the explicit planner
  produces canonical current-schema markers and repeated planning is
  byte-identical.
- Dart and native boundary trackers prevent capture in an incomplete VT control
  string. Split-OSC regression coverage verifies the marker is delayed until BEL.
- Native replay retains at most 64 session-local checkpoints under a 32 MiB
  estimated budget, evicts oldest entries and forces a Snapshot after restore.
- Optional FFI and ReplayBackend capabilities preserve old delegates. The real
  Dart/native bridge captures, mutates and restores terminal state successfully.
- Strict Rust/Dart/Flutter analyses, focused tests, documentation contracts and the
  final `make verify` all pass.
- Final gate evidence: 1,733 vendored Rust tests pass with one ignored, 131
  native-core tests, 518 session integration tests, 3 `vttest` regressions, 57
  `ianvs_pty` tests, 537 `ianvs_terminal` tests with one intentional skip, 1,100
  example tests, 4 macOS smoke tests, 46 real-PTY tests and 17 XCTest cases all pass.
- All six benchmark correctness hashes report `hash_match=true` in
  `build/bench-results-ci/20260721T111849Z`; the native result bundle is
  `Test-Runner-2026.07.21_19-21-18-+0800.xcresult`.
- The first full gate attempt encountered one non-reproducible existing
  `background masked-hint` FIFO timeout. Its focused rerun passed, and the complete
  second gate passed the same case at 301 ms under its 750 ms hard ceiling.

## Risks / Follow-ups

- Materialized snapshots are process-local. A fresh process must replay the prefix
  before restoring a persisted marker.
- Future seek must define replay cursor and Frame delivery semantics without
  rewinding Runtime Event sequences.
- Checkpoints restore terminal-visible state but do not create a portable graphic
  asset bundle; graphics persistence remains separate.

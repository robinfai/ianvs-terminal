# T-326 Replay Frame Hash Comparison

## Goal

Compare reference and replayed Frame sequences at each applied viewport state, with a bounded and
actionable first-divergence result for deterministic replay tests and bug reproduction.

## Scope

- Add a public `TerminalReplayFrameHashComparator` beside the Recording / Replay APIs.
- Apply Snapshot/Delta sequences through `TerminalViewportState` before hashing.
- Reuse the existing deterministic viewport hash for visible row text, wrapping and geometry.
- Report the first hash or frame-count divergence with both trace sizes and available hashes.
- Bound each input trace to 4,096 Frames and require a Snapshot when a trace is non-empty.
- Allow a custom applied-Frame hasher for stricter test-specific projections.

## Non-goals

- Do not change Recording v1 or persist hashes inside recording files.
- Do not call this a cryptographic integrity or authenticity check.
- Do not include graphic asset bytes, full style semantics or Host effects in the default hash.
- Do not add checkpoint/seek, Replay UI or runtime collection lifecycle.
- Do not compare raw JSON/Protobuf bytes or require identical Snapshot/Delta partitioning.

## Files In Scope

- `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_frame_hash_comparator.dart`
- `packages/ianvs_terminal/test/terminal_replay_frame_hash_comparator_test.dart`
- `docs/tasks/runtime-pty/T-326-replay-frame-hash-comparison.md`
- `docs/tasks/README.md`
- `docs/ROADMAP.md`
- `docs/CURRENT_EXECUTION_TARGET.md`
- `docs/CURRENT_EXECUTION_TARGETS.json`

## Comparison Contract

- Empty traces are valid and equal only to another empty trace.
- Every non-empty trace begins with a Snapshot; invalid traces fail before comparison.
- The comparator applies each Frame to its own viewport state and hashes the applied state.
- Snapshot and Delta partitions may differ when they produce the same applied viewport at the same
  trace index.
- A content divergence reports the zero-based index and both hashes.
- A length divergence reports the first missing index and the available side's applied hash.
- The 4,096-Frame cap matches the live Recording capture event bound and prevents unbounded
  diagnostic comparison.

## Functional Acceptance

- Equal Snapshot/Delta sequences match.
- Equivalent applied states match even when one trace uses a Delta and the other a Snapshot.
- Changed visible content reports the first differing index and both hashes.
- A missing or extra Frame reports a frame-count divergence at the first missing index.
- Delta-first and over-limit traces throw `ArgumentError`.
- Existing benchmark hashing remains byte-for-byte unchanged.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_replay_frame_hash_comparator_test.dart \
  test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

T-326 is closed.

- Six focused comparator regressions pass, including equal applied state, different
  Snapshot/Delta partitioning, first hash mismatch, custom stricter projection, frame-count
  mismatch and invalid/over-limit traces.
- `TerminalReplayFrameHashComparator` is public, immutable and bounded to 4,096 Frames per
  trace. It compares hashes only after applying each Frame through `TerminalViewportState`.
- The default projection reuses the existing deterministic benchmark viewport hash; callers can
  inject a stricter applied-Frame hasher without changing Recording v1.
- `flutter analyze --fatal-infos`, the focused Replay regressions, docs contract and final
  `make verify` all pass.
- Final gate evidence: 1,733 vendored Rust tests pass with one ignored, 131 native-core tests,
  515 session integration tests, 3 `vttest` regressions, 56 `ianvs_pty` tests, 529
  `ianvs_terminal` tests with one intentional skip, 1,100 example tests, 4 macOS smoke tests,
  46 real-PTY tests and 17 XCTest cases all pass.
- All six benchmark correctness hashes remain equal in
  `build/bench-results-ci/20260721T104233Z`; the native result bundle is
  `Test-Runner-2026.07.21_18-45-09-+0800.xcresult`.

## Risks / Follow-ups

- The default viewport hash intentionally excludes style and graphics. A richer semantic hash
  needs its own versioned projection before it can become persisted evidence.
- Comparison identifies the first divergent applied Frame but does not make replay seekable.
- Hashes prove deterministic equality for this projection, not file integrity or trust.

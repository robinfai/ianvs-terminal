# T-325 Replay Speed Control

## Goal

Add deterministic, bounded speed control to realtime current recording schema playback without changing the
recording wire format, native replay path or synchronous no-delay mode.

## Scope

- Add an immutable public playback speed to `TerminalReplayBackend`.
- Accept finite speeds from 0.25x through 4x, inclusive, with 1x as the default.
- Scale realtime playback against the absolute recording timeline.
- Preserve event order, same-offset grouping, session cancellation and read-only replay behavior.
- Keep no-delay playback synchronous and independent of the selected valid speed.

## Non-goals

- Do not add pause/resume, seek, checkpoint generation or a mutable replay clock.
- Do not add Replay UI, persistence of playback preferences or keyboard actions.
- Do not change current recording schema events, Frame payloads, native FFI or Runtime capabilities.
- Do not add graphics asset bundles or historical Host effect replay.
- Do not widen the 0.25x–4x bound without a separate compatibility decision.

## Files In Scope

- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- `packages/ianvs_terminal/test/terminal_replay_backend_test.dart`
- `docs/tasks/runtime-pty/T-325-replay-speed-control.md`
- `docs/tasks/README.md`
- `docs/ROADMAP.md`
- `docs/CURRENT_EXECUTION_TARGET.md`
- `docs/CURRENT_EXECUTION_TARGETS.json`

## Timing Contract

- `playbackSpeed` defaults to `1` and is fixed for the lifetime of a backend.
- Realtime wall offset is `round(recordingOffset.inMicroseconds / playbackSpeed)`.
- Each timer delay is the difference between two scaled absolute offsets. Scaling absolute offsets
  avoids accumulating per-segment rounding error.
- A scaled delay may be zero; events still retain current recording schema sequence order.
- No-delay mode validates the configured speed but never creates a timer.

## Functional Acceptance

- Existing callers that omit speed retain the exact 1x realtime schedule.
- 2x replay halves the fixture's 10 ms intervals to 5 ms.
- Absolute microsecond offsets scale without cumulative segment-rounding drift.
- NaN, infinities, values below 0.25 and values above 4 fail at construction with
  `ArgumentError`.
- No-delay playback remains synchronous at any valid speed.
- Existing event delivery, Frame delegation, capability forwarding and cancellation tests remain
  green.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd packages/ianvs_terminal
dart format --output=none --set-exit-if-changed \
  lib/src/recording/terminal_replay_backend.dart \
  test/terminal_replay_backend_test.dart
flutter analyze --fatal-infos
flutter test test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

T-325 is closed.

- `TerminalReplayBackend` now exposes an immutable `playbackSpeed` with an inclusive 0.25x–4x
  contract and unchanged 1x default behavior.
- Realtime timers use differences between scaled absolute recording offsets, so fractional
  microsecond rounding does not accumulate across event segments.
- Same-offset order, cancellation and all delegated runtime capabilities remain unchanged.
  No-delay mode still completes synchronously and creates no timers.
- Four focused tests cover 2x scheduling, absolute-offset rounding, finite bounds and no-delay
  behavior at a non-default speed; the complete replay file passes 12 tests.

Verification on 2026-07-21:

- Strict `flutter analyze --fatal-infos`, the focused replay suite and all 12 documentation
  contract tests passed.
- The complete `make verify` returned zero: 1,733 vendored Rust tests passed with one ignored,
  native core passed 131 unit tests, 515 session tests and 3 `vttest` regressions,
  `ianvs_pty` passed 56 tests, and the selected example suite passed 1,100 tests.
- macOS passed 4 smoke tests, 46 real PTY tests and all 17 XCTest cases. The maximum-backoff
  baseline was approximately 437 ms, below its 750 ms ceiling.
- All six correctness hashes are true in
  `build/bench-results-ci/20260721T102918Z`; the XCTest result is
  `Test-Runner-2026.07.21_18-31-57-+0800.xcresult`.

## Risks / Follow-ups

- A backend's speed is intentionally immutable. Runtime speed changes need a clock that can
  rebase pending timers without duplicate delivery.
- Seek still requires checkpoints or deterministic replay from the beginning; speed control does
  not create random access.
- Replay UI and saved speed preferences remain product work outside this backend-only slice.

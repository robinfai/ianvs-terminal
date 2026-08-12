# T-310 Live Recording Seam

## Goal

Connect the current Recording format to the real native session boundary with bounded, ordered capture of
raw PTY output, user input, resize and child exit events.

## Scope

- Add a private native recording buffer beside `TerminalSession`.
- Capture PTY bytes at the reader before terminal parsing or Frame construction.
- Capture successful user writes, resize operations and observed child exits under one ordered
  recording lock.
- Bound one recording to 4,096 events and 8 MiB of raw payload.
- Return a structured capacity error instead of dropping events or exporting a partial stream.
- Expose explicit `terminal.recording_start`, `terminal.recording_stop` and
  `terminal.recording_cancel` session requests.
- Add a public Dart `TerminalLiveRecorder` that returns a validated `TerminalRecording`.
- Keep `record` versus `redact` input handling at the native ingress boundary.

## Non-goals

- Do not route raw PTY bytes through render Frames or the product event queue.
- Do not add file persistence, background streaming, upload/export UI or automatic session-start
  recording.
- Do not implement ReplayBackend, playback scheduling, speed control or checkpoint/seek.
- Do not record Host Request/Response, graphics assets or viewport `InstantReplayStore` frames.
- Do not silently evict old recording events when capacity is reached.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/session/recording.rs`
- `native/core/tests/session_test.rs`
- `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_live_recorder.dart`
- `packages/ianvs_terminal/test/terminal_live_recorder_test.dart`
- `docs/recording/FORMAT_CURRENT.md`
- `docs/tasks/runtime-pty/T-310-live-recording-seam.md`

## Functional Acceptance

- A real PTY session records exact pre-parser output bytes.
- Successful input and resize calls share a contiguous sequence with PTY output.
- `redact` stores only input byte length; `record` stores exact input bytes.
- An observed child exit produces `session_exited`, including its exit code.
- Repeated start, inactive stop/cancel and capacity overflow return structured errors.
- Stopping a valid recording produces current NDJSON accepted by `TerminalRecordingCodec`.
- Capacity overflow never returns a plausible partial recording.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml session::recording::tests --lib
cargo test --manifest-path native/core/Cargo.toml --test session_test \
  live_recording_captures_raw_pty_output_redacted_input_and_resize -- --exact

cd packages/ianvs_terminal
flutter analyze
flutter test test/terminal_live_recorder_test.dart test/terminal_recording_codec_test.dart
flutter test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

- Added the private `SessionRecording` buffer with fixed event/payload limits and all-or-error
  overflow behavior.
- Raw bytes are copied at the native PTY reader before parsing; write, resize and exit capture use
  the same recording lock, so sequence and monotonic offsets remain deterministic.
- Added explicit start/stop/cancel session requests without adding PTY output to product events or
  changing Frame JSON/Protobuf.
- Added public `TerminalLiveRecorder`, capacity metadata and structured backend errors.
- Two native buffer tests, one real PTY integration regression and ten combined Dart live
  recorder/codec tests pass. Native Clippy and package analysis report no issues.
- The complete `ianvs_terminal` suite passes 495 tests with 1 intentional skip.
- The final `make verify` passed: vendored Rust 1,733 tests with 1 ignored, native core 118 unit +
  513 session + 3 `vttest` regressions, `ianvs_pty` 22 tests, documentation 12 tests, example
  1,063 tests, macOS smoke 4 tests, real PTY 46 tests and Runner XCTest 16 tests.
- The verification benchmark was written to `build/bench-results-ci/20260721T032057Z`; all six
  correctness hashes are byte-identical to the T-309 baseline.
- T-310 is closed. ReplayBackend is the next Iteration 03 slice.

## Risks / Follow-ups

- This slice intentionally keeps one recording in bounded memory. Long-running sessions need a
  separately designed streaming persistence sink rather than a larger unbounded buffer.
- PTY output can echo user input and remains sensitive even when the explicit input policy is
  `redact`.
- ReplayBackend remains the next Iteration 03 slice and must consume the validated event model,
  not native implementation details.

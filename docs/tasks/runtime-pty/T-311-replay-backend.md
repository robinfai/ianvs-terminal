# T-311 ReplayBackend

## Goal

Close the Recording / Replay MVP with a deterministic, read-only ReplayBackend that uses the
production native parser and Frame pipeline without starting a child process.

## Scope

- Add a headless native replay session beside live `TerminalSession` creation.
- Feed recorded raw PTY output through the same parser, damage and Frame construction path used by
  live sessions.
- Add optional replay-session FFI and `ianvs_pty` backend capabilities.
- Implement `TerminalReplayBackend` as the existing `PtySessionBackend` abstraction.
- Support realtime scheduling and synchronous no-delay playback.
- Apply the recorded initial geometry and subsequent Resize events in stable sequence order.
- Ignore historical UserInput and reject new writes or view-driven resize mutations.
- Suppress historical host-facing effects such as clipboard, OpenURL and terminal responses.
- Prove repeated playback stability with a fixed validated current recording schema stream.

## Non-goals

- Do not add checkpoint/seek, pause, speed controls, replay editing or product UI.
- Do not record or replay graphics asset bundles or full Host Request/Response traffic.
- Do not execute historical user input, clipboard operations, URLs, downloads or child processes.
- Do not change the current recording schema wire format or Frame JSON/Protobuf schema.
- Do not broaden Workspace, remote, plugin, renderer or cross-platform scope.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `native/core/tests/session_test.rs`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- `packages/ianvs_terminal/test/terminal_replay_backend_test.dart`
- `docs/tasks/runtime-pty/T-311-replay-backend.md`

## Functional Acceptance

- `TerminalReplayBackend` implements `PtySessionBackend` and delegates Frame, event and viewport
  access through a native replay session.
- Realtime mode honors monotonic offsets; no-delay mode completes synchronously for deterministic
  tests.
- Same-offset events retain recording sequence order and repeated playback produces byte-stable
  Frames.
- SessionStarted geometry is applied before PTY output and recorded Resize events drive later
  geometry.
- UserInput is never sent to native code, replay writes are rejected, and live view resizes do not
  mutate recorded geometry.
- Replay creation does not start the configured child process.
- Historical host effects and terminal responses are drained but not delivered or written.
- Existing structured current recording schema corruption and version errors remain the replay input gate.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test session_test \
  replay_session_is_headless_read_only_and_suppresses_host_effects -- --exact
cargo test --manifest-path native/core/Cargo.toml --test session_test \
  repeated_replay_produces_byte_stable_frames -- --exact

cd packages/ianvs_pty
dart analyze
dart test

cd ../ianvs_terminal
flutter analyze
flutter test test/terminal_replay_backend_test.dart
flutter test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

- Added headless replay sessions with no PTY child, writer, master or resource sampler.
- Extracted shared PTY-byte ingestion so live and replay sessions use the same parser, transcript,
  damage and Frame pipeline; replay drains host callbacks/responses without executing them.
- Added optional FFI/binding methods for replay create, output and exit, with a real Rust dynamic
  library bridge test.
- Added public `TerminalReplayBackend` with realtime and no-delay scheduling, stable same-offset
  order, initial/recorded geometry and read-only input behavior.
- Four Dart replay contract tests, two native headless/stability regressions and the complete
  `ianvs_pty` test suite pass. Both Dart packages analyze cleanly and native Clippy passes.
- The final `make verify` passed: vendored Rust 1,733 tests with 1 ignored, native core 118 unit +
  515 session + 3 `vttest` regressions, `ianvs_pty` 24 tests, `ianvs_terminal` 499 tests with 1
  intentional skip, documentation 12 tests, example 1,063 tests, macOS smoke 4 tests, real PTY 46
  tests and Runner XCTest 16 tests.
- The verification benchmark was written to `build/bench-results-ci/20260721T035353Z`; all six
  correctness rows are byte-identical to the T-310 baseline through the deterministic metric
  columns, and every snapshot/delta hash comparison is `true`.
- T-311 and Recording / Replay MVP Iteration 03 are closed. Local Workspace stability is the next
  active lane.

## Risks / Follow-ups

- current recording schema intentionally excludes graphics asset bundles and full Host Request/Response
  traffic, so external-resource fidelity remains deferred.
- Realtime playback currently preserves original timing at 1x only; pause, speed control and seek
  require a separately designed clock/checkpoint contract.
- PTY output may contain secrets even when explicit UserInput was redacted; replay files retain the
  privacy boundary documented in `docs/recording/FORMAT_CURRENT.md`.

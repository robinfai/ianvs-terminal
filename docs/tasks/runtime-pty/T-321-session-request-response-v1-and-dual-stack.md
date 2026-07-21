# T-321 Session Request/Response V1 And Dual Stack

## Goal

Replace the primary Dart/native generic session command channel with a correlated, versioned
Session Request/Response v1 contract while preserving the existing JSON request symbol as an
explicit compatibility path.

## Scope

- Define bounded request and response envelopes with schema/contract identity, request id,
  session id, operation and payload.
- Return structured protocol errors for malformed, unsupported and runtime-failed requests.
- Add an optional `ianvs_session_request_v1_json` FFI entrypoint and advertise a distinct
  `session-request-envelope.json.v1` capability.
- Add typed Dart envelope producers/decoders with additive-field tolerance and correlation checks.
- Add optional binding/backend interfaces and symbol probing without making v1 mandatory.
- Route `TerminalJsonRequestClient`, `TerminalDiagnosticsClient` and `TerminalLiveRecorder`
  through one v1-preferred compatibility transport.
- Make `TerminalReplayBackend` preserve the same v1 request capability when its delegate supports
  it.
- Retain the exact legacy request shape and `ianvs_session_request_json` for both upgrade
  directions.

## Non-goals

- Do not reclassify native-to-product clipboard, URL, notification or other host-effect events as
  Session Requests; Host Request/Response is a later contract.
- Do not migrate dedicated search/selection symbols, Frame, Event, Recording format, diagnostics
  payload schemas or asset byte transports.
- Do not remove or rename `ianvs_session_request_json`.
- Do not change operation-specific payload or response semantics.
- Do not add async multiplexing, remote backends, checkpoints or UI.

## Files In Scope

- `native/core/src/session_request.rs`
- `native/core/src/ffi.rs`
- `native/core/src/lib.rs`
- `native/core/src/runtime_contract.rs`
- `native/core/tests/runtime_session_request_test.rs`
- `packages/ianvs_pty/lib/ianvs_pty.dart`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/lib/src/pty_session_request_v1.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `packages/ianvs_pty/test/session_request_v1_test.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_session_request_transport.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_json_request_client.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_diagnostics.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_live_recorder.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- focused tests for those call sites
- protocol, inventory, roadmap and execution-target documentation

## Functional Acceptance

- Request v1 has a 1 MiB encoded ceiling; response v1 has a 16 MiB ceiling to retain bounded
  Recording stop responses.
- Every successful response exactly echoes request id, session id and operation.
- Dart rejects unsupported schemas, wrong contracts, malformed envelopes and correlation drift
  with structured errors while ignoring additive unknown v1 fields.
- Native returns a bounded structured error for invalid schema/contract, identity mismatch,
  unsupported operation and runtime failure.
- All generic terminal request clients prefer v1 when supported and preserve their existing
  operation-specific return semantics.
- New Dart with an old native library emits the exact legacy `{kind, ...payload}` object.
- Old Dart with a new native library continues through `ianvs_session_request_json`.
- Live and replay real-native integration covers v1 plus legacy compatibility.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test runtime_session_request_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/session_request_v1_test.dart test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_json_request_client_test.dart \
  test/terminal_diagnostics_test.dart test/terminal_live_recorder_test.dart \
  test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

Session Request/Response v1 is implemented and T-321 is closed.

- Rust now validates bounded Session Request v1 envelopes and returns bounded Session Response v1
  for success, malformed schema/contract/identity, unsupported operation and runtime failure.
- `ianvs_session_request_v1_json` is optional on Dart and is advertised separately as
  `session-request-envelope.json.v1`; the older feature id and FFI symbol remain intact.
- Dart request/response models enforce exact correlation, structured failures, additive-field
  tolerance, a 1 MiB request limit and a 16 MiB response limit.
- `TerminalJsonRequestClient`, `TerminalDiagnosticsClient` and `TerminalLiveRecorder` share one
  v1-preferred compatibility transport. `TerminalReplayBackend` exposes v1 only when its delegate
  supports it.
- New-Dart/old-native emits the exact legacy `{kind, ...payload}` object, and old-Dart/new-native
  continues through `ianvs_session_request_json`.
- Strict Clippy and both Dart package analyses pass. The Rust unit/FFI regressions pass, the PTY
  contract/backend slice passes 37 tests, the terminal client/replay slice passes 22 tests and the
  documentation contracts pass 12 tests.
- The final `make verify` entrypoint returns zero: 1,733 vendored Rust tests, 127 native unit tests,
  515 native session tests, 3 native vttest regressions, 48 `ianvs_pty` tests, 509
  `ianvs_terminal` tests with 1 intentional skip, 12 documentation contracts, 1,100 selected
  example tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner XCTest cases pass.
- All six deterministic benchmark rows retain `hash_match=true` in
  `build/bench-results-ci/20260721T082801Z`.
- An initial full-gate attempt lost the Flutter integration runner handshake before the first real
  PTY assertion. A process sample showed an idle app/event loop rather than executing product code;
  the process group was cleaned up, the real PTY gate passed 46/46 in isolation, and the subsequent
  complete `make verify` run passed without reproducing the infrastructure stall.

## Risks / Follow-ups

- The 16 MiB response ceiling is intentionally larger than ordinary command responses because a
  bounded Recording v1 document is currently returned through this channel.
- Dedicated Host Request/Response, diagnostic payload and asset transfer migrations remain
  separate tasks.

# T-320 SessionConfig V1 And Profile Wire Migration

## Goal

Replace the primary Dart/native session-create payload with a versioned, product-neutral
SessionConfig v1 while preserving explicit compatibility in both upgrade directions.

## Scope

- Define bounded SessionConfig v1 with schema version, contract id, session identity, display name
  and the existing neutral launch/terminal/shell-integration/appearance/interaction config.
- Add a typed Dart producer/decoder with structured contract errors and additive-field tolerance.
- Add native typed decoding that maps SessionConfig v1 to internal `TerminalProfile` only after
  contract validation.
- Add optional live and replay SessionConfig v1 FFI entrypoints and advertise the feature through
  Runtime Capabilities v1.
- Make `TerminalRuntimeController` prefer v1 only when its backend declares support.
- Keep new Dart usable with old native libraries by falling back to the legacy Profile-shaped
  payload, and keep old Dart usable with new native libraries through the existing FFI symbols.
- Move the legacy Profile-shaped encoder behind an explicitly named compatibility path.
- Cover live/replay routing, unknown fields, malformed contracts and both fallback directions.

## Non-goals

- Do not change Frame, Event, Recording, request, diagnostic or asset payloads.
- Do not remove the existing live/replay FFI symbols during the compatibility window.
- Do not change application Profile persistence or make native core depend on app Profile fields.
- Do not add remote, SSH, plugin, process recovery, checkpoint/seek or platform claims.
- Do not redesign terminal configuration defaults or UI.

## Files In Scope

- `native/core/src/session_config.rs`
- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `native/core/src/lib.rs`
- `native/core/src/runtime_contract.rs`
- `native/core/tests/runtime_session_config_test.rs`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- `packages/ianvs_terminal/lib/src/config/terminal_session_config_v1.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- `packages/ianvs_terminal/test/terminal_session_config_v1_test.dart`
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `packages/ianvs_terminal/test/terminal_replay_backend_test.dart`
- `docs/ARCHITECTURE.md`
- `docs/protocols/RUNTIME_CAPABILITIES_V1.md`
- `docs/protocols/SESSION_CONFIG_V1.md`
- `docs/tasks/runtime-pty/T-320-session-config-v1-and-profile-wire-migration.md`

## Functional Acceptance

- SessionConfig v1 has an exact schema/contract identity and a 1 MiB encoded ceiling.
- Dart emits no app Profile fields and ignores additive unknown v1 fields when decoding.
- Native rejects unsupported schema/contract and malformed required identity/config fields.
- New live and replay FFI entrypoints create sessions from the typed contract.
- A v1-capable backend receives v1 and never receives the Profile-shaped fallback.
- A backend or native library without v1 support continues receiving the exact legacy payload.
- The existing legacy live/replay FFI entrypoints remain covered against the new native library.
- Real native/Dart integration proves that live product startup uses the v1 path.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test runtime_session_config_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_session_config_v1_test.dart \
  test/terminal_runtime_controller_test.dart test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

SessionConfig v1 is implemented and T-320 is closed.

- Dart now owns a typed, bounded `TerminalSessionConfigV1` producer/decoder with structured
  contract errors, additive-field tolerance and a 1 MiB encoded ceiling.
- Rust validates the same contract before mapping it to the internal `TerminalProfile`; app
  Profile aliases are not part of the new contract.
- `ianvs_session_create_v1` and `ianvs_replay_session_create_v1` cover live and replay creation,
  and Runtime Capabilities advertises `session-config.json.v1`.
- `TerminalRuntimeController` and `TerminalReplayBackend` prefer v1 only when the loaded backend
  exposes it. New Dart falls back to the exact legacy Profile-shaped payload for old native
  libraries, while the old live/replay FFI symbols remain tested against the new native core.
- The real Dart/native bridge creates both a live `/bin/sh` session and a replay session through
  v1; focused routing tests prove the primary product controller does not call the legacy encoder
  when v1 is available.
- Strict native clippy and both Dart package analyses pass. Focused Rust FFI, PTY backend,
  SessionConfig/controller and replay tests pass.
- The complete `make verify` gate passes: 1,733 vendored Rust tests, 123 native unit tests,
  515 native session tests, 3 native vttest regressions, 42 `ianvs_pty` tests, 505
  `ianvs_terminal` tests with 1 intentional skip, 12 documentation contracts, 1,100 selected
  example tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner XCTest cases.
- All six deterministic benchmark rows retain `hash_match=true` in
  `build/bench-results-ci/20260721T073713Z`.

## Risks / Follow-ups

- The legacy FFI symbols remain a compatibility surface until a separately approved removal
  window; they must not regain ownership of the primary product path.
- Later Command/HostRequest contracts should reuse the Runtime Envelope taxonomy without coupling
  this configuration payload to event sequencing.

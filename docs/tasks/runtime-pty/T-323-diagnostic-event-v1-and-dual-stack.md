# T-323 Diagnostic Event V1 And Dual Stack

## Goal

Version the existing native Frame/Session diagnostic snapshot boundary with correlated
Diagnostic Event v1 envelopes while preserving both legacy diagnostic FFI symbols and the
separate privacy-preserving diagnostics export package.

## Scope

- Define Diagnostic Event v1 as the `message_class: "diagnostic"` specialization of Runtime
  Envelope v1.
- Add session id, per-session sequence, timestamp, diagnostic name and object payload.
- Add optional `ianvs_session_take_diagnostic_event_v1_json` and advertise
  `diagnostic-event.json.v1`.
- Cover `frame_stats` and `session_stats` without changing their legacy payload fields or take
  semantics.
- Add bounded, typed Dart decoding with additive-field tolerance and correlation validation.
- Prefer v1 in `TerminalRuntimeController`, the benchmark trace capture and ReplayBackend
  delegation; fall back to legacy symbols when v1 is unavailable.
- Keep diagnostic failures observational so malformed or unavailable metrics cannot interrupt a
  Frame refresh.

## Non-goals

- Do not change or remove `ianvs_session_take_frame_debug_stats_json` or
  `ianvs_session_take_session_debug_stats_json`.
- Do not change `terminal-diagnostics-session-v1` or `terminal.export_diagnostics`.
- Do not expose the internal sanitized diagnostic-history queue as a live stream.
- Do not migrate Frame, graphics/file assets, other Host operations, remote transport or UI.
- Do not authorize old-wire removal.

## Contract Boundary

- The envelope contract remains `ianvs-runtime-envelope-v1`; Diagnostic Event v1 fixes
  `message_class` to `diagnostic`.
- `message_name` is `frame_stats` or `session_stats` and is correlated to the requested name.
- `session_id` is the native positive decimal u64 string; `sequence` is per session and advances
  only for a materialized diagnostic.
- `payload` must be an object. The complete encoded Dart input is bounded to 1 MiB.
- Unknown additive fields are ignored. Wrong schema, contract, class, session, name, sequence or
  payload type is rejected.

## Functional Acceptance

- New Dart/new native returns typed Frame and Session diagnostic envelopes with identity,
  sequence and timestamp.
- A second Session diagnostic has the next sequence; a consumed Frame diagnostic returns null
  until another Frame is produced.
- New Dart/old native still reads legacy Frame/Session diagnostic JSON.
- old Dart/new native still reads the unchanged legacy symbols.
- Runtime and benchmark consumers prefer v1; ReplayBackend preserves the optional capability.
- Diagnostics export remains independently versioned and unchanged.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml \
  --test runtime_capabilities_test --test runtime_diagnostic_event_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/diagnostic_event_v1_test.dart test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_runtime_controller_test.dart \
  test/terminal_replay_backend_test.dart

cd ../..
flutter analyze --fatal-infos example
dart test test/docs_contract_test.dart
make verify
```

## Result

Diagnostic Event v1 for Frame/Session metrics is implemented and T-323 is closed.

- Native publishes `frame_stats` and `session_stats` as correlated Runtime Envelope v1
  diagnostics with positive session identity, per-session sequence and timestamp. Frame metrics
  preserve their one-shot take semantics.
- `ianvs_session_take_diagnostic_event_v1_json` is optional on Dart and advertised separately as
  `diagnostic-event.json.v1`; both legacy debug-stat symbols remain unchanged.
- Dart validates the bounded envelope and exact session/name correlation. Runtime and benchmark
  consumers prefer v1, ReplayBackend preserves the optional capability, and new Dart falls back
  to legacy JSON with an older native library.
- Focused Rust coverage passes 3 tests across Runtime Capabilities and Diagnostic Event v1;
  `ianvs_pty` passes 55 tests and `ianvs_terminal` passes 513 tests with 1 intentional skip.
- Strict Clippy and all Dart/Flutter analyses pass. The final `make verify` returns zero: 1,733
  vendored Rust tests pass with 1 ignored; native core passes 131 unit tests, 2 Diagnostic Event
  integration tests, 515 session tests and 3 vttest regressions.
- Documentation contracts pass 12 tests; the selected example suite passes 1,100 tests, macOS
  smoke passes 4, real PTY passes 46 and all 17 Runner XCTest cases pass. The final XCTest bundle
  is `Test-Runner-2026.07.21_17-46-54-+0800.xcresult`.
- All six deterministic benchmark rows retain `hash_match=true` in
  `build/bench-results-ci/20260721T094417Z`.

## Risks / Follow-ups

- Diagnostic sequence is intentionally separate from Runtime Event sequence; each stream is
  independently ordered and must not be compared numerically.
- A malformed v1 Frame diagnostic may already have consumed the one-shot native snapshot; the
  runtime drops the observational metric instead of risking a refresh failure.
- The internal diagnostic history and the export evidence package remain separate future
  migration decisions.

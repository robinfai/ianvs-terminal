# T-319 Runtime Event Envelope V1 And Dual Stack

## Goal

Introduce a versioned Runtime Event Envelope with session identity, sequence and timestamp, then
migrate native event polling to it while retaining the legacy event-array fallback.

## Scope

- Inventory every current FFI symbol and classify its payload as control, command/config, event,
  frame, diagnostic, asset transfer or ownership.
- Define a reusable Runtime Envelope v1 taxonomy and a bounded Runtime Event Batch v1.
- Assign every queued native event a per-session sequence and timestamp before queue eviction.
- Expose an optional `ianvs_session_poll_event_envelopes_json` FFI function.
- Add a typed Dart envelope/batch decoder with structured contract errors.
- Prefer Event Envelope v1 in `NativePtyBackend` when the optional symbol is present.
- Fall back to `ianvs_session_poll_events_json` for older native libraries.
- Detect sequence gaps, reordered messages and cross-session messages instead of silently accepting
  them.

## Non-goals

- Do not change Frame JSON/Protobuf or move Frames into JSON envelopes.
- Do not migrate SessionConfig or remove the legacy native Profile wire in this task.
- Do not migrate generic session requests, diagnostics or asset bytes.
- Do not change event names or product event routing semantics.
- Do not add HostRequest/HostResponse recording, UI, remote backends or platform claims.

## Files In Scope

- `native/core/src/runtime_contract.rs`
- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `native/core/tests/runtime_event_envelope_test.rs`
- `packages/ianvs_pty/lib/ianvs_pty.dart`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/lib/src/pty_runtime_envelope.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `packages/ianvs_pty/test/runtime_envelope_test.dart`
- `docs/protocols/RUNTIME_WIRE_INVENTORY.md`
- `docs/protocols/RUNTIME_EVENT_ENVELOPE_V1.md`
- `docs/protocols/RUNTIME_CAPABILITIES_V1.md`
- `docs/tasks/runtime-pty/T-319-runtime-event-envelope-v1-and-dual-stack.md`

## Functional Acceptance

- Every event receives a monotonic per-session sequence before queue admission/eviction.
- Event Batch v1 exposes its session id, next sequence and dropped count even when all attempted
  events were rejected by bounds.
- Each retained event envelope carries schema, contract, class, name, session id, sequence,
  timestamp and payload.
- Dart ignores additive unknown fields and accepts unknown event names while retaining their
  payload.
- Dart rejects unsupported schemas, wrong classes, invalid identities, malformed ordering and
  cross-session batches with a structured error code.
- A supported v1 binding is preferred and legacy polling is not called.
- An older binding without the optional symbol continues to use the legacy array.
- The real Rust dynamic library crosses the v1 FFI path and preserves started/exit order.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test runtime_event_envelope_test
cargo test --manifest-path native/core/Cargo.toml session::tests::pending_event --lib

cd packages/ianvs_pty
dart analyze
dart test test/runtime_envelope_test.dart test/native_pty_backend_test.dart
dart test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

- Added the closed Runtime Envelope v1 taxonomy and bounded Event Batch v1 with explicit schema,
  contract, class, session identity, next cursor, drop count and per-message sequence/timestamp.
- Native assigns sequence and timestamp before queue admission. Evicted or rejected events advance
  the cursor and produce observable loss metadata, including an empty loss-only batch.
- Added optional `ianvs_session_poll_event_envelopes_json` and advertised
  `event-envelope.json.v1`. The legacy `ianvs_session_poll_events_json` symbol remains unchanged.
- Added the typed Dart envelope/batch decoder with a 9 MiB encoded ceiling, 1,024-message limit,
  additive-field/unknown-event tolerance and stable structured errors for invalid schema, class,
  identity, order and size.
- `NativePtyBackend` prefers Event Envelope v1, detects loss/reordering/cross-session data and maps
  sequence/timestamp/schema onto `PtyEvent`; bindings without the optional capability continue
  through the legacy array path.
- Focused Rust queue/contract/FFI tests and 40 `ianvs_pty` tests pass, including both the legacy
  fallback and the real rebuilt dynamic library.
- The final `make verify` passed vendored Rust 1,733 tests with 1 ignored; native core 121 unit,
  1 OSC corpus, 1 Runtime Capabilities, 1 Runtime Event Envelope, 515 session and 3 `vttest`
  tests; `ianvs_pty` 40 tests; `ianvs_terminal` 499 tests with 1 intentional skip;
  documentation 12 tests; selected example CI 1,100 tests; macOS smoke 4 tests; real PTY 46 tests;
  and Runner XCTest 17 tests.
- Benchmark evidence is in `build/bench-results-ci/20260721T070651Z`; all six correctness rows have
  `hash_match=true`. The fresh XCTest result passed 17/17 at
  `Test-Runner-2026.07.21_15-09-30-+0800.xcresult`.
- T-319 is closed. T-320 should migrate SessionConfig/Profile wire as a separate compatibility
  slice; no Frame, request, diagnostic or asset wire was changed here.

## Risks / Follow-ups

- T-320 must define SessionConfigV1 and migrate/remove the old native Profile wire separately.
- Later command, frame, diagnostic and asset envelope migrations must preserve their existing
  high-throughput or binary transport properties; this task does not imply JSON-wrapping all data.

# T-322 Host Request/Response V1 Clipboard Read

## Goal

Introduce the first bounded native-to-product Host Request/Response v1 slice on top of Runtime
Event Envelope v1, while preserving the existing OSC 52 clipboard-read event and direct PTY reply
as explicit compatibility paths.

## Scope

- Define bounded `HostRequestV1` and `HostResponseV1` JSON contracts with schema/contract
  identity, request id, session id, operation, sequence, timestamp and payload.
- Reclassify only the OSC 52 `clipboard_paste_request` on the v1 event path as a
  `clipboard.read_text` Host Request.
- Keep `ianvs_session_poll_events_json` byte-for-byte compatible with the legacy
  `clipboard_paste_request` event shape.
- Add an optional `ianvs_session_host_response_v1_json` FFI entrypoint and advertise
  `host-request-response.json.v1` separately.
- Retain a bounded native pending-request queue and consume a matching response at most once.
- Add typed Dart request decoding and response encoding with outer Runtime Event correlation
  checks and additive-field tolerance.
- Prefer Host Response v1 when both the event and optional backend capability are present; use
  the current direct PTY response with an old native backend.

## Non-goals

- Do not classify URL opening, attention feedback, notification display, shell metadata, resize,
  cell-size replies or other one-way events as Host Responses.
- Do not migrate OSC 5522 MIME clipboard, OSC 1337 ReportVariable, notification activation,
  file-download asset transfer or file-upload denial in this slice.
- Do not remove either event-poll symbol, the raw input transport or any legacy event kind.
- Do not add full Host Request/Response recording, remote transport, async multiplexing or UI.

## Contract Boundary

- Runtime Event Envelope v1 uses `message_name: "host_request"` and carries a complete
  `ianvs-host-request-v1` object as its payload.
- The initial operation is `clipboard.read_text`; its payload contains the OSC 52 selection.
- A successful Host Response payload contains canonical `data_base64` for at most 4 MiB decoded
  UTF-8 clipboard data. A denied or failed response carries a bounded structured error and no
  payload.
- Request identity is derived from the native event sequence and is correlated against session,
  operation, sequence and timestamp before Dart exposes it.
- Native retains at most 64 pending Host Requests. Responses are validated before consumption;
  duplicate, stale, cross-session and wrong-operation responses are rejected.

## Functional Acceptance

- New Dart/new native completes an authorized OSC 52 clipboard read through Host Response v1.
- Denial consumes the matching request without exposing clipboard bytes or writing a PTY reply.
- New Dart/old native preserves the existing direct `ESC ] 52` reply.
- Old Dart/new native preserves the legacy `clipboard_paste_request` event and direct reply.
- Unknown additive v1 fields are ignored; wrong schema, contract or correlation is rejected.
- Ordinary Runtime Event v1 messages retain their existing message names and payloads.
- Capability and symbol probing remain optional and do not make an older native library fail to
  load.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test runtime_host_request_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/host_request_v1_test.dart test/runtime_envelope_test.dart \
  test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_runtime_controller_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

Host Request/Response v1 for OSC 52 text clipboard reads is implemented and T-322 is closed.

- Native Runtime Event Envelope v1 now maps only `clipboard_paste_request` to a correlated
  `host_request`; ordinary v1 events and the complete legacy event-array shape remain unchanged.
- Native retains at most 64 pending Host Requests, validates response schema/state/identity and
  canonical bounded UTF-8 Base64, then consumes success, denial or error exactly once.
- `ianvs_session_host_response_v1_json` is optional on Dart and is advertised separately as
  `host-request-response.json.v1`.
- Dart validates the inner Host Request against the outer event session, sequence and timestamp.
  The runtime prefers Host Response v1 when supported and preserves the old direct OSC 52 reply
  with an older native library.
- Fake and real-native regressions cover success, structured denial, symbol fallback, old event
  compatibility, pending-request bounds and duplicate rejection. The real PTY/FFI test accepts
  the first response and rejects the second response for the same identity.
- Strict Clippy plus both package analyses pass. The final `make verify` returns zero: 1,733
  vendored Rust tests pass with 1 ignored; native core passes 131 unit tests, 2 Host Request
  integration tests, 515 session tests and 3 vttest regressions; `ianvs_pty` passes 52 tests and
  `ianvs_terminal` passes 511 tests with 1 intentional skip.
- Documentation contracts pass 12 tests; the selected example suite passes 1,100 tests, macOS
  smoke passes 4, real PTY passes 46 and all 17 Runner XCTest cases pass. The final XCTest bundle
  is `Test-Runner-2026.07.21_17-01-21-+0800.xcresult`.
- All six deterministic benchmark rows retain `hash_match=true` in
  `build/bench-results-ci/20260721T085840Z`.

## Risks / Follow-ups

- A bounded pending queue intentionally rejects a response after its oldest identity has been
  evicted; it never applies a late response to a newer request.
- OSC 5522 MIME clipboard, OSC 1337 ReportVariable, notification activation and full Host
  Request/Response recording remain separately scoped migrations.
- URL opening, attention, notification display and file-download assets remain one-way events or
  specialized transports; this task does not imply that every host-facing event needs a response.

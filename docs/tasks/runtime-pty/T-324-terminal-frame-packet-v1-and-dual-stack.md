# T-324 Terminal Frame Packet V1 And Dual Stack

## Goal

Version the high-volume native-to-Dart Frame transport with a compact Protobuf packet that
correlates the existing `terminal-frame-diff-v1` payload to one session, sequence and timestamp,
and can recover from a consumed-but-unapplied packet by requesting a native Snapshot on the next
take.

## Scope

- Add `TerminalFramePacketV1` beside the existing Protobuf Frame message.
- Fix packet schema, contract, message class/name, session id, sequence, timestamp and nested
  Frame schema identity.
- Add optional `ianvs_session_take_frame_packet_v1_protobuf` and advertise
  `frame-packet.protobuf.v1`.
- Let the caller acknowledge its last applied packet sequence. Native forces a Snapshot when the
  acknowledgement is missing or differs from the last emitted packet after a packet has already
  crossed the boundary.
- Add a bounded Dart packet decoder with exact contract/session/schema checks and unknown-field
  compatibility inherited from Protobuf.
- Prefer Frame Packet v1 in automatic transport mode; retain the existing Protobuf and JSON
  paths for old native libraries and explicit JSON mode.
- Preserve the optional capability through ReplayBackend.

## Non-goals

- Do not change any field or field number in `TerminalFrameDiff`.
- Do not JSON- or Base64-wrap Frame payloads.
- Do not move graphic RGBA or file-download bytes into the Frame packet.
- Do not remove `ianvs_session_take_frame_diff_protobuf` or
  `ianvs_session_take_frame_diff_json`.
- Do not add remote transport, checkpoint/seek, renderer or UI behavior.
- Do not authorize old-wire removal.

## Contract Boundary

- Packet `schema_version` is `1`; `contract` is `ianvs-terminal-frame-packet-v1`.
- `message_class` is `frame`; `message_name` is `frame_diff`.
- `session_id` is the positive decimal native u64 string and must equal the requested session.
- `sequence` is a per-session u64 starting at zero and increments only after a materialized packet
  is encoded.
- `timestamp_micros` is a positive Unix timestamp generated when the packet materializes.
- `frame_schema_version` is `terminal-frame-diff-v1` and must equal the nested Frame value.
- The encoded packet is bounded to 64 MiB before Dart decoding. Missing required identity or
  nested Frame data is rejected.
- Unknown Protobuf fields are ignored. Unknown schema, contract, class, name or Frame version is
  rejected before application.

## Resynchronization

- A caller sends no acknowledgement before its first accepted packet.
- Thereafter it sends the sequence of the last packet it successfully decoded and accepted.
- If native has emitted a packet but the acknowledgement is absent or stale, the next take marks
  full repaint before extraction and returns a Snapshot with the next sequence.
- A malformed or mismatched packet is never retried through a legacy take in the same refresh,
  because Frame extraction is one-shot. The unchanged acknowledgement causes native resync on the
  next refresh.
- A Dart adapter also rejects duplicate, reordered or gapped Delta packets. A later forward
  Snapshot can establish a new accepted sequence for non-native adapters.

## Functional Acceptance

- New Dart/new native prefers Frame Packet v1 and applies the same Frame projection as the legacy
  Protobuf payload.
- Packet session, sequence, timestamp and Frame schema cross the real FFI boundary.
- Dropping one packet and acknowledging the prior sequence makes the next native packet a
  Snapshot rather than a dependent Delta.
- New Dart/old native falls back to the existing Protobuf symbol, then JSON when Protobuf is also
  unavailable.
- Old Dart/new native continues using both unchanged legacy Frame symbols.
- Explicit JSON preference does not probe or consume the new packet path.
- ReplayBackend preserves the optional packet capability.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
./tools/gen_frame_diff_proto.sh
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml \
  --test runtime_capabilities_test --test runtime_frame_packet_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test test/native_pty_backend_test.dart

cd ../ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_frame_packet_v1_test.dart \
  test/terminal_replay_backend_test.dart

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

T-324 is closed.

- `TerminalFramePacketV1` now wraps the unchanged Frame Protobuf with exact contract, session,
  sequence, timestamp and Frame schema identity. Native exposes the optional FFI symbol and
  advertises `frame-packet.protobuf.v1`.
- The caller acknowledges only its last accepted sequence. A missing or stale acknowledgement
  after an emitted packet forces the next extraction to a Snapshot; packet sequence advances only
  after successful materialization and encoding.
- Dart bounds and validates the packet before application, rejects cross-session, duplicate,
  reordered and gapped Delta packets, accepts a forward Snapshot for resynchronization and clears
  acknowledgement state when a session closes.
- Automatic transport prefers Packet v1, then the unchanged legacy Protobuf/JSON paths according
  to symbol support. Explicit JSON never probes Packet v1, malformed packets do not consume a
  second legacy Frame, and ReplayBackend preserves the optional capability.
- The generated Rust/Dart Protobuf bindings, Runtime Capabilities, wire inventory, architecture
  boundary and protocol documentation are synchronized. No `TerminalFrameDiff` field, asset
  channel or old symbol was removed.

Verification on 2026-07-21:

- Protobuf generation, Rust formatting, strict Clippy and both focused Rust integration files
  passed; Frame Packet v1 contributes two real-FFI/resynchronization tests.
- Strict Dart/Flutter analysis passed. `ianvs_pty` passed 56 tests and `ianvs_terminal` passed 519
  tests with one intentional existing skip, including the new decoder/coordinator/replay cases.
- `make format-check`, `make analyze`, `make test` and the complete `make verify` returned zero.
- The final gate passed 1,733 vendored Rust tests with one ignored, 131 native unit tests, 515
  session tests, 3 vttest regressions, 1,100 selected example tests, 4 macOS smoke tests, 46 real
  PTY tests and all 17 XCTest cases.
- All six benchmark correctness hashes are true in
  `build/bench-results-ci/20260721T101427Z`; the XCTest result is
  `Test-Runner-2026.07.21_18-17-09-+0800.xcresult`.

## Risks / Follow-ups

- Packet sequence is transport order, not terminal damage generation, Runtime Event sequence or
  Diagnostic Event sequence; these counters must not be compared.
- A packet decoder failure intentionally delays recovery until the next refresh so the same
  one-shot native Frame is never consumed twice.
- Asset transfer identity/version and later remote framing remain independently scoped.

# T-330 Graphic Asset Packet V1 And Dual Stack

## Goal

Version the existing native-to-Dart decoded RGBA transfer as one bounded, identity-checked
Protobuf packet while retaining the exact meta/copy symbols for both upgrade directions.

## Scope

- Define `GraphicAssetPacketV1` with schema, contract, message class/name, session identity, asset
  identity/version, dimensions and decoded RGBA.
- Add optional `ianvs_session_graphic_asset_packet_v1_protobuf` with native-owned bytes released by
  the existing `ianvs_bytes_free` contract.
- Resolve one exact cached asset and capture its metadata plus bytes under one session-state lock.
- Add a bounded Dart decoder with exact identity, dimension and payload validation.
- Prefer the packet when its optional symbol exists; retain the legacy meta/copy sequence when it
  does not.
- Advertise `graphic-asset-packet.protobuf.v1` and verify real FFI plus both compatibility paths.

## Non-goals

- Do not change `terminal-frame-diff-v1`, Terminal Frame Packet v1 or Recording v1/v2.
- Do not remove or change `ianvs_session_graphic_asset_meta` or
  `ianvs_session_graphic_asset_rgba_copy`.
- Do not add live Recording asset capture, file-download migration, remote transport or UI.
- Do not retry a null or malformed new packet through legacy symbols in the same call.
- Do not authorize old-wire removal.

## Contract Boundary

- Schema is `1`; contract is `ianvs-graphic-asset-packet-v1`.
- Message class/name are `asset_transfer` / `graphic_asset`.
- Session, asset and version identity are positive canonical decimal u64 strings and must exactly
  match the request.
- Width and height are positive u32 values; RGBA length is exactly `width * height * 4`.
- Decoded RGBA is capped at 100 MiB and the encoded packet at that value plus 4 KiB.
- Unknown Protobuf fields are ignored. Unknown schema/envelope identity and malformed payloads are
  rejected before returning an asset.
- Returned bytes are released with `ianvs_bytes_free(pointer, out_len)`.

## Compatibility

- New Dart/new native prefers the packet and performs one atomic native read.
- New Dart/old native uses the unchanged legacy meta/copy pair.
- Old Dart/new native keeps using both unchanged legacy symbols.
- A malformed packet fails structurally; it does not downgrade within the same asset load.
- ReplayBackend's public asset API and bundled-asset precedence remain unchanged.

## Functional Acceptance

- A real Kitty graphic crosses the FFI boundary with exact session/asset/version identity,
  dimensions and decoded RGBA.
- Dart accepts additive unknown fields and rejects malformed Protobuf, wrong schema/envelope,
  identity drift, dimension/RGBA drift and capacity overflow.
- Packet-capable bindings are preferred without calling legacy asset methods.
- Packet-absent bindings retain the pre-existing legacy behavior.
- Runtime Capabilities is deterministic and contains the new lexically sorted feature id.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
./tools/gen_frame_diff_proto.sh
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml \
  --test runtime_capabilities_test --test runtime_graphic_asset_packet_test

cd packages/ianvs_pty
dart analyze --fatal-infos
dart test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

T-330 is closed.

- Native and Dart generated bindings share the fixed Protobuf schema. The optional FFI returns one
  native-owned packet from one locked cache lookup and keeps both legacy symbols unchanged.
- Dart validates every identity and size boundary, exposes immutable RGBA and selects the packet
  only when its symbol and byte-free function are available.
- Compatibility tests prove packet preference, no malformed-packet downgrade, legacy fallback and
  a real Rust/Dart dynamic-library bridge.
- Strict Dart analysis, 62 PTY tests, two focused Rust integrations and strict clippy pass.
- The complete `make verify` gate passes 1,733 vendored Rust tests with one ignored, 131 native
  unit tests, 518 session tests, 3 vttest regressions, 549 terminal tests with one intentional
  skip, 12 documentation contracts, 1,100 example tests, 4 macOS smoke tests, 46 real PTY tests
  and all 17 Runner XCTest cases.
- All six benchmark correctness rows report `hash_match=true` in
  `build/bench-results-ci/20260721T125256Z`; the XCTest result is
  `Test-Runner-2026.07.21_20-55-38-+0800.xcresult`.

## Risks / Follow-ups

- The 100 MiB ceiling matches today's default image-byte policy; changing that policy requires a
  separately versioned compatibility decision.
- File downloads and live Recording asset capture remain independent transports.
- Old-wire removal still requires a separately approved compatibility window.

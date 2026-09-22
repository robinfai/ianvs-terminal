# Graphic Asset Packet V1

Graphic Asset Packet v1 is the atomic Protobuf transport for one decoded RGBA asset already
identified by a Frame graphic placement. It versions the native-to-Dart asset boundary without
embedding image bytes in `terminal-frame-diff-v1` or changing Recording wire.

```protobuf
message GraphicAssetPacketV1 {
  uint32 schema_version = 1;
  string contract = 2;
  string message_class = 3;
  string message_name = 4;
  string session_id = 5;
  string asset_id = 6;
  string asset_version = 7;
  uint32 width = 8;
  uint32 height = 9;
  bytes rgba = 10;
}
```

The fixed v1 identity is:

- `schema_version: 1`;
- `contract: "ianvs-graphic-asset-packet-v1"`;
- `message_class: "asset_transfer"` and `message_name: "graphic_asset"`;
- positive canonical decimal u64 strings for session, asset and version identity;
- positive `width` and `height` with exactly `width * height * 4` RGBA bytes.

Unknown Protobuf fields are additive. Dart rejects an unsupported schema, wrong envelope,
non-canonical or mismatched identity, invalid dimensions, RGBA-length drift and encoded or decoded
capacity violations. Decoded RGBA is capped at 100 MiB, matching the existing default image-byte
boundary; encoded packets allow only 4 KiB of envelope overhead. Accepted Dart values expose an
unmodifiable RGBA view.

## FFI and ownership

The required owned-byte entrypoint is:

```text
ianvs_session_graphic_asset_packet_v1_protobuf(
  session_id,
  asset_id,
  asset_version,
  out_len
)
```

Native resolves the exact cached identity and captures dimensions plus RGBA while holding one
session-state lock. A non-null result must be released with `ianvs_bytes_free` using the exact
returned length. Missing sessions/assets, disabled graphics, invalid cached dimensions or capacity
violations return null and set `out_len` to zero.

`NativePtyBindings` requires this symbol when loading the library. A null or malformed response
is authoritative for that call; the predecessor metadata/copy symbols and Dart downgrade path
have been removed. Missing assets are not reconstructed through a second native read.

## Current transport boundary

Runtime Capabilities advertises `graphic-asset-packet.protobuf.v1`. ReplayBackend retains its
`loadGraphicAsset` API and delegates to this packet path. The predecessor `graphic-asset.rgba.v1`
feature is removed. This contract does not change Frame wire or cover file downloads, Recording
capture, remote transport or UI.

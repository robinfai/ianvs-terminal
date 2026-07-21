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

The optional owned-byte entrypoint is:

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

The packet is optional because older libraries do not export the symbol. Once the symbol is
available, a null or malformed response is authoritative for that call: Dart does not issue the
legacy meta/copy pair in the same load. This prevents a decoder or native-state error from being
silently hidden by an in-call downgrade.

## Compatibility

- new Dart/new native probes and prefers Graphic Asset Packet v1;
- new Dart/old native falls back to the exact existing `ianvs_session_graphic_asset_meta` plus
  `ianvs_session_graphic_asset_rgba_copy` sequence;
- old Dart/new native keeps using those unchanged legacy symbols;
- malformed new packets fail structurally and do not downgrade in the same call;
- ReplayBackend keeps its existing `loadGraphicAsset` API and automatically benefits when its
  native delegate exposes the packet path.

Runtime Capabilities advertises this surface as `graphic-asset-packet.protobuf.v1`. The feature
does not authorize removal of `graphic-asset.rgba.v1`, change Frame wire, or broaden this packet to
file downloads, Recording capture, remote transport or UI.

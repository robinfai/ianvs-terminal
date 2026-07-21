# Terminal Frame Packet V1

Terminal Frame Packet v1 is the correlated, ordered Protobuf transport for the existing
`terminal-frame-diff-v1` payload. It adds transport identity without changing any
`TerminalFrameDiff` field or field number.

```protobuf
message TerminalFramePacketV1 {
  uint32 schema_version = 1;
  string contract = 2;
  string message_class = 3;
  string message_name = 4;
  string session_id = 5;
  uint64 sequence = 6;
  uint64 timestamp_micros = 7;
  string frame_schema_version = 8;
  TerminalFrameDiff frame = 9;
}
```

The fixed v1 identity is:

- `schema_version: 1`;
- `contract: "ianvs-terminal-frame-packet-v1"`;
- `message_class: "frame"` and `message_name: "frame_diff"`;
- a positive decimal native u64 `session_id` matching the requested session;
- a per-session `sequence` starting at zero;
- a positive Unix `timestamp_micros` assigned when the packet materializes;
- `frame_schema_version: "terminal-frame-diff-v1"`, equal to the nested Frame value.

The Dart decoder rejects empty or larger-than-64-MiB packets, missing identity, wrong
schema/contract/class/name/session, invalid ordering and mismatched Frame versions before applying
the Frame. Unknown Protobuf fields remain additive. Nested Frame validation and entry limits remain
owned by the existing Frame decoder.

## Acknowledgement and resynchronization

The optional FFI entrypoint is:

```text
ianvs_session_take_frame_packet_v1_protobuf(
  session_id,
  after_sequence,
  has_after_sequence,
  out_len
)
```

Before its first accepted packet, Dart passes `has_after_sequence = 0`. Thereafter it passes the
last successfully decoded and accepted sequence. Native increments its packet sequence only after
it materializes and encodes a packet. If a prior packet was emitted but the next acknowledgement
is missing or stale, native marks the pending extraction for a full repaint and returns a Snapshot
at the next sequence. This recovers a packet that crossed FFI but was rejected before viewport
application.

Dart independently rejects duplicates, reordered packets and gapped Delta packets. A newer
Snapshot may establish a new accepted sequence, which permits non-native adapters to resynchronize.
A malformed packet does not fall back to a legacy take in the same refresh because native Frame
extraction is one-shot; retaining the prior acknowledgement requests recovery on the next take.

Returned bytes are native-owned and must be released with `ianvs_bytes_free` using the exact
returned length. The packet does not contain graphic RGBA or file-download bytes; those remain on
their existing identity/version-aware asset channels.

## Compatibility

- new Dart/new native probes and prefers Frame Packet v1;
- new Dart/old native falls back to `ianvs_session_take_frame_diff_protobuf`, then JSON when the
  legacy Protobuf symbol is also unavailable;
- old Dart/new native continues using both unchanged legacy Frame symbols;
- explicit JSON preference never probes or consumes the packet path;
- ReplayBackend preserves the optional packet capability and acknowledgement unchanged.

Runtime Capabilities advertises this surface as `frame-packet.protobuf.v1`. This feature does not
authorize removal of either legacy Frame symbol or change `terminal-frame-diff-v1` compatibility.

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

The required FFI entrypoint is:

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
A malformed packet never falls back to another transport. Native Frame
extraction is one-shot; retaining the prior acknowledgement requests recovery on the next take.

Returned bytes are native-owned and must be released with `ianvs_bytes_free` using the exact
returned length. The packet does not contain graphic RGBA or file-download bytes; those remain on
their existing identity/version-aware asset channels.

## Current transport boundary

### Frozen file-operation provenance

The nested Frame has additive fields `semantic_snapshot_token` (34, optional string),
`semantic_blocks` (35) and `semantic_row_contexts` (36). Native captures the Frame text,
display projection and these Block metadata under the same terminal-state lock. The token is
a per-session monotonic decimal string, independent of the packet acknowledgement sequence.
Each metadata entry contains `id`, execution-time `cwd`, and optional `context_id`,
`shell_hostname`, `shell_username`, `sftp_context_id`; each row entry contains `viewport_row`
and `block_id`. The optional SFTP context is the execution-time route lease, not a lookup
of the current route for a reused shell context ID.
The row number is a non-optional proto3 scalar: an omitted `viewport_row` means zero.
This is provenance only, not a new command execution or completed-history record.

All three fields replace the prior semantic snapshot on every Frame, including Delta frames
whose text payload contains only dirty rows. Missing metadata grants no file authority.
The live `terminal.command_blocks` response remains a separate observation; it must never
be stamped with the last displayed Frame token or used to reconstruct missing row ownership.

Native accepts only unique whole-row output ownership, including linked whitespace cells.
Later writes over closed output and structural edits revoke affected provenance.
Fold summaries, padding, ambiguous
rows, alternate screens and replay do not provide file provenance. Capture is bounded to
512 viewport rows, 128 distinct Blocks and 256 KiB of serialized metadata; exceeding a
budget emits no semantic mapping. Ownership scanning also has a bounded work allowance.
A path uses its frozen cwd, never the current shell cwd.
Host actions validate the displayed token, row and session epoch on activation and again
after menus or asynchronous confirmation. A newer displayed Frame invalidates old targets.

`TerminalFrameTransportCoordinator` requires `PtySessionFramePacketV1Backend`; it rejects a
backend without that contract. `NativePtyBindings` requires the packet symbol when loading the
library. ReplayBackend preserves the packet capability and acknowledgement unchanged.

Runtime Capabilities advertises `frame-packet.protobuf.v1`. The predecessor native Frame
Protobuf/JSON symbols and explicit JSON preference are removed. Internal Frame JSON codecs and
corpus fixtures still describe `terminal-frame-diff-v1`; they do not provide a runtime downgrade.

# Terminal Recording Format V2 Checkpoints And Graphic Assets

Recording v2 extends the canonical NDJSON contract from
[`FORMAT_V1.md`](FORMAT_V1.md) with deterministic replay checkpoint markers and
portable decoded graphic assets. It is an additive replay format: v1 remains
byte-stable and supported, while v2 files must use v2 metadata and v2 events
consistently.

## Compatibility

- Live native recording continues to emit v1. Capturing a session never silently
  changes its persisted format.
- `TerminalRecordingCheckpointPlanner` explicitly upgrades a validated v1 or v2
  recording to canonical v2.
- `TerminalRecordingGraphicAssetBundler` explicitly upgrades a validated v1 or
  v2 recording and attaches a canonical v2 asset bundle. It never mutates the
  live native v1 capture result in place.
- A v1 decoder rejects checkpoint events. A v2 decoder accepts all v1 event kinds
  plus `checkpoint`.
- Replay delegates without checkpoint support ignore checkpoint markers and still
  deliver the complete ordered output, resize and exit stream.
- Unknown future schema versions remain unsupported rather than being interpreted
  as v2.

## Checkpoint Event

The canonical event shape is:

```json
{"record_type":"event","schema_version":2,"session_id":"session-1","sequence":2,"monotonic_offset_micros":1200,"event_kind":"checkpoint","payload":{"checkpoint_id":"checkpoint-1","source_sequence":1}}
```

- `checkpoint_id` is non-empty UTF-8 and at most 128 bytes.
- `source_sequence` identifies the last non-checkpoint event represented by the
  checkpoint and must precede the marker event.
- Checkpoint event sequence numbers remain contiguous with every other event.
- Replanning strips existing markers and normalizes source event sequences before
  inserting a deterministic replacement set, so repeated planning is byte-identical.

The default planner inserts an initial checkpoint after `session_started`, then a
checkpoint every 256 playable events and a final checkpoint when needed. The
interval is configurable from 1 through 4,096 events; the planned recording may
contain at most 64 checkpoints.

## Safe Parser Boundaries

`TerminalSnapshot` does not serialize an incomplete VT parser control string. A
checkpoint taken in the middle of CSI, OSC, DCS, APC, PM or SOS input would
therefore restore a different parser state.

Both the Dart planner and native replay session track the control-sequence
boundary. The planner delays a marker until the parser returns to Ground, and the
native capture API independently rejects an unsafe boundary. CAN, SUB, BEL and ST
termination are handled explicitly. This defense is required even for hand-built
v2 recordings that did not pass through the planner.

## Materialization And Bounds

A persisted checkpoint is a marker, not a serialized native heap snapshot. When
replay reaches the marker, `TerminalReplayBackend` asks an optional native
checkpoint capability to capture the current terminal state and records the
returned opaque session-local id.

Native replay retains at most 64 checkpoints and 32 MiB of estimated checkpoint
state per session. Oldest entries are evicted first. A single checkpoint larger
than the byte budget is rejected. Opaque ids are valid only for the replay session
that created them.

Restoring a checkpoint replaces terminal/parser-visible state, transcript,
scrollback and Host Protocol parser state, then forces a full Snapshot Frame.
Graphic asset caches and pending downloads are cleared so visible assets are
reconstructed from restored terminal state.

Runtime Event sequences are not rolled back or cleared. Their ordering contract is
monotonic for the lifetime of the replay session; a future seek controller must
coordinate its own replay cursor without manufacturing an Event sequence gap.

## Seek Contract

`TerminalReplayBackend.seekSession` accepts an inclusive target between zero and
the recording duration. It selects the latest checkpoint already materialized at
or before that offset, restores it, and synchronously feeds recorded output,
resize and exit events through the target. Historical user input remains excluded.

If more than one checkpoint has the same offset, the later resume position wins.
Known markers are never captured twice. Realtime playback cancels its previous
timer only after restore succeeds, then schedules from the requested offset using
the existing absolute speed-scaled timeline. No-delay playback stays positioned at
the target.

Pending events that existed before seek remain buffered for the caller. Runtime
Events regenerated only by fast-forward are drained internally, while their native
sequence numbers remain monotonic. A missing or evicted opaque checkpoint returns a
typed restore failure instead of falling back to timestamp-only state.

## Graphic Asset Bundle

Canonical v2 stores decoded RGBA separately from asset identity so identical
pixels are written once even when more than one `(asset_id, asset_version)` key
references them. All `graphic_asset_blob` records precede all `graphic_asset`
records, and both groups precede event records.

A blob record has this shape:

```json
{"record_type":"graphic_asset_blob","schema_version":2,"blob_id":"sha256:<64 lowercase hex>","width":1,"height":1,"rgba_base64":"AQID/w=="}
```

An identity reference has this shape:

```json
{"record_type":"graphic_asset","schema_version":2,"session_id":"session-1","asset_id":7,"asset_version":1,"blob_id":"sha256:<64 lowercase hex>"}
```

- The SHA-256 input is UTF-8 `width:height:` followed by decoded RGBA bytes. It
  is a deterministic content address and corruption check, not an authenticity
  or trust claim.
- Asset identities, widths and heights are positive. RGBA length must equal
  `width * height * 4` exactly.
- One recording contains at most 128 asset identities and 128 unique blobs. The
  sum of unique decoded RGBA is at most 32 MiB.
- Blob records sort by `blob_id`; identity records sort by `asset_id` then
  `asset_version`. Duplicate content is deduplicated, while duplicate identities,
  conflicting identities, unreferenced blobs and missing references are rejected.
- Hash mismatch, invalid base64, dimension drift and bound violations return a
  structured `TerminalRecordingFormatException` instead of a partial bundle.

`TerminalReplayBackend.loadGraphicAsset` serves an exact bundled identity before
consulting the optional native graphic-asset delegate. A missing bundled identity
keeps the native fallback, preserving old delegates and recordings.

## Persistence Boundary

Checkpoint markers survive process restart, but materialized native snapshots do
not. A new process must replay the prefix once to materialize a marker before it
can restore that marker. Bundled decoded graphic assets survive restart and can
restore exact asset keys, but they do not serialize a native `TerminalSnapshot`,
pending download state or Host effects. Graphic placement still comes from replayed
output/Frames; an asset blob alone does not manufacture a placement. A portable
serialized snapshot and long-lived snapshot migration contract remain separate work.

## Scope

T-327 establishes the versioned marker, safe materialization and bounded native
restore primitive. T-328 adds deterministic backend seek on top of that primitive.
T-329 adds the bounded content-addressed graphic asset bundle and ReplayBackend
lookup path. These slices do not add pause, Replay UI, full Host Request/Response
recording, live asset capture wiring or checkpoint files.

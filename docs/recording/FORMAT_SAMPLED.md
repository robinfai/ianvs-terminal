# Sampled recording container, implementation draft

This describes the schema 2 format now used by the application's capture and
saved-replay entrypoints. It remains under development; current acceptance gaps
are tracked in the [delivery task](../tasks/adaptive-session-recording.md).

## Bundle and ownership

A new `.trailrec` directory contains `records.bin`, an `assets/` directory, and
an optional disposable `seek.index`. Creation uses a new directory/file and
never overwrites an existing bundle or legacy NDJSON. Library reservation,
publication, active-file protection and deletion belong to the application
repository; this native slice does not replace those responsibilities.

The primary file starts with eight bytes `TRLREC02`, a little-endian `u32` JSON
metadata length, a 32-byte SHA-256 digest of that JSON, and the JSON. Metadata is
at most 64 KiB and contains recording ID, UTC start milliseconds, title and an
optional host. IDs are bounded to 128 bytes; metadata strings to 8 KiB.

## Record envelope

Each record has a 60-byte header followed by a payload of at most 17 MiB:

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 4 | `TRC2` |
| 4 | 1 | 1 visual, 2 semantic, 3 completed footer |
| 5 | 3 | Reserved, must be zero |
| 8 | 4 | Little-endian payload length |
| 12 | 8 | Zero-based record ordinal |
| 20 | 8 | Monotonic microseconds since recording start |
| 28 | 32 | SHA-256 of header bytes 0–27 and the payload |

Ordinals are contiguous across visual and semantic tracks. Offsets cannot move
backwards. Length and remaining file bytes are checked before payload allocation.
Unknown kinds, malformed fields, dependency errors and checksum failures stop
reading at the last verified record; readers do not scan ahead past damage.

Visual payloads are Protobuf messages containing visual sequence (tag 1),
optional prior visual sequence (tag 2), structured `TerminalFrameDiff` (tag 3),
and all currently visible asset bindings (tag 4). Visual sequences are contiguous;
keyframes omit the prior sequence. Stored deltas refer to the previous stored
screen. A keyframe is eligible after five seconds and required at least every
128 visual samples, limiting dependency depth during dense hook bursts.

The initial implementation reuses current frame model types. Storage-envelope
and frame-shape compatibility are separate checks; future live ABI changes must
explicitly review the stored frame schema. No raw PTY or input record kind exists.

Semantic payloads are strict JSON `SemanticEvent` objects. Kinds include command
start/finish, context change, hook available/unavailable. Hook text is retained
without UI truncation; individual fields are capped at 64 KiB. Oversized or
malformed capture input is surfaced as a recording failure, not silently clipped.
Timestamps use native observation time, not remote shell wall time. A command
already running when recording starts can have a finish without a recorded start.

The completed footer is strict JSON with visual count, semantic count, record
count **excluding the footer**, and duration. A valid footer must match the
preceding records. A file without a footer is interrupted. Trailing bytes after
a footer are reported as damage rather than ignored.

## Images

Each asset binding contains native ID/version, original dimensions and a
32-byte content digest. The blob name is the hexadecimal digest plus `.rgba`.
The blob bytes are `TRLRGBA2`, little-endian `u32` width and height, then RGBA.
The digest covers dimensions and pixels, permitting deduplication across native
IDs and versions. Blob length and checksum are verified when pixels are loaded.

Blobs are written to a temporary file, synchronized, published without replacing
an existing blob, and the asset directory is synchronized before a visual can
reference them. Native capture copies the needed pixels while the terminal state
is locked, before live-cache eviction. Per-frame limits are 256 distinct assets
and 32 MiB of total decoded pixels. Dimension multiplication uses checked arithmetic.
The primary record scan validates bindings; pixel integrity is checked separately
when loading referenced blobs. Complete primary records alone do not certify
that every external blob is still present after arbitrary file modification.

## Background writing and recovery

The producer queues serialized payloads, with a shared 64 MiB admission budget,
at most 64 pending records per writer and 16 active writers. These are provisional
engineering limits. In-flight records retain their budget until the disk write
finishes; object, decoder and screen memory are additional bounded state, not
included in the payload counter. Queue exhaustion visibly stops the capture.
Already admitted records drain to a synchronized interrupted prefix.

The writer calls `sync_all` on a five-second wall-clock deadline, including while
idle, and on stop. Status distinguishes written and committed counts. A slow or
failed filesystem can miss a deadline; the ten-second product recovery target
requires real system/disk validation. Process-kill tests and one idle five-second
commit test are present; they are not power-loss evidence.

Recovery currently performs a read-only prefix scan. It never truncates or
rewrites primary data, and cancellation leaves it intact. Repair/publication must
respect application ownership and must not race active writers.

## Disk index and native capture

`seek.index` is a disposable disk cache with a 104-byte checksummed header
and 64-byte checksummed entries for keyframes. Entries store timestamp, primary
file offset, record ordinal and visual sequence. Open validates source length,
metadata fingerprint and index length. Seek binary-searches entries on disk,
then streams the selected dependency group, checking cancellation between records.
It does not open a PTY or execute historical host actions. Interrupted prefixes
can be indexed; stale or corrupted indexes fail and can be rebuilt by streaming.

The writer appends keyframe and command index entries as records are written.
After syncing primary data, each five-second commit (and finish) syncs both index
headers and publishes `summary.index` last. It never copies or rescans an entire
index to commit. Cache I/O failure disables publication for that writer; primary
capture remains authoritative and the next open can rebuild caches.

`summary.index` contains `TRLINFO2`, a little-endian `u32` payload length, SHA-256
of the payload, and strict JSON capped at 64 KiB. The payload stores schema 2,
metadata fingerprint, scan report and local file stamps for records, seek and
command indexes. Stamps include length and nanosecond modification time; Unix
also checks device, inode and change time. Copied, replaced, changed, missing or
corrupt files invalidate this disposable cache. Checksums still verify each
record, keyframe and command when read; the marker is not an authenticity proof.

Normal opens validate this bounded marker and file stamps without scanning the
primary stream. An interrupted file exactly at a published commit also opens
this way. An uncommitted tail, damaged cache or imported bundle requires one
cancellable, bounded-memory prefix scan and atomic cache replacement. Recovery
never rewrites primary data. Application ownership prevents index rebuild from
racing a live writer. File work runs on bounded Dart worker isolates and has
native cancellation, including UI seek replacement.

Native Session capture has its own snapshot extraction and 100 ms observation
timer; it does not consume UI damage/acknowledgements or require frontend polling.
The adaptive sampler selects stored samples from these observations. Hooks enter
the recording before UI queue admission. Bounded live hook context survives a
mid-session start; command boundaries and missing coverage remain explicit.
The native clock timestamps hook observation, so multiple hooks parsed in one
read can be associated with the same resulting screen. Sampling is not lossless
output capture and does not claim an exact intermediate screen for every command.


## Capture control during app integration

The `terminal.sampled_recording_start/status/stop/release` operations use
Session Request v1 with a strict schema 2 operation payload. The application uses
these operations and advertises `session-recording.v2` with format version 2.
The application must persist its library reservation and filesystem claim before
start. It generates a 32-character lowercase hexadecimal capture ID and reserves
an absolute path whose final component is `<capture_id>.trailrec`.

Start takes `schema_version`, `capture_id`, `bundle_path` and `metadata` (whose
`recording_id` must equal the capture ID). The other operations take the first
three fields. The positive originating session ID remains part of the outer
request identity after the session closes. Retrying an identical start is
idempotent; changed metadata, session or path under the same ID is rejected.

Requests do not perform disk creation, snapshot extraction or final writing on
the caller thread. A bounded registry retains at most 128 jobs, including at most
16 unsettled captures. Stop intent can arrive before initialization completes.
Native status remains available after SessionStore removal. A delayed stop is
bound to its recording ID and cannot stop a subsequent capture in that session.
Filesystem creation does not hold the session capture lock, so close and hook
handling do not wait for a stalled create or header synchronization.

Status includes phase (`starting`, `capturing`, `stopping`, `finished`,
`interrupted`, `failed`), written/committed counts, error, stop intent and
`settled`. A failed producer may still have a draining writer: only `settled=true`
proves that native worker has closed its file and released its pending queue.
The library must also honor its own process/filesystem ownership claim.
Release is allowed only after settlement and removes only the registry entry.
It never deletes or renames recording files. Unknown entries, malformed replies,
identity conflicts, transport errors and polling timeouts are not settlement.
The Dart client validates the correlated identity, exact fields, counts and state
relationships and preserves these distinctions for the application repository.


## File requests and application ownership

`ianvs_recording_file_request_v2_json` accepts a strict JSON object containing
`schema_version: 2`, `operation`, `job_id` and `payload`. The returned UTF-8 string
is released with `ianvs_string_free`. Reserve returns a decimal job ID; cancel
sets an atomic flag; release is rejected while a read is running. At most eight
native read jobs exist concurrently. Requests are at most 64 KiB; responses are
at most 48 MiB. The Dart API limits itself to two workers and 256 queued requests.

Read operations are `inspect`, `metadata`, `seek`, `timeline` and `asset`.
Inspect uses valid local summary/index caches, or streams a recovery scan to
rebuild them. Metadata only verifies the native header and recording identity. Seek returns one complete
Protobuf screen plus asset bindings. Timeline returns up to 128 semantic events
and a byte cursor. Asset returns verified RGBA pixels. Binary payloads are base64
on this JSON boundary and decoded on the worker isolate; no session is created.

`commands.index` starts with `TRLCMD02`, the primary source length (`u64`), a
32-byte metadata fingerprint and a SHA-256 checksum of those 48 header bytes.
Each entry contains a `u32` length, 32-byte SHA-256 and semantic-event JSON. The
cache is replaceable and must match the primary file length and metadata.

The application reserves `recordings-v2/entries/<id>.json` before dispatching
capture and retains `claims/<id>.lock` until actual native settlement. Permanent
lock files are never unlinked. Viewer leases also survive cancellation until all
file reads settle. Keep, active, unknown-schema and corrupt-manifest entries are
excluded from automatic retention. Orphan new-format bundles recover as Keep;
legacy NDJSON and directories outside this library are never cleanup candidates.
Manifest writes use flushed temporary files and rename; directory durability and
system-failure acceptance are still outstanding.

# Sampled recording container, implementation draft

This describes the native implementation under development, **not the current
app entrypoint**. The app still uses [FORMAT_CURRENT](FORMAT_CURRENT.md) until its
Dart/UI/library integration switches. This is not a claim of completed batch 2,
power-loss durability, production performance or 24-hour acceptance.

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

`seek.index` is an atomically published cache with a 104-byte checksummed header
and 64-byte checksummed entries for keyframes. Entries store timestamp, primary
file offset, record ordinal and visual sequence. Open validates source length,
metadata fingerprint and index length. Seek binary-searches entries on disk,
then streams the selected dependency group, checking cancellation between records.
It does not open a PTY or execute historical host actions. Interrupted prefixes
can be indexed; stale or corrupted indexes fail and can be rebuilt by streaming.

The current index builder scans the primary file. Incremental index publication
during capture, app-owned asynchronous jobs and UI seek cancellation remain
integration work; rebuilding an entire long file on each open is not the target.

Native Session capture has its own snapshot extraction and 100 ms observation
timer; it does not consume UI damage/acknowledgements or require frontend polling.
The adaptive sampler selects stored samples from these observations. Hooks enter
the recording before UI queue admission. Bounded live hook context survives a
mid-session start; command boundaries and missing coverage remain explicit.
The native clock timestamps hook observation, so multiple hooks parsed in one
read can be associated with the same resulting screen. Sampling is not lossless
output capture and does not claim an exact intermediate screen for every command.

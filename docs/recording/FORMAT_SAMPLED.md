# Sampled recording container, schema 2

This describes the schema 2 format now used by the application's capture and
saved-replay entrypoints. The four-batch acceptance result and measured limits
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
sets an atomic flag; release is rejected while a file operation is running. At most eight
native file jobs exist concurrently. Requests are at most 64 KiB; responses are
at most 48 MiB. The Dart API limits itself to two workers and 256 queued requests.

Read operations are `inspect`, `metadata`, `seek`, `timeline`, `asset` and `search`.
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
The library persists `retention.json` with exactly `schema_version: 2`,
`maximum_age_days` (integer 1..36500), and `maximum_bytes` (integer
1..9007199254740991). Both limits apply to ordinary recordings. Defaults are
30 days and 20 GiB until explicitly saved. Unknown, malformed, oversized or
non-regular policy files block automatic cleanup and new capture; they never
silently reset to defaults. A deliberate settings save replaces the policy and
applies cleanup immediately, so a cleanup error can occur after settings were
saved. The UI reports that distinction and allows retry.

Cleanup runs at startup and every five minutes, with at most one periodic run
in flight. Shutdown stops scheduling and waits for ongoing cleanup/library
mutations. Keep can be changed during replay or search; metadata refreshes and
Keep changes are serialized so late reads cannot restore an old flag. Deletion
is disabled for the selected replay, requires confirmation otherwise, and removes
its bundle/indexes and manifest while retaining the permanent claim file.

Manifest and policy writes use flushed temporary files, rename, then a native
`sync_directory` request. Its payload is exactly `directory_path`, an absolute
path to an existing directory; Unix opens it with `O_DIRECTORY | O_NOFOLLOW`
and calls `sync_all` before acknowledging an empty result. Symlink leaves,
non-directories, unknown fields and unsupported non-Unix platforms fail explicitly.
The same bounded worker/job registry keeps blocking sync work off the UI isolate.

Directory creation synchronizes each new directory and its parent. Bundle deletion
synchronizes the library root before removing and synchronizing the manifest.
Failed directory acknowledgement invalidates prepared-directory state, so a retry
re-establishes publication even if the old unlink already removed the manifest.
A missing manifest never authorizes deletion of a remaining orphan bundle.
Capture reservation is not returned before publication; capture settlement retains
its file/native claim until the final manifest write succeeds. The file-worker
provider closes in the infrastructure shutdown phase after application persistence.
Actual process-kill evidence is separate from system/power-loss behavior.
[DURABILITY_ACCEPTANCE](DURABILITY_ACCEPTANCE.md) records actual APFS
full/disconnect and isolated Linux guest-kernel crash recovery, with explicit
platform/timing limits; it does not establish macOS hardware power-loss behavior.


## External new-format bundles

The picker copies an external schema-2 bundle into the managed library and marks
it Keep. Selecting an existing managed entry opens it without copying. The old
NDJSON format is never read, imported, migrated or cleaned. External originals
are not modified, indexed, moved or deleted; only their verified new-format
primary data and referenced graphic assets are admitted.

`copy_bundle` accepts exactly `source_path`, `destination_path` and
`maximum_bytes` (integer 1..9007199254740991). Both paths are absolute `.trailrec`
directories; the destination must not exist or resolve inside the source. It
preserves the 32-lowercase-hex recording identity and exact primary bytes,
including a damaged tail, and validates referenced assets against the verified
prefix. Unreferenced assets, external indexes and unknown files are omitted.
Changed primary files, symlink leaves/assets, missing or corrupt referenced
assets and budget exhaustion fail explicitly. Copying uses bounded blocks and a
bounded recent-asset cache, counts deduplicated blob bytes including headers,
and checks cancellation between blocks. It synchronizes the copy and parent
before returning exactly `inspection` (the inspect result) and `copied_bytes`.
Failed copies remove only their newly created destination when possible; the
caller retains staging ownership until the worker actually settles.

`publish_bundle` accepts exactly `staging_path`, `destination_path` and
`recording_id`. It validates the staging metadata and final `<id>.trailrec` name,
then atomically renames without replacing any existing entry, including an empty
directory. It uses descriptor-anchored exclusive rename on macOS/Linux and
synchronizes both parent directories before returning an empty acknowledgement.
Other platforms fail explicitly. A failed acknowledgement can occur after the
rename; the caller must preserve that destination for orphan recovery.

Before dispatching a copy, the application durably writes
`.imports/<nonce>.json` with exactly `schema_version: 2` and `import_id: <nonce>`.
The nonce is 32 lowercase hex digits and owns only the sibling
`<nonce>.trailrec` staging directory. One library mutation claim spans the copy,
local index preparation, final capacity check, exclusive publication, Keep
manifest and staging cleanup. Active-file growth and staging/index bytes count
against capacity. Existing recording identities are rejected without replacing
their data or manifests. Cancellation before publication removes only owned
staging after the worker settles. Once publication begins it settles without UI
cancellation; a committed copy stays protected even if its viewer was cancelled.

Restart and retention clean only staging authorized by a strict known journal;
unknown, corrupt and future journals remain untouched and their regular-file
bytes count as protected capacity. A published bundle without its manifest
recovers as Keep. Staging deletion is synchronized before its journal is removed
and synchronized. Shutdown first cancels imports, then waits for queued
maintenance, picker reads and library operations before closing file workers.


## Retained text search

The first search creates disposable `search.index` and `search.info` files by
streaming the verified primary prefix. Index construction is cancellable and
holds only current replay state, previous logical lines and 64 recent command
starts; it does not keep the recording history in memory. Temporary files are
published only after a complete scan. Source metadata/file stamps and the index
stamp invalidate changed or damaged caches; primary data is never rewritten.

`search.index` begins with `TRLTXT02`. Each document contains two little-endian
u32 lengths (metadata and text), a SHA-256 digest of their concatenated bytes,
strict JSON metadata and UTF-8 text. Metadata holds offset, command/screen kind,
host and optional row. Text is capped at 16 MiB and metadata at 512 KiB per
document. `search.info` contains a 32-byte SHA-256 and at most 64 KiB of strict
JSON identifying schema 2, metadata fingerprint and source/index file stamps.
Both files are disposable local caches, not authenticity evidence.

Screen documents join soft-wrapped rows and include sized-text placements;
unchanged logical rows at the same position are not repeated. Host changes
index the last retained screen under the new context at that event time, matching
what replay can actually show. Command starts and orphan finishes are indexed.
A finish whose start was evicted from the 64-context deduplication window can
produce a duplicate hit. No raw keys, OCR or unsampled output are searched.

Queries use case-insensitive Unicode lowercase substring matching. Native pages
return at most 100 hits with previews capped at 240 characters plus ellipses.
Work yields after 2,048 documents, about 4 MiB scanned, or about 1 MiB of response
text; one bounded document may exceed the scan budget. Empty pages can have a
forward byte cursor. Cancellation is checked during construction and paging.
First construction still requires a complete streaming scan of the recording.

The application searches finished/recovered library files, newest first, with
recording start-date, nested-host and command/screen filters. It keeps one page
of at most 50 results and 128 prior cursors; the first page remains reachable.
Date ranges use local calendar boundaries converted to UTC. Unreadable files
produce a partial-results warning. A result opens replay at its stored time and
never creates a PTY or dispatches a historical command.

Replay and search share one process-owned OS file descriptor per recording.
Each reader retains its reference until its native work settles, including after
cancellation. Only the last reader releases the shared OS lock. Exclusive writer
and cleanup claims still reject busy files. Search caches live inside the bundle
and are deleted with it; no external search entry outlives library deletion.

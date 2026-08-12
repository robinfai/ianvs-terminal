# Terminal Recording Current Format

The Iteration 03 recording format is newline-delimited JSON. It is intentionally separate from
the existing Frame JSON/Protobuf wire: a recording describes an ordered session event stream,
while a Frame describes current render state.

## File Structure

Line 1 is the required metadata record:

```json
{"record_type":"metadata","schema_version":1,"session_id":"session-1","created_at_utc":"2026-07-21T00:00:00.000Z","input_policy":"redact"}
```

Every following line is an event record:

```json
{"record_type":"event","schema_version":1,"session_id":"session-1","sequence":0,"monotonic_offset_micros":0,"event_kind":"session_started","payload":{"terminal_emulation":"xterm256","cols":80,"rows":24}}
```

The current event kinds are:

- `session_started`: terminal emulation plus initial rows and columns.
- `pty_output`: raw PTY output bytes encoded as Base64.
- `user_input`: Base64 bytes when metadata uses `record`, or only `byte_length` plus
  `redacted: true` when metadata uses `redact`.
- `resize`: rows, columns, pixel dimensions and optional cell pixel dimensions.
- `session_exited`: an integer exit code or `null`.
- `checkpoint`: a bounded deterministic replay checkpoint marker.
- `shell_semantic`: bounded shell-integration command, directory, prompt and
  remote-session metadata.

Content-addressed `graphic_asset_blob` and `graphic_asset` records may appear
between metadata and events. They use the same schema version as metadata and
events and retain the existing 128-asset / 32 MiB decoded-byte bounds.

Checkpoint planning inserts an initial marker after `session_started`, then
bounded periodic/final markers only at safe parser boundaries. Native replay
retains at most 64 materialized checkpoints and 32 MiB of estimated checkpoint
state per session. Seek restores the latest materialized marker at or before
the target and deterministically replays forward. Graphic blobs are SHA-256
content-addressed, sorted canonically and rejected on missing/corrupt identity.

`sequence` starts at zero and is contiguous. `monotonic_offset_micros` is non-negative and cannot
decrease. Every event must use the metadata session id and schema version. These invariants make
loss, cross-session mixing and event reordering explicit decoding failures.

## Validation And Errors

- Additive unknown object fields are ignored and removed by canonical re-encoding.
- Unsupported schema versions and event kinds are rejected; the current format does not silently guess their
  semantics.
- Invalid JSON, truncated records, invalid payloads, sequence gaps, decreasing monotonic offsets
  and session mismatches produce `TerminalRecordingFormatException` with a stable error code and
  source line number.
- The fixed contract fixture is
  `packages/ianvs_terminal/test/fixtures/recording/basic_current.ndjson`.

## Input And Output Privacy

Input policy is required metadata rather than an implicit recorder default:

- `redact` records only the input byte count. It is the recommended default for future product
  wiring because passwords, tokens and pasted secrets never enter the recording file.
- `record` stores exact input bytes and must require an explicit product/user decision before a
  live recorder enables it.

Redacting input does not make the whole recording non-sensitive. PTY output may contain commands,
paths, environment values, file contents or credentials echoed by a child process. Recordings
must remain local unless a separate explicit export/upload action is approved.

## Live Capture Boundary

T-310 connects the format to an explicitly started native recorder. Raw output is copied at the
PTY reader before parser or Frame processing; successful user writes, resizes and observed child
exits share the same ordered recording boundary. The capture buffer is limited to 4,096 events and
8 MiB of raw payload. Capacity overflow returns `capacity_exceeded` and discards the recording at
stop instead of silently evicting events or exporting a partial stream.

`TerminalLiveRecorder` uses the existing session JSON request bridge for start, stop and cancel.
It validates stopped native NDJSON through `TerminalRecordingCodec` before exposing the recording.
Capture does not add raw output to the normal product event queue and does not change Frame
JSON/Protobuf.

## Single Current Schema

The project is not released, and only the current recording contract is
accepted. Native capture, Dart construction, checkpoint planning, semantic
merging, graphics bundling, repository metadata and replay all emit and accept
exactly `schema_version: 1`. Any other value fails closed.

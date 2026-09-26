# Terminal Recording Current Format

The application now captures and opens schema 2 `.trailrec` bundles. The complete
byte layout, validation rules, bounds and recovery behavior are described in
[the sampled recording specification](FORMAT_SAMPLED.md).

A bundle contains `records.bin`, content-addressed RGBA assets and rebuildable
seek/command/text indexes. Visual records retain adaptively sampled structured screen
state; semantic records retain independently observed hook commands, arguments,
context and status. Raw keystrokes and lossless PTY output are not recorded.
A sample can omit short-lived output; commands without observed hooks are absent.

The native capability is `session-recording.v2`, with
`recording_schema_versions: [2]`. Live Frame Packet v1 and Session Request v1
remain separate versioned envelopes. Sampled capture operations carry strict
schema 2 payloads. The file reader has its own `ianvs_recording_file_request_v2_json`
entrypoint and never creates a PTY or dispatches historical host actions.

The app owns a separate `recordings-v2` library. It persists a reservation before
native start, retains its filesystem claim until the writer settles, and marks
recovered prefixes as interrupted. Existing schema 1 NDJSON files and indexes are
left untouched. The application does not read, migrate, rewrite or delete them.

This is the development implementation, not completed release acceptance.
The writer publishes incremental seek/command indexes and a bounded summary
cache for normal opens; changed files fall back to a recovery scan. Cross-recording
command/screen search with host/date filters and result-to-replay navigation is
implemented with cancellable, bounded pages. The library exposes persistent
age/capacity settings, Keep and explicit deletion; cleanup runs at startup, every
five minutes and after an explicit settings apply. Active/read files remain
protected. External bundle ownership, directory durability and more-than-24-hour
system/product validation remain open in the
[delivery task](../tasks/adaptive-session-recording.md). The application recording
tests and isolated review entrypoints use the new product contract;
full release acceptance is still pending.

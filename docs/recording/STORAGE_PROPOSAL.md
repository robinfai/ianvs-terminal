# Adaptive structured recording plan

Status: four-batch delivery accepted on 2026-09-27 under the user-revised
approximately two-hour acceptance scope. The application
now uses the new capture and structured replay path described in
[FORMAT_CURRENT](FORMAT_CURRENT.md) and [FORMAT_SAMPLED](FORMAT_SAMPLED.md).

Native sampling, writing, recovery, disk seek, hook tracking and bounded Dart
file workers are connected to the application library and player.
The [requirement audit](ACCEPTANCE_RESULT.md) records the completed delivery. Incremental indexes and bounded cached opens are
implemented, along with cross-recording command/screen search and host/date
filters. Persistent retention settings and Keep controls are connected. Library
metadata and directory publication now await native synchronization acknowledgements.
External new-format bundles use cancellable owned staging, protected publication
and restart cleanup. Actual macOS disk-full/retention UI and bounded APFS/Linux
guest-crash evidence are recorded in
[DURABILITY_ACCEPTANCE](DURABILITY_ACCEPTANCE.md). The user revised actual-duration acceptance to approximately two hours on
2026-09-27. The corrected application captured 1 h 54 min 43 s; resource review
and independent new-process file verification are recorded in
[REAL_DURATION_ACCEPTANCE](REAL_DURATION_ACCEPTANCE.md). The final timeout was reproduced as external Escape/Bash history-search
interference; the corrected menu Cancel control passed. See the
[delivery task](../tasks/adaptive-session-recording.md).
Current file timings do not establish OS-cold-cache performance.

## Fidelity and scope

Persist adaptively sampled **structured visible terminal state** and an
independent hook timeline. Preserve text, styles, cursor, geometry, links and
graphics references/assets. This is sampled visual history, not lossless raw
output and not bitmap video. Intermediate output can be absent. Commands and
their arguments come from hooks; raw input bytes are never part of the new format.
Unavailable hook coverage must be explicit.

Recording is manually started per Session and uses one monotonic timeline.
The release acceptance run now targets approximately two hours by user request;
the implementation does not impose a two-hour recording limit. The initial sample includes the visible state already
present at start. Semantic events preserve ordering independently of visual
sampling. Boundary frames and command IDs/context IDs permit navigation without
pretending to capture unobserved output. Replay must never run commands, open
connections or dispatch historical host side effects.

## Sampling and state correctness

Apply every live delta before selecting stored samples. Build each storage delta
against the preceding **stored** screen, not the preceding live transport frame.
Do not drop an intermediate live delta and then apply a later relative delta.

The state assembler must preserve unchanged rows/hyperlinks through scrolling,
replace metadata and graphics correctly, reject unbased deltas, and force
self-contained keyframes for initial state, resize, alternate-screen transitions
and a measured seek cadence. A stable screen need not create duplicate periodic
records. Frame shape version, storage/container version and metadata version are
separate contracts even if the initial implementation reuses frame model types.

Sampling intervals respond to measured visual activity and writer pressure;
semantic events are not dropped for visual-rate control. Queue admission failure
must visibly stop capture while preserving verified data, rather than claiming
an intact timeline. Initial 100 ms–1 s sampling and 5 s keyframe eligibility in
the prototype are calibration inputs, not fixed product defaults.

## Storage, reading and recovery

Use independently validated bounded chunks, explicit lengths and checksums,
time/sequence indexes and self-contained keyframes. Finalization distinguishes
completed files from verified interrupted prefixes. The new format must be
identifiable without parsing old NDJSON; unknown formats are rejected intact.

Continuous background writing and all-session queue limits bound memory.
Durable commits target a maximum ten-second uncommitted tail. A flush to a
language/runtime buffer is not proof of durable storage. Test process kill,
partial chunk/index/footer, corrupt length/checksum, cancellation, queue/disk
exhaustion and system restart separately. Recovery must not race a live writer.

Open/seek/search are incremental and cancellable. Indexes may be rebuilt; they
must not require loading an entire recording into memory. Assets needed by a
retained sample must be captured before eviction, content-identified, bounded
in decoded size and available at independent cold seek positions.

## Library and retention

First-release scope includes cross-recording search of commands and retained
screen text with host/date filters. Do not report unsampled output as searchable.
Maintain index/file consistency through rename, recovery and deletion.

Ordinary recordings are eligible for automatic removal under **both** configurable
age and aggregate capacity limits. Keep-marked and active recordings are protected.
If protected contents exhaust the budget, report the condition and prevent new
capture. Never select old NDJSON files or unknown schemas for cleanup. Disabling
or replacing this library does not delete legacy files.

## Validation and delivery

The four delivery batches and complete acceptance requirements live in the
[active task](../tasks/adaptive-session-recording.md) and [roadmap](../ROADMAP.md).
Canonical implementation remains in native/core, terminal packages and the app
recording feature; regenerate standalone package mirrors using the existing tool.

Compare sampled states with independently forced native snapshots, including
8,000-line scrollback eviction, split Unicode/control sequences, hyperlinks,
resize, alternate screen, nonempty initial state, metadata-only frames and asset
version changes. Seek from keyframes must equal sequential replay at stored
positions. Include all metadata/index/asset/keyframe bytes in size reports.

Measure capture cost, retained/queue/peak RSS, write CPU, disk growth, stop time,
cold/warm first frame, seek/search P50/P95 and input/render responsiveness on
identified hardware. Separate synthetic logical-duration tests from the
user-approved approximately two-hour wall-clock acceptance. Historical storage experiments are reference
tools, not adoption evidence; see [benchmarks](../../tools/recording_bench/README.md).

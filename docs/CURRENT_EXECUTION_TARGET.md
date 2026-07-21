# Current Execution Target

Date: 2026-07-21

This document is the human-readable view of
[`CURRENT_EXECUTION_TARGETS.json`](CURRENT_EXECUTION_TARGETS.json). The JSON
manifest is validated by `dart test test/docs_contract_test.dart`; it records
the current lane, repository evidence, verification commands, and blocked or
deferred directions.

## Calibrated Decision

The active target is **`runtime-contract-stability`**.

Iteration 01 and the supplemental real `vttest` gate are now closed on the
current macOS host. Iteration 02 is also closed: the bounded Frame extraction
finished with unchanged schema, golden/parity output and deterministic benchmark
hashes, followed by a complete repository gate. Re-reading the foundation
handoff confirms that Iteration 03 is Recording / Replay MVP and Workspace
follows it. T-309 through T-311 have now closed that MVP with a complete
repository gate, so the active work advances to stabilizing the existing local
Workspace, profile, session bootstrap, persistence and lifecycle paths. T-312
and T-313 now close the first Workspace stability slice: schema migration,
real-session relaunch, live persistence and visible relaunch failure handling.
T-314 closes the next bounded slice: Session Descriptor v1 and the Workspace
schema v2 migration passed the complete repository gate. T-315 closes the
storage half of project/Recent Workspace identity with Workspace schema v3, an
independent collection and Recent index v1. T-316 closes the product half with a
native project picker, Recent Workspace menu and failure-safe live switching.
T-317 now closes the recording lifecycle association slice with redacted capture,
atomic local persistence, retryable pending-save state and destructive-transition
gates, completing the bounded Local Workspace baseline. T-318 starts the handoff
Runtime Contract phase with a versioned, optional capability query. It does not
remove old FFI or change Frame/Recording payloads. T-319 then closes the first bounded
wire migration: Runtime Event Envelope v1 is preferred when available, while older
native libraries continue through the legacy event array. T-320 closes the next bounded
migration: live and replay session creation now prefer product-neutral SessionConfig v1,
while both old Profile-shaped symbols and new-Dart/old-native fallback remain verified.
T-321 closes the next bounded migration: generic synchronous session commands now prefer
correlated Session Request/Response v1 envelopes with structured protocol errors, while the exact
legacy `{kind, ...payload}` request and symbol remain covered in both upgrade directions.
T-322 closes the first bounded native-to-product Host Request/Response migration: only OSC 52
text clipboard reads become correlated v1 Host Requests, while old event polling and direct PTY
responses remain compatibility-tested. T-323 closes the Frame/Session metric migration with
typed Diagnostic Event v1 envelopes, while both legacy debug-stat symbols and the independent
privacy-preserving diagnostics export remain compatibility-tested. T-324 closes the existing
Frame payload migration with a correlated Protobuf packet, accepted-sequence acknowledgement and
Snapshot resynchronization, while both legacy Frame symbols and all asset channels remain intact.
T-325 then closes the first bounded second-stage Replay enhancement: immutable 0.25x–4x realtime
speed control uses an absolute scaled timeline, while pause, checkpoint, seek and Replay UI remain
separately scoped. T-326 closes the next slice with bounded applied-viewport Frame hash comparison,
first-divergence evidence and an injectable stricter projection, without changing Recording v1.
T-327 closes an explicit Recording v2 checkpoint marker and bounded native snapshot
materialization at safe VT parser boundaries. It keeps v1 and legacy delegates compatible and does
not add pause or Replay UI. T-328 closes deterministic backend seek on those materialized
checkpoints, including inclusive target semantics, Event cursor coordination and realtime
rescheduling from the requested offset. T-329 closes the next portable Replay slice with a
bounded content-addressed Recording v2 RGBA asset bundle. ReplayBackend serves an exact recorded
asset identity before the native cache while preserving v1 bytes and old-delegate fallback.
T-330 now versions the live decoded-RGBA boundary as one atomic Graphic Asset Packet v1. New Dart
prefers the packet when available, old native libraries retain the exact metadata/copy fallback,
and old Dart continues using both unchanged legacy symbols. The complete repository gate passes.

## Evidence Behind the Decision

- The reviewed automated xterm slice is closed: the current audit contains
  `Covered` and explicit `Deferred` decisions, with no remaining `Gap` row.
- Bash and fish shell integration and kitty keyboard handling exist in the
  runtime, so the old M1/M3 descriptions are no longer accurate as future-only
  work.
- `ShellActionRegistry`, `LocalWorkspaceRepository`, `ProfileRepository`, and
  `SessionBootstrapService` prove that local workspace expansion is already an
  implemented product surface.
- CI runs the repository verification entrypoint on Ubuntu and macOS, but only
  macOS has the desktop integration path. This is useful portability evidence,
  not proof of Linux desktop support.
- Before T-304, `native/core/src/session.rs` was 10,303 lines and still owned
  cache, damage, viewport-shift and snapshot-fallback decisions directly.
- The structured frame corpus now covers snapshot, delta, graphics, blocks and
  hyperlinks, while JSON/Protobuf parity and native session regressions protect
  the unchanged external contract.
- `FrameBuildContext` now makes the common terminal and viewport inputs
  explicit, while `session/frame/snapshot.rs` owns contiguous and folded
  Snapshot row construction.
- `session/frame/delta.rs` now owns Delta candidate scanning, row comparison,
  cache updates and damage construction behind an explicit `DeltaFrameContext`.
- `session/frame/projection.rs` now owns folded-block display projection and
  source/display row mapping.
- `session/frame/graphics.rs` now owns raw and folded graphics placement,
  viewport geometry, Kitty placeholder scanning and asset snapshot gathering.
- Iteration 02 reduced `session.rs` from 10,303 to 8,930 lines and passed the
  complete macOS gate with all six deterministic benchmark hashes unchanged.
- `TerminalRuntimeController` already exposes successful user-input and resize
  streams plus Frame/Exit events, but raw PTY output remains internal to native
  `TerminalSession`; the recorder must add an explicit bounded seam rather than
  treating Frames as output bytes.
- `terminal_recording.dart` and the fixed v1 fixture establish schema version,
  session id, sequence, monotonic offset, all five MVP event kinds, structured
  format errors and explicit `record`/`redact` input policy.
- `session/recording.rs` and `TerminalLiveRecorder` now connect that contract to
  pre-parser PTY output, successful input/resize calls and observed child exit,
  with 4,096-event and 8 MiB raw-payload limits plus all-or-error overflow.
- `TerminalReplayBackend` and the native headless replay session now reuse the
  production parser/Frame path with realtime and no-delay scheduling, stable
  repeated output, recorded geometry and historical side-effect suppression.
- `TerminalReplayBackend` now also validates an immutable 0.25x–4x speed and scales realtime
  timers from absolute Recording v1 offsets, avoiding accumulated interval-rounding drift while
  leaving no-delay playback synchronous.
- `TerminalReplayFrameHashComparator` now applies bounded Snapshot/Delta traces through independent
  viewport states, reports the first hash or frame-count divergence, and reuses the existing
  deterministic benchmark projection by default while allowing a stricter injected hasher.
- `TerminalRecordingCheckpointPlanner` now upgrades validated recordings explicitly to v2, inserts
  deterministic initial/periodic/final markers only at safe control-sequence boundaries and leaves
  live native capture on v1.
- Optional replay checkpoint FFI captures session-local `TerminalSnapshot` state under 64-entry and
  32 MiB bounds. Restore forces a full Snapshot Frame while preserving Runtime Event sequence
  monotonicity; older delegates ignore markers and continue replaying the ordered output stream.
- ReplayBackend seek restores the latest materialized checkpoint at or before an inclusive target,
  fast-forwards only through that offset, buffers pre-seek events, drains seek-regenerated lifecycle
  events and resumes realtime playback from the target on the absolute scaled timeline.
- `TerminalRecordingGraphicAssetBundler` explicitly upgrades a validated recording to v2, stores
  at most 128 asset identities and 32 MiB of unique decoded RGBA by SHA-256 content address, and
  rejects corrupt, missing, duplicate or oversized records without exposing a partial bundle.
- ReplayBackend serves a defensive copy for an exact bundled `(assetId, assetVersion)` before the
  optional native graphic-asset delegate, while absent keys retain the existing fallback.
- Graphic Asset Packet v1 captures exact session/asset/version identity, dimensions and decoded
  RGBA under one native state lock. Dart enforces a 100 MiB bound and only falls back to the old
  metadata/copy pair when the optional packet symbol is absent.
- Workspace schema v3 now carries stable `id`/`name`/`projectPath` identity,
  rewrites legacy unversioned/schema-v1/schema-v2 layouts, preserves unsupported
  future Workspace or descriptor documents, and keeps malformed current data on
  the existing quarantine/repair path.
- Recent Workspace index v1 tracks the current identity and a bounded UTC-ordered
  recent list while independent collection documents prevent projects from
  overwriting one shared layout file.
- `LocalSessionWorkspaceCodec` now maps live `SessionState` topology to local
  relaunch intent and maps persisted pane IDs to newly launched runtime session
  IDs during bootstrap. Restore failures are visible and dismissible.
- `TerminalSessionDescriptor` now separates persisted descriptor identity from
  runtime session IDs and captures command/cwd/title/creation/exit/restart metadata.
  Workspace v2 migrates v1 intents, drops environment values, and protects future
  descriptor versions from quarantine or overwrite.
- `LocalSessionRecordingRepository` now allocates Workspace-partitioned Recording v1
  files, performs atomic canonical NDJSON writes and validates reads. `SessionController`
  updates `recordingPath` only after durable save, retains complete stopped recordings for
  retry, and finalizes capture before close, Workspace switch, observed exit or disposal.
- The title bar and command palette share `toggleSessionRecording`; their Start,
  Stop/Save, Retry Save and busy states are semantic, theme-derived and default to redacted
  input capture.
- `RuntimeCapabilities::current` and `ianvs_runtime_capabilities_json` now expose a
  deterministic compiled-core manifest. `PtyRuntimeCapabilities` validates schema, contract,
  bounds and duplicates while retaining additive unknown v1 feature ids.
- `NativePtyBindings` resolves the capability symbol optionally, so older dynamic libraries
  continue through the pre-existing feature-probing and session paths.
- `RuntimeEventBatchV1` assigns per-session sequence/timestamp before bounded queue eviction;
  Dart validates the versioned envelope and detects loss, reordering and cross-session data.
- `NativePtyBackend` probes the Event Envelope symbol optionally and keeps the legacy event-array
  path for older native libraries.
- `TerminalRuntimeController` and `TerminalReplayBackend` prefer the optional SessionConfig v1
  symbols, while the old Profile-shaped live/replay create paths remain compatibility-tested.
- `TerminalJsonRequestClient`, `TerminalDiagnosticsClient` and `TerminalLiveRecorder` share one
  v1-preferred Session Request transport. Response identity is checked exactly and replay retains
  the capability only when its delegate exposes it.
- Runtime Event Envelope v1 now maps OSC 52 text reads to `HostRequestV1`; Dart checks the inner
  identity against outer session/sequence/timestamp and returns bounded `HostResponseV1` through
  an optional symbol. Native consumes a matching response once and retains at most 64 pending
  identities, while legacy event polling remains unchanged.
- Diagnostic Event v1 now carries `frame_stats` and `session_stats` through correlated Runtime
  Envelope v1 diagnostics. Dart validates session/name identity and bounds, runtime and benchmark
  consumers prefer the optional symbol, ReplayBackend delegates it, and both legacy debug-stat
  symbols remain available for either upgrade direction.
- `KNOWN_ISSUES.md` still correctly excludes SSH, plugins, native renderer, and
  broad cross-platform claims.

## Execution Order

1. Keep documentation and execution targets machine-verifiable.
2. Treat Frame Pipeline Iteration 02 as closed evidence; reopen it only for a
   concrete regression or separately scoped follow-up.
3. Treat the verified T-309 Recording Metadata/Event v1 contract as the stable
   Iteration 03 input; reopen it only for a concrete codec or privacy regression.
4. Treat the verified T-310 bounded raw PTY output seam and live recorder as
   closed evidence; reopen them only for a concrete capture regression.
5. Treat T-311 and Recording / Replay MVP as closed evidence; reopen them only
   for a concrete replay, privacy or deterministic-output regression.
6. Treat T-312 through T-317 as the verified Workspace schema, restore, Session
   Descriptor, collection identity, Recent index, project selection and safe
   runtime switching plus recording lifecycle baseline. Keep process recovery,
   recording library, Replay UI and broad Workspace management out of scope.
7. Treat T-318 Runtime Capabilities v1, T-319 Runtime Event Envelope v1, T-320 SessionConfig v1,
   T-321 Session Request/Response v1, T-322 Host Request/Response v1 for OSC 52, T-323 Diagnostic
   Event v1 and T-324 Terminal Frame Packet v1 as closed, backward-compatible Runtime Contract
   work. Treat T-330 Graphic Asset Packet v1 as the closed decoded-RGBA migration.
   Keep the old event array, Profile-shaped create symbols, discriminated request symbol,
   debug-stat symbols, legacy Frame symbols and graphic metadata/copy pair until a separately
   approved removal window; scope other Host operations independently.
8. Treat T-327 checkpoint materialization, T-328 backend seek and T-329 portable graphic assets as
   bounded Replay foundations. Keep pause/scrubber UI, live asset capture product wiring, full Host
   Request/Response capture, remote, plugins and renderer expansion outside these slices.
9. Start Linux or Windows product work only from real target-host evidence in
   T-065; CI package tests alone do not satisfy that gate.

## Acceptance Loop

Every iteration should use this loop:

1. Create or select one task under `docs/tasks/` with a single verifiable goal.
2. Add the smallest failing regression that represents the user-visible or
   contract-level gap.
3. Implement only the task scope.
4. Run the task's focused tests, then `make format-check`, `make analyze`, and
   `make test`.
5. Run `make verify` for cross-boundary, lifecycle, persistence, runtime, or
   release-facing changes.
6. Update the task result and evidence. If a GUI-only gate cannot run, record
   the exact blocker instead of treating automation as equivalent evidence.

## Fresh Verification Baseline

The target calibrated on 2026-07-20 was re-verified through T-330 on 2026-07-21 with
`make format-check` and the complete `make verify` entrypoint:

- All Dart files were formatter-clean and all static analysis gates passed.
- Vendored Rust passed 1,733 tests; native core passed 131 unit tests, 1 OSC corpus,
  1 Runtime Capabilities integration, 2 Diagnostic Event integrations, 1 Runtime Event Envelope
  integration, 2 Terminal Frame Packet integrations, 1 Graphic Asset Packet integration,
  1 SessionConfig v1 integration,
  1 Session Request/Response v1 integration,
  2 Host Request/Response integrations, 518 session tests, and 3 vttest regressions.
- `ianvs_pty` passed 62 tests; `ianvs_terminal` passed 549 tests with 1
  intentional skip; documentation contracts passed 12 tests.
- The selected example CI application suite passed 1,100 component/widget tests,
  followed by 4 macOS smoke tests and 46 real PTY tests.
- The macOS desktop build succeeded and all 17 Runner XCTest cases passed.
- All six benchmark correctness rows report `hash_match=true` in
  `build/bench-results-ci/20260721T125256Z`.

The verification run also exposed and closed three current-code drifts:
formatter drift in the OSC 72 test, stale command-palette smoke copy, and a
real OSC 99 notification-menu regression. Their evidence is recorded in
T-299, T-300, and T-301 under `docs/tasks/verification-gates/`.

Iteration 01 then established the explicit compatibility baseline in T-302:
six-layer capability evidence, real shell and alternate-screen TUI fixtures,
Unicode width/cursor proof, and observable resize replay/truncation boundaries.
That evidence closed the prerequisite without prematurely starting the
frame-pipeline or recording/replay iterations at that time.

T-303 then installed Homebrew `vttest` 20251205, serialized the PTY-heavy VT220
slice, synchronized GUI focus with viewport mounting, and passed the complete
real macOS GUI + PTY + `vttest` release gate. This closes the supplemental host
lane on the current machine while preserving its external-dependency status on
other hosts.

T-304 then started Iteration 02 with a bounded, schema-preserving slice. It
expanded frame golden coverage, extracted cache/damage/row-shift/fallback logic
to `session/frame/damage.rs`, reduced `session.rs` from 10,303 to 9,814 lines,
kept all six benchmark hashes stable and passed the complete repository gate.

T-305 then introduced the common private `FrameBuildContext` and moved both
contiguous and folded Snapshot construction to `session/frame/snapshot.rs`.
It reduced `session.rs` to 9,696 lines; all six pre/post benchmark correctness
files and configured timing metrics remained stable. It intentionally left
Delta, Display Projection and Graphics Projection to separate follow-up slices.

T-306 then moved Delta candidate scanning, cache comparison/update and dirty
range construction to `session/frame/delta.rs` behind `DeltaFrameContext`. It
reduced `session.rs` to 9,630 lines; independent Delta regressions, the complete
serialized native suite, 35/35 golden/parity checks and all six deterministic
benchmark comparisons passed. Display Projection and Graphics Projection remain.
The final repository gate passed and wrote benchmark evidence to
`build/bench-results-ci/20260721T021112Z`.

T-307 then moved folded-block display projection construction and every
source/display row mapping primitive to `session/frame/projection.rs`. It reduced
`session.rs` to 9,468 lines; 114 native unit tests, the complete serialized
session suite, 35/35 golden/parity checks and all six deterministic benchmark
comparisons passed. Graphics Projection is the last Iteration 02 slice.
The final repository gate passed and wrote benchmark evidence to
`build/bench-results-ci/20260721T022641Z`.

T-308 closed Iteration 02 by moving graphics placement construction, folded
projection, viewport geometry, Kitty placeholder scanning and asset snapshot
gathering to `session/frame/graphics.rs`, while Session retained cache lifecycle
ownership. It reduced `session.rs` to 8,930 lines; 116 native unit tests, the
complete serialized session suite, 35/35 golden/parity checks and all six
deterministic benchmark comparisons passed. The final `make verify` passed and
wrote byte-identical benchmark evidence to
`build/bench-results-ci/20260721T024435Z`.

T-309 then started Iteration 03 with the versioned Recording Metadata/Event v1
contract. The canonical NDJSON codec models SessionStarted, PtyOutput,
UserInput, Resize and SessionExited with contiguous sequence and monotonic
offset, ignores additive unknown fields, returns structured corruption/version
errors and makes exact versus redacted input an explicit metadata decision.
Seven focused codec/privacy tests, the 492-test package suite, documentation
contracts and the complete repository gate passed. All six benchmark correctness
hashes remained byte-identical in `build/bench-results-ci/20260721T030204Z`.
T-309 closed the format slice; live capture remained separate and is now closed
by T-310.

T-310 then connected that contract to the real native session boundary. Raw PTY
bytes are captured before parsing, while successful input, resize and observed
child exit share one ordered recorder. The 4,096-event / 8 MiB payload limits
fail with a structured capacity error instead of exporting partial data. Native
buffer tests, a real PTY regression, 495 package tests and the complete repository
gate passed; all six benchmark correctness hashes remained byte-identical in
`build/bench-results-ci/20260721T032057Z`. T-310 is closed and ReplayBackend is
the next slice.

T-311 now implements that slice with a headless native session, optional FFI
capability and a `PtySessionBackend`-compatible Dart scheduler. Realtime and
no-delay focused tests pass; repeated sessions produce byte-stable Frames,
historical input is never executed, and clipboard/OpenURL effects are
suppressed. The final repository gate passed, including 1,063 example tests,
4 macOS smoke tests, 46 real PTY tests and 16 Runner XCTest cases. Benchmark
evidence is in `build/bench-results-ci/20260721T035353Z`; all six deterministic
correctness rows remain byte-identical to the T-310 baseline. T-311 and
Iteration 03 are closed, and Local Workspace stability is now active.

T-312 and T-313 then closed the first Local Workspace stability slice. At that
checkpoint, persisted layouts carried schema v1, migrated the prior unversioned
shape, and preserved future-version files. When `workspace.restoreLayout` is enabled, the real
`SessionController` restores nested topology by relaunching new sessions,
serializes later changes, and exposes skipped relaunches in a dismissible product
error. The final repository gate passed with 1,072 example CI tests, 4 macOS
smoke tests, 46 real PTY tests and 16 Runner XCTest cases. Benchmark evidence is
in `build/bench-results-ci/20260721T041743Z`; all six correctness rows are
byte-identical to the T-311 baseline through the deterministic columns. The
Workspace lane remains active for the richer Session Descriptor, project/recent
Workspace identity and recording association.

T-314 then added the independent Session Descriptor v1 contract and advanced
Workspace persistence to schema v2. Legacy `sessionIntent` leaves migrate to
descriptors; command, cwd, title, UTC creation time, exit state, optional recording
path and restart policy survive live capture/restore, while environment values are
never persisted. Focused descriptor/repository/codec tests pass 14 tests, the full
Workspace plus `SessionController` regression passes 135 tests, and fatal-info
analysis is clean. The final `make verify` passes 1,077 example CI tests, 4 macOS
smoke tests, 46 real PTY tests and all 16 Runner XCTest cases. Benchmark evidence
is in `build/bench-results-ci/20260721T044538Z`; all six deterministic rows report
`hash_match=true`. T-314 is closed, and project/Recent Workspace identity is next.

T-315 now advances persistence to Workspace schema v3 with required stable identity,
deterministic absolute project-path IDs, independent collection documents and Recent
index v1. Legacy layouts migrate to the default identity without destructive deletion,
and controller capture retains the loaded identity. Focused identity/repository/codec
coverage passes 23 tests, the full Workspace plus `SessionController` regression passes
146 tests, and fatal-info analysis is clean. The final `make verify` passes 1,088 selected
example CI tests, 4 macOS smoke tests, 46 real PTY tests and all 16 Runner XCTest cases.
Benchmark evidence is in `build/bench-results-ci/20260721T051058Z`; all six deterministic
rows report `hash_match=true`. T-315 is closed, and project selection plus safe runtime
Workspace switching is next.

T-316 now makes that collection product-visible. The title bar and native macOS
`File > Open Project…` / `Command-O` command share a directory-only picker and Recent
Workspace switch path. Target sessions are prepared before activation, old PTYs close only
after success, and load, launch or activation failure preserves the previous Workspace.
Focused repository/controller/widget coverage passes 98 tests, the complete Workspace,
`SessionController` and Shell regression passes 487 tests, and fatal-info analysis is clean.
The direct package gate passes 1,149 example tests with one intentional skip; the final
`make verify` passes 1,094 selected example CI tests, 4 macOS smoke tests, 46 real PTY tests
and all 17 Runner XCTest cases. Benchmark evidence is in
`build/bench-results-ci/20260721T053640Z`; all six deterministic rows report
`hash_match=true`. T-316 is closed; its then-next recording lifecycle association
slice is now closed by T-317 below.

T-317 now connects the verified native recorder to product lifecycle and Workspace
association. Recording starts with redacted input, saves canonical v1 NDJSON atomically,
and updates the Session Descriptor only after durable persistence. A failed write retains
the complete stopped recording for retry without a second native stop; pane/tab close and
Workspace switching refuse to destroy the previous runtime state until saving succeeds.
Observed exit and controller disposal perform best-effort finalization. Eight focused tests,
the 123-test affected regression and fatal-info analysis pass. The final `make verify` passes
1,102 selected example CI tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner
XCTest cases. Benchmark evidence is in `build/bench-results-ci/20260721T062119Z`; all six
deterministic rows report `hash_match=true`. T-317 is closed; recording library, Replay UI,
checkpoint/seek and broad Workspace management remain separately deferred.

T-318 now starts the Runtime Contract phase with Runtime Capabilities v1. Native core
returns one deterministic schema/contract/version/feature manifest through the optional
`ianvs_runtime_capabilities_json` symbol, and Dart exposes a typed, bounded decoder.
Additive v1 fields and unknown feature ids remain forward-compatible; unsupported schema
versions fail explicitly. A binding without the symbol returns no manifest while existing
session paths remain usable. Six new Dart regressions and one native contract/FFI test pass.
The final repository gate passed 1,100 selected example CI tests, 4 macOS smoke tests,
46 real PTY tests and 17 Runner XCTest cases. Benchmark evidence is in
`build/bench-results-ci/20260721T064315Z`, with all six correctness hashes unchanged.
T-318 is closed; this slice does not alter or remove any existing wire.

T-319 then inventories the FFI boundary and defines the closed Runtime Envelope v1 message
taxonomy plus bounded Event Batch v1. Native events receive session-scoped sequence and timestamp
before queue admission, so eviction and rejection remain observable through the cursor and drop
count. Dart accepts additive fields and unknown event names but rejects malformed schema, class,
identity, ordering or size with structured errors. `NativePtyBackend` prefers the optional new
symbol and retains the legacy event array for old libraries. The final repository gate passed
1,100 selected example CI tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner XCTest
cases. Benchmark evidence is in `build/bench-results-ci/20260721T070651Z`; all six correctness
rows report `hash_match=true`. T-319 is closed; SessionConfig/Profile wire remains the separately
scoped migration that T-320 takes up below.

T-320 then defines the product-neutral SessionConfig v1 contract with exact schema/contract
identity, bounded launch/config collections and a 1 MiB encoded ceiling. Native live and replay
entrypoints map the validated payload to the internal `TerminalProfile`; Runtime Capabilities
advertises the optional symbols. Dart prefers v1 through explicit backend capabilities, while
the legacy Profile-shaped encoder and old symbols remain covered in both upgrade directions.
The real Dart/native bridge creates live and replay v1 sessions. The final repository gate passed
1,100 selected example CI tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner XCTest
cases. All six benchmark correctness rows remain true in
`build/bench-results-ci/20260721T073713Z`. T-320 is closed; old-wire removal is not authorized by
this compatibility slice.

T-321 then defines bounded, correlated Session Request/Response v1 envelopes for the synchronous
Dart-to-native generic command channel. Native dispatch returns stable structured errors for bad
schema, contract, identity, operation and runtime failure; Dart rejects correlation drift and
prefers the optional `ianvs_session_request_v1_json` symbol through one shared transport. JSON,
diagnostics and live recording clients use that transport, replay delegates the same capability,
and the exact legacy request object remains covered. Strict native/Dart analyses, focused Rust
FFI tests, 37 PTY contract/backend tests, 22 terminal client/replay tests and 12 documentation
contracts pass. The final `make verify` returns zero with 48 PTY tests, 509 terminal tests plus one
intentional skip, 1,100 example tests, 4 macOS smoke tests, 46 real PTY tests and 17 XCTest cases.
All six benchmark rows retain `hash_match=true` in
`build/bench-results-ci/20260721T082801Z`. T-321 is closed; Host Request/Response and other wire
migrations remain separately scoped.

T-322 then defines the native-to-product Host Request/Response v1 contract and deliberately uses
only OSC 52 text clipboard reads as its first operation. Runtime Event Envelope v1 carries the
correlated request; Dart validates outer/inner identity and uses the optional
`ianvs_session_host_response_v1_json` symbol. Native bounds pending identities at 64, validates
canonical UTF-8 Base64, consumes success/denial/error once and rejects duplicates. Legacy event
polling and direct PTY replies remain covered in both upgrade directions. Strict analyses, 2 Rust
contract tests, 52 PTY tests, 511 terminal tests with 1 intentional skip and 12 documentation
contracts pass. The complete repository gate also passes 1,100 example tests, 4 macOS smoke tests,
46 real PTY tests and all 17 XCTest cases. All six benchmark hashes remain true in
`build/bench-results-ci/20260721T085840Z`. T-322 is closed; other Host operations, Frame,
diagnostic and asset migrations remain separately scoped.

T-323 then defines the `diagnostic` specialization of Runtime Envelope v1 for the existing
`frame_stats` and `session_stats` metrics. Native assigns per-session sequence and timestamp only
when a diagnostic materializes, preserving Frame's one-shot take semantics. Dart validates the
bounded envelope and exact session/name identity, while runtime, replay and benchmark paths prefer
the optional symbol and retain both legacy debug-stat fallbacks. Strict analyses, 3 focused Rust
tests, 55 PTY tests, 513 terminal tests with 1 intentional skip and 12 documentation contracts
pass. The complete repository gate also passes 1,100 example tests, 4 macOS smoke tests, 46 real
PTY tests and all 17 XCTest cases. All six benchmark hashes remain true in
`build/bench-results-ci/20260721T094417Z`. T-323 is closed; other Host operations, Frame and asset
migrations remain separately scoped.

T-324 then defines Terminal Frame Packet v1 around the unchanged `terminal-frame-diff-v1`
Protobuf. Native adds exact session identity, a per-session sequence, timestamp and an optional FFI
take that accepts the last Dart-accepted sequence; stale acknowledgement forces the next Frame to
a Snapshot. Dart validates the bounded packet and ordering before application, never retries a
malformed one-shot Frame through legacy transport in the same refresh, and preserves old
Protobuf/JSON fallback plus replay. Strict analyses, 2 focused Rust Frame Packet tests, 56 PTY
tests, 519 terminal tests with 1 intentional skip and 12 documentation contracts pass. The
complete repository gate also passes 1,100 example tests, 4 macOS smoke tests, 46 real PTY tests
and all 17 XCTest cases. All six benchmark hashes remain true in
`build/bench-results-ci/20260721T101427Z`. T-324 is closed; other Host operations, asset migrations
and any old-wire removal remain separately scoped.

T-325 through T-327 then close three bounded second-stage Replay foundations. Realtime playback
supports an immutable 0.25x–4x speed on the absolute timeline; applied-viewport Frame comparison
reports the first deterministic divergence; and Recording v2 checkpoint markers materialize
session-local native snapshots only at safe VT parser boundaries. V1 recordings and old delegates
remain compatible, native retention is bounded to 64 entries and 32 MiB, and restore preserves the
monotonic Runtime Event sequence. The final T-327 gate passes 518 native session tests, 57 PTY
tests, 537 terminal tests with one intentional skip, 1,100 example tests, 4 macOS smoke tests, 46
real PTY tests and all 17 XCTest cases. All six benchmark hashes remain true in
`build/bench-results-ci/20260721T111849Z`. At that boundary, seek, Replay UI and portable graphics
asset bundles remained separately scoped.

T-328 then closes deterministic ReplayBackend seek over those materialized checkpoints. It restores
the latest eligible checkpoint, fast-forwards through an inclusive monotonic target, preserves
pending pre-seek events, drains only seek-regenerated lifecycle and resumes realtime playback from
the requested offset on the absolute speed-scaled timeline. The focused ReplayBackend suite passes
20 tests, including a real native-core Frame proof. The complete repository gate passes 518 native
session tests, 57 PTY tests, 543 terminal tests with one intentional skip, 1,100 example tests, 4
macOS smoke tests, 46 real PTY tests and all 17 XCTest cases. All six benchmark hashes remain true in
`build/bench-results-ci/20260721T115621Z`. Pause, scrubber/Replay UI and portable graphics asset
bundles remain separately scoped.

T-329 then closes portable decoded graphic assets without changing live Recording v1 or Frame
wire. Canonical v2 files deduplicate identical RGBA by dimensions-and-bytes SHA-256, cap one bundle
at 128 identities and 32 MiB of unique decoded bytes, reject corruption and missing references,
and let ReplayBackend resolve an exact recorded key before native fallback. The focused recording,
checkpoint and replay set passes 39 tests. The complete repository gate passes 518 native session
tests, 57 PTY tests, 549 terminal tests with one intentional skip, 12 documentation contracts,
1,100 example tests, 4 macOS smoke tests, 46 real PTY tests and all 17 XCTest cases. All six
benchmark hashes remain true in `build/bench-results-ci/20260721T122846Z`. Pause, Replay UI, live
asset capture product wiring and full Host Request/Response recording remain separately scoped.

T-330 then versions the live native-to-Dart decoded RGBA read without changing Frame or Recording
wire. Native returns one identity/dimensions/RGBA Protobuf packet from one locked cache lookup;
Dart validates schema, envelope, exact request identity, dimensions and the 100 MiB payload bound.
The packet-capable path is preferred, a malformed packet never downgrades in the same call, and
both legacy metadata/copy symbols remain available in either upgrade direction. Strict analysis,
62 PTY tests, two focused Rust integrations and clippy pass. The complete repository gate also
passes 518 native session tests, 549 terminal tests with one intentional skip, 1,100 example
tests, 4 macOS smoke tests, 46 real PTY tests and all 17 XCTest cases. All six benchmark hashes
remain true in `build/bench-results-ci/20260721T125256Z`. T-330 is closed; file downloads, live
Recording capture, remote transport and old-wire removal remain separately scoped.

## Direction Boundaries

- The May P0-P5 ledger remains historical closure evidence; it does not prove
  that later July changes pass today.
- Historical M1-M5 sections in `ROADMAP.md` remain useful for intent and
  dependency context, but no longer define the live implementation state.
- T-064's candidate row-range annotation API was not implemented as written;
  later terminal block work uses `TerminalBlock` frame data and viewport
  rendering. Any future generic annotation API needs a new focused decision,
  not an assumption that T-064 already shipped.
- New protocol breadth should be tied to a compatibility gap, product need, or
  focused task rather than continuing phase numbering by inertia.
- Existing viewport `InstantReplayStore` is not evidence that deterministic raw
  session recording or ReplayBackend already exists.
- Local Workspace stabilization is closed through T-317. Runtime Contract stability remains
  active through the closed T-318/T-324 and T-330 slices, matching the handoff
  phase without reopening completed MVP work or broadening the next migration.
- Workspace restore means deterministic relaunch from saved intent with new
  session IDs; it never means that the original PTY process survived restart.

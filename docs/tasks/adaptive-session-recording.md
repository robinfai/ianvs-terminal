# Adaptive session recording delivery

## Goal

Deliver the four user-approved batches for macOS daily use and durable,
manually started, per-session sampled visual recordings with command timelines.

## Scope

1. **Scheme validation**: adaptive structured screen sampling, all live deltas
   applied before sampling, storage deltas relative to the last stored sample,
   keyframes and independent hook events; measure shell/log/TUI workloads.
2. **Capture and replay**: bounded continuous writing, explicit start/stop,
   restart/open, asynchronous seek, command navigation and interrupted-prefix
   recovery. Target at most ten seconds of uncommitted tail loss; test process
   failure and system/durability behavior separately.
3. **Library and search**: index commands and retained screen text across files;
   filter by host/date/command; protect recordings marked Keep and active files;
   apply both age and aggregate capacity retention limits to ordinary files.
4. **Long-running acceptance**: more than 24 actual hours with shell, sustained
   logs, TUI, idle intervals and SSH; measure memory, CPU, disk, seek/search,
   failure recovery and impact on normal input/rendering.

The first release includes all four batches. Passing a prototype or accelerated
24-hour logical timeline does not establish delivery or real-duration acceptance.

## Non-goals

- Lossless raw PTY-output history, raw keystroke recording or bitmap video.
- Automatic recording, synchronized multi-pane recordings, cloud sync or iOS
  expansion, renderer replacement, Project Workspace or agent orchestration.
- Reading, importing, migrating, rewriting or deleting old schema 1 NDJSON.
  Old files remain on disk; new retention must never select them.

## Files In Scope

- `native/core/src/recording/`, native session integration and native tests.
- `packages/ianvs_terminal/lib/src/recording/` and matching runtime/transport/tests.
- `example/lib/features/recording/`, sessions, replay/library UI and tests.
- Generated `packages/ianvs_terminal_core` mirrors through the existing sync tool.
- Recording benchmarks, verification entrypoints and authoritative docs.

## Functional Acceptance

- A user can manually start and stop one session recording and reopen it after
  restarting the app. Recording starts with the current complete visible state.
- Sampling frequency adapts to activity/resources. Unsampled live updates still
  reach the sampling state. Hook command/argument/time/context events have their
  own ordered timeline and are never dropped to reduce visual sampling frequency.
- Sampled text, styles, cursor, links, resize, alternate screen and graphics
  replay correctly; image bytes are retained before live cache eviction.
- Commands navigate to related sampled frames. Missing hooks and sampled-output
  gaps are described honestly. Search covers only retained commands/screen text.
- Writes, open/seek, search and graphics have bounded work/memory; all sessions
  share a queue budget. Disk/queue failure is visible, retaining a verified prefix.
- Abnormally terminated recordings are identifiable and recoverable. Recovery
  never executes historic commands, opens SSH connections or invokes host actions.
- Retention has configurable age/capacity, preserves Keep/active files, updates
  search indexes, and stops new capture when protected files exhaust the budget.

## Verification Commands

Follow [TESTING](../TESTING.md) and [ACCEPTANCE](../ACCEPTANCE.md). Commands are
added as each executable entrypoint is implemented; no absent entrypoint counts
as evidence.

```bash
cargo test --manifest-path native/core/Cargo.toml --test sampled_recording_test --test sampled_recording_storage_test --test sampled_recording_timeline_test --test sampled_recording_session_test --test sampled_recording_request_test
flutter test packages/ianvs_terminal/test/sampled_recording_capture_test.dart
cargo run --release --manifest-path native/core/Cargo.toml --example sampled_recording_bench -- build/recording_bench/adaptive/results.json
dart test test/docs_contract_test.dart
dart run tools/sync_terminal_core.dart
make verify
```

## Manual QA

Exercise actual macOS local shell and SSH, start midway through a populated TUI,
resize, copy/search/seek, interrupted capture, recovery, Keep, retention and
cross-recording filters. Check keyboard focus, large text, light/dark themes,
screen-reader labels and unchanged terminal input behavior. Use controlled test
files for retention/failure cases. Store logs/screenshots/metrics under `build/`.

## Done When

All four batches pass relevant automated and real UI checks; more-than-24-hour
wall-clock evidence exists on the final implementation; full `make verify`
passes; current-format/product/architecture documentation matches shipped code.

## Risks / Follow-ups

- Initial sampling intervals, keyframe cadence, queue sizes, retention defaults
  and latency gates are provisional until representative measurements establish
  them. Record device/OS and workload alongside any numeric gate.
- Ten-second recovery is a target, not proof of power-loss durability.
- The app and its recording tests now use schema 2; full product acceptance remains open.
- Prototype correctness must cover scrollback eviction at 8,000 lines, Unicode,
  boundary frames, metadata-only updates, hyperlinks and graphics versions.

## Implementation checkpoint — native capture and storage

Implemented, with focused coverage:

- Adaptive structured-state sampling and pure replay, including native VT oracle
  comparisons and scrollback eviction. Native complete snapshots account for
  changed rows instead of treating every observation as a full repaint.
- Checksummed streaming `.trailrec` bundles, synchronized image blobs, bounded
  background queue, interrupted-prefix scan and cancellable disk-index seek.
  See [sampled format draft](../recording/FORMAT_SAMPLED.md).
- Native Session capture independent of UI polling/damage, hooks before the UI
  queue, existing shell context at start, and stop/close/child-exit final frames.
- Focused suites: 16 sampler, 15 storage (including a child-process helper),
  6 timeline and 5 native capture tests; session architecture guards also pass.
  The complete native run passed 997 tests with five conditional tests ignored;
  strict Clippy and 15 documentation contract tests passed on this checkpoint.
- Baseline full verification reached the example app suite and failed eight
  tests: macOS signer fixture, iPhone keyboard input bar and six exact visual
  goldens. Logs and image differences are local build/test artifacts. This is
  not a green repository baseline; later native changes also require full rerun.

A subsequent control checkpoint adds asynchronous idempotent capture requests,
a bounded registry queryable after session close, explicit writer settlement,
and a typed Dart client. The shared status fixture and failure tests cover lost
replies, correlation errors, retry, stop during start, late stop, existing-file
protection, timeout and cancellation. Filesystem creation no longer holds the
session capture lock. These interfaces are staged; the app has not switched.

Control-checkpoint verification: 1,007 native tests passed, five conditional tests
were ignored; 83 canonical/standalone/client-regression Dart tests and targeted
fatal-infos analysis passed. The native control suite includes six request
lifecycle tests and two unit contract/close-gate tests. A flaky SSH fixture now
publishes its complete PID marker atomically. A real-PTY timeout observed during
broad runs led to a child-ready barrier, waiting on the persisted command-finish
event instead of a bootstrap-dependent count, and richer failure diagnostics.
The updated five-test capture suite passed its final rerun; strict Clippy,
15 documentation contract tests and generated-source verification also passed.

Still required before batch 2 acceptance: switch exact-current native/Dart
capabilities and app start/stop/status with ownership-aware handoff, pure structured
Flutter replay and cancellable seek jobs, incremental index publication, durable
failure UI, representative whole-container/asset/RSS/input-latency measurements.
Batch 3 library/search/retention and batch 4 real >24-hour/product/SSH/system
failure validation remain open. Legacy app entrypoints are unchanged so far.


## Application integration checkpoint — in progress

The app now routes manual capture, state polling, stop, observed exit, rejected
close continuation and shutdown through sampled capture identities. Saved replay
uses complete structured screens, one in-flight/coalesced seek, retained graphics
and bounded command pages; it never creates a replay PTY or executes host actions.
Native capabilities now advertise recording schema 2.

A separate `recordings-v2` library persists reservations before native dispatch,
retains writer/viewer leases until actual completion, isolates corrupt/unknown
manifests and recovers orphan bundles protected by Keep. Native metadata checks
protect deletion identity. Age/capacity retention is implemented at the repository
level with provisional 30-day/20-GiB defaults; settings and library controls remain.
Only managed bundle paths can currently be opened by the application picker.

Verification so far: 24 new Dart/application tests passed, including an actual PTY
capture → stop → close → reopen → seek/command round trip; four layout tests also
passed with repository fonts at 1,100 px and 390 px/2× text in both themes. Screenshots
under `build/recording_bench/adaptive/replay-*.png` were visually inspected. Three
native file-service tests plus ABI/capabilities checks passed; strict native Clippy
passed. These are focused checks, not full `make verify` evidence.

Before batch 2 acceptance, port the old session/shell recording tests to the new
contracts, exercise the actual full macOS app/player and installed shell/SSH hooks,
finish fast open/incremental cache publication and validate whole-pipeline resource
cost. The file reader currently scans on every open. External new-format bundle
open/import still needs a defined safe ownership path. Keep/capacity settings,
cross-recording search, system-failure evidence and real >24-hour acceptance remain.


## Application regression checkpoint

The session/shell tests now exercise schema 2. Coverage includes simultaneous
starts, strict capture identity, retries after lost replies, transfer/close races,
split-pane continuations, shutdown settlement, cancellation that retains file
ownership until reads finish, keyboard focus, copy and command navigation.
Forty-five canonical recording/application tests passed. Five standalone file
reader tests and thirteen shell architecture checks also passed. Native regression
passed 1,010 tests with five conditional tests ignored; documentation contracts
passed fifteen tests. Full-tree Dart analysis is clean.

Legacy UI-side semantic merging and old handoff tests are replaced by the native
hook/control tests and current lifecycle tests; cross-recording search acceptance
is still required rather than inferred from the retired NDJSON search tests.
Non-recording widget tests now override the new library with an I/O-free fixture.
Device design-review and isolated macOS acceptance entrypoints use sampled files;
compilation is not a claim that these device entrypoints were executed.

Two existing verification failures were repaired: the signing fixture now controls
its native-library gate while retaining entitlement checks and fail-before-signing
coverage; the iPhone toolbar reads keyboard visibility outside Scaffold's inset-
consuming body. Both relevant test files passed (12 tests). Six old title-bar
goldens were visually checked and regenerated for the existing unified-menu UI;
strict pixel comparison is retained. A complete verification rerun is pending.

Remaining work: native incremental cache publication/fast open, external bundle
ownership/import, library search and host/date filters, Keep/settings/retention UI,
real macOS and installed-shell/SSH review, whole-pipeline performance and failure
measurements, and more than 24 actual hours of acceptance on the final code.


## Implementation checkpoint — incremental file indexes

The native writer now appends keyframe/command indexes and publishes a bounded,
checksummed summary marker after syncing primary data. Normal open reuses these
local caches without scanning the full recording. Changed or missing caches and
uncommitted tails trigger a cancellable recovery scan. Cache publication failure
does not discard a finished primary recording. Same-size corruption with restored
mtime is detected by Unix change stamps; pixel integrity remains checked at load.

Thirty-five focused native file/storage/control/session tests and strict Clippy
passed. A real-container benchmark now measures 10,000/100,000 samples, cached
open, random seek and forced recovery under warm filesystem caches. Timing data
is generated under ignored build output; this does not establish cold-disk or
real-duration acceptance.

The first complete verification rerun stopped at two terminal architecture tests:
the new file adapter was placed in the domain folder while decoding the wire
format. It now lives in the runtime composition layer with an explicit adapter
boundary; domain restrictions remain intact. All 30 canonical architecture/file
tests pass. Full repository verification must be rerun on this checkpoint.

Search/filter UI, configurable protected retention, external bundle ownership,
actual macOS/local/SSH review, whole-pipeline measurements and >24-hour real-time
acceptance remain required.


File benchmark evidence on macOS 27.0 (26A428), arm64, release build, warm
filesystem caches: 100,000 samples / 10,000 commands produced 105,866,253 primary
bytes plus 3,607,711 index bytes. Across 25 opens, P95 was 93 microseconds; across
100 random seeks, P95 was 185 microseconds. Forced recovery took 812,253
microseconds. The same 10,000-sample case opened at P95 137 microseconds, supporting
bounded cached-open work rather than a duration-sized scan. The short native
benchmark process peaked at 6,995,968 bytes RSS; that is not application or
long-running memory evidence. Logs: `build/recording_bench/adaptive/file-results.json`
and `file-benchmark.log` (ignored local outputs). Full verification is running.

The complete gate's native section passed 1014 tests with 5 conditional
tests ignored. The next stage reported two alphabetic export-order lints after
the reader's move to runtime; both barrel files are now sorted. The complete
repository gate is being rerun and remains unconfirmed until it exits successfully.


## Implementation checkpoint — cross-recording search

Native disposable text indexes and cancellable search pages now cover hook
commands and retained structured-screen text, including soft wrap, Unicode,
sized text and nested-host transitions. The library controller combines files
with bounded result/cursor state, date/host/kind filters, visible partial-file
failures and stale-query suppression. Search results open the recorded moment,
including in an already open replay, without creating sessions or sending input.
Independent readers share one OS claim; cancelling or closing one cannot make a
file eligible for deletion while another reader remains active.

Focused verification: six native search tests and strict Clippy passed; 25 app
controller/library/architecture tests, six actual native-worker/file-contract
tests and 14 widget/shell tests passed. Four search captures at 1,100 px and
390 px / 2x text, light and dark, were inspected; filter, paging, error/retry,
keyboard dismissal and result navigation checks are included. The search preview
has no file/native dependency. Generated package mirrors are synchronized and
full-tree fatal-infos Dart analysis is clean. The current complete gate has passed
1,020 canonical native tests (five conditional tests ignored); later stages remain
running, so complete verification is not yet established.

On the same macOS 27.0 arm64 host, 100,000 synthetic samples / 10,000 commands
produced 15,054,116 bytes of text index plus a 495-byte marker. First build and
first result page took 1,989,219 microseconds. Across 25 dense cached pages, P95
was 478 microseconds. A rare tail hit scanned all 54 pages in 169,660 microseconds;
a no-match scan took 178,690 microseconds (per-page P95 3,457 microseconds).
Native benchmark RSS peaked at 7,782,400 bytes. These warm-filesystem, short,
synthetic measurements exclude Flutter, live PTY, images and input latency.
Evidence: `build/recording_bench/adaptive/search-file-results.json` and
`search-file-benchmark.log`, with search screenshots under the example build tree.

The previous complete gate passed canonical/standalone terminal suites and then
found an omitted iOS export for the file-service ABI. The list is fixed and all
12 Apple build-contract tests pass. That gate had not reached the example app or
macOS integration stages; full verification remains unconfirmed.

Remaining: configurable persistent retention and Keep controls, external bundle
ownership/import, real macOS/local/installed-shell/SSH review, whole-pipeline and
system-failure measurements, >24 actual hours on the final pipeline, and a green
complete repository gate. No batch is declared complete solely by this checkpoint.


### Complete-gate result after search

The full gate passed 1,020 canonical native tests (5 conditional skips), 39 PTY
package tests, 702 canonical terminal tests (1 skip), 746 standalone tests
(1 skip), 43 root contract tests, smoke benchmarks, and 1,973 application tests
(1 skip). Full-tree formatting, fatal-infos analysis, strict Clippy and generated
mirrors also passed. The four actual macOS smoke tests passed.

The real-PTY suite passed 44 cases and failed the pre-existing OSC 1337 download
feedback check: exact saved bytes had succeeded, but the assertion required a
SnackBar even though the desktop host renders notification cards. The saved and
upload-denied checks now assert their exact localized visible text, allowing
independent notifications to coexist. That actual macOS/PTY test passed in a
focused rerun. The full gate did not reach Keychain, release packaging or native
Xcode tests; complete verification still needs a final rerun. Logs are
`/private/tmp/adaptive-recording-search-make-verify.log` and
`/private/tmp/adaptive-recording-download-feedback-test.log` on this host.


## Implementation checkpoint — persistent protected retention

The library now persists configurable age/capacity limits with strict policy
validation. Startup and five-minute maintenance apply both limits; invalid or
unknown settings prevent cleanup and new capture instead of resetting defaults.
Explicit Save and apply warns about immediate deletion. Keep can be changed while
a replay is open, and a late inspect cannot overwrite a newly saved Keep flag.
Deletion requires confirmation and removes the managed bundle, indexes and
manifest. Reader/writer claims and old NDJSON remain protected.

The settings surface has light/dark and compact 2x-text previews, input validation,
usage reporting, retry/error feedback, keyboard navigation and busy-state controls.
Four captures at 1,100x740 and 390x700 were inspected. Six surface tests and four
library-management widget tests pass; the latter include real filesystem settings
persistence, Keep during replay, cancel/confirm deletion and shutdown waiting for
pending periodic cleanup. That shutdown test exposed unsafe late tab-color and
resize access to a gated runtime; optional viewport reads and shutdown guards
now prevent those exceptions. Controller widget fixtures dispose owned providers
before Flutter timer invariants. All 133 session/startup/shutdown tests and 39
native roundtrip/library/search/replay/architecture tests pass.

Current logs: `/private/tmp/adaptive-recording-retention-management.log`,
`/private/tmp/adaptive-recording-retention-lifecycle.log`,
`/private/tmp/adaptive-recording-retention-integration.log`, and
`/private/tmp/adaptive-recording-retention-visual.log`. Captures are under
`example/build/recording_bench/adaptive/retention-*.png`. The complete application
suite passed 1,990 tests with two conditional skips; fatal-infos analysis and all
12 documentation contract tests passed. Full-repository verification is being
rerun and is not established by these focused/application passes.

Still open: safe external new-format bundle ownership, directory durability and
system-failure checks, actual macOS/local/installed-shell/SSH product review,
whole-pipeline performance and more than 24 actual hours on the final pipeline.
No batch is declared fully accepted by this checkpoint.


## Complete gate and directory publication checkpoint

The full `make verify` run on commit `80a7f6e6` exited successfully on this
macOS 27.0 arm64 host. It passed 1,020 canonical native tests (five conditional
skips), strict Clippy, formatting, full-tree fatal-infos analysis, generated
mirrors, canonical/standalone package and documentation contracts, smoke
benchmarks, 1,990 application tests (one conditional skip), four actual macOS
smoke tests, all 45 real-PTY cases, the actual Keychain test, Debug/Release and
incremental Release packaging/library checks, and native Xcode tests. The earlier
OSC 1337 feedback blocker is closed on that checkpoint. The log is retained at
`build/recording_bench/adaptive/retention-make-verify.log` (ignored local output).

A subsequent slice adds bounded native directory synchronization for library
metadata publication and deletion. Reservations are returned only after directory
acknowledgement; failed stop publication retains native/file ownership. Failed
initialization and interrupted unlink acknowledgement can be retried, including
when both bundle and manifest are already absent. A remaining orphan bundle is
never removed merely because its manifest is absent. The default file provider
now closes after application persistence during shutdown.

Focused verification passed 25 native storage/file-service tests, strict Clippy,
six actual Dart/native-worker file tests, 58 application recording/library/search/
replay/shutdown tests, 15 documentation contracts, and full-tree fatal-infos
analysis. Fault injection covers
initial directory preparation, reservation publication, final stop, abandoned
reservation cleanup, policy save, and both stages of deletion. These syscall and
failure-path checks do not establish hardware power-loss durability. The changed
slice still requires a fresh complete gate.

The repository's production SSH bootstrap acceptance also passed in a dedicated
Colima Docker context. It exercised real Bash/Zsh/Fish hooks, shell switching,
nested SSH/ControlMaster/SFTP, endpoint isolation, and history checks using local
disposable OpenSSH containers and temporary fixture credentials. Artifacts are
under `build/recording_bench/adaptive/ssh-product/`. This is production transport
and hook evidence, not full Flutter recording/player or 24-hour acceptance.

Remaining work: external new-format bundle ownership/opening, actual macOS
recording UI and installed-shell/SSH recording review, whole-pipeline resource
and input measurements, system-failure evidence, and more than 24 actual hours
on the final pipeline. All four delivery batches remain in scope.


### Incremental macOS bundle signing regression

The complete gate on `bda766be` passed 1,021 canonical native tests (five
conditional skips), the package/contracts/analysis stages, 1,998 application
tests (one skip), all four actual macOS smoke cases, 45 real-PTY cases and
Keychain. It then failed strict Debug bundle signing: `App.framework` itself
was valid, but the enclosing app still recorded its prior signature. A repeated
unchanged Debug build reproduced the failure; Xcode reran the Flutter embedding
script without rerunning the enclosing CodeSign step.

The Flutter framework embedding and Data API scripts now declare their actual
bundle outputs to Xcode. The actual Keychain test build, transition back to the
normal Debug entrypoint, and a second incremental Debug build all pass strict
deep signature verification; all 12 Apple build contracts pass. The macOS gate
now repeats Debug as well as Release builds. A full gate including Release and
native Xcode tests must still be rerun after this fix. Evidence is in
`build/recording_bench/adaptive/directory-make-verify.log`,
`debug-signing-transition.log` and `debug-signing-contracts.log` in that folder.


## Implementation checkpoint — owned external recording import

The file picker now admits external schema-2 recordings through a bounded native
copy, retaining the original identity, exact primary bytes and verified referenced
graphics. It writes indexes only in the owned copy. Native publication uses an
exclusive rename that cannot replace an existing entry. Existing identities,
invalid policy, capacity exhaustion, changed source data and invalid referenced
assets fail without overwriting an existing recording or modifying the source.

The app journals staging before the worker starts, holds its library claim until
settlement, rechecks capacity including indexes, and publishes imported entries
as Keep. Cancellation before publication cleans only owned staging. Cancellation
after publication begins waits for settlement and preserves the committed copy.
Lost publication/manifest acknowledgements leave a protected recoverable bundle.
Restart cleans only strict known staging journals; unknown/future/corrupt ones
remain untouched and count toward protected capacity. Shutdown cancels imports
before waiting for maintenance queued behind them and also drains picker reads.
The picker and command-palette descriptions now explain the owned copy behavior.

Focused verification passed two native copy units, seven copy/publication
integration tests and eight native file-service tests, plus strict Clippy.
Canonical/standalone typed-file tests passed 20 cases, including real native
copy, publish, graphics, seek and search. Application checks passed 45 import,
library and management cases and a further 30 import/picker/native/architecture
cases (overlapping import cases are not unique additional tests). The actual
PTY round trip now imports its finished bundle through the app library, seeks
and searches its copy, deletes the copy and verifies the original remains intact.
Widget tests exercise opening through the picker, cancelling it, and shutdown
while periodic retention waits behind a still-running copy; replay creates no
PTY and sends no terminal input.

Evidence: `/private/tmp/adaptive-recording-import-native.log`,
`/private/tmp/adaptive-recording-import-file-api.log`,
`/private/tmp/adaptive-recording-import-app-tests.log`, and
`/private/tmp/adaptive-recording-import-roundtrip.log`. Full-tree fatal-infos
analysis and all 12 documentation contracts pass, and generated mirrors are
current. The complete repository/macOS gate is being rerun for this checkpoint;
no completion claim follows from the focused tests.

Remaining: actual macOS recording UI and installed-shell/SSH recording review,
whole-pipeline resource and input measurements, system-failure evidence, more
than 24 actual hours on the final pipeline, and a green final complete gate.
All four delivery batches remain in scope.


## Complete import gate and macOS window acceptance checkpoint

The complete `make verify` on `7a12df68` exited 0. It passed canonical and
standalone native/Dart contracts, strict static checks, 2,014 application tests
(one conditional skip), all four actual macOS smoke cases, all 45 real-PTY cases,
Keychain, strict Debug and repeated Debug signatures, Release and repeated Release
packaging/signatures, and native Xcode tests. The log is retained in
`build/recording_bench/adaptive/import-make-verify.log`. This establishes the
complete import checkpoint and closes the previously observed incremental Debug
signing gate; subsequent changes still require current final verification.

A new real macOS window test exercises the production app/controller/native
composition. It starts recording through the command menu while a populated TUI
is already visible, records a resize, styles, Unicode, hyperlinks and a Kitty
image, deletes the live image data, and verifies the retained RGBA bytes. It stops
and opens through the product controls, clicks a recorded command and checks its
exact seek time, seeks retained TUI/final frames, and types into replay without
changing the live shell or creating another session. Pointer misses are fatal;
menu motion/scrolling is settled before tapping and visible notices are dismissed
through their controls. Theme checks wait for actual dark appearance before
capture. The deterministic PTY fixture emits explicit hooks: it is not evidence
for installed-shell bootstrap by itself.

Image review exposed the sampled player's native fallback black background
being used instead of the same application appearance as live/instant replay.
The player now uses the configured default colors while retaining explicit cell
styles. Four final captures were inspected at
`build/recording_bench/adaptive/macos-ui/run-ngWn95/`: `live-tui.png`,
`replay-initial-light.png`, `replay-tui-light.png`, and `replay-final-dark.png`.
The strict window test passed on this host, and it is now included in the macOS
verification script. Recording notices explicitly say raw keystrokes are not
recorded, and command-palette search no longer advertises old NDJSON opening.

A separate real installed-shell test captures actual Bash and Zsh hooks, checks
exact quoted Unicode commands and exit codes, closes the PTY, and searches/seeks
the saved file. Both installed shells passed; local Fish is explicitly skipped
because `/opt/homebrew/bin/fish` is absent. The test isolates startup/history
settings without changing the user's HOME or shell configuration. The recording
library UI regression suite plus installed-shell tests passed 11 cases with that
one conditional skip. Evidence is in `/private/tmp/adaptive-recording-macos-ui.log`
and `/private/tmp/adaptive-recording-appearance-regression.log`.

Remaining: recording-specific SSH/full-app evidence, restart/process and system
failure evidence at the final product boundary, whole-pipeline resource/input
measurements, more than 24 actual hours on the final implementation, and a green
final complete gate. No batch is newly declared fully accepted by this checkpoint.

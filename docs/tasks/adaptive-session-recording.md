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
cargo test --manifest-path native/core/Cargo.toml --test sampled_recording_test --test sampled_recording_storage_test --test sampled_recording_timeline_test --test sampled_recording_session_test
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
- The app still runs schema 1 capture until batch 2 replaces its entrypoints.
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

Still required before batch 2 acceptance: exact-current native/Dart request
contracts, app start/stop/status and ownership-aware handoff, pure structured
Flutter replay and cancellable seek jobs, incremental index publication, durable
failure UI, representative whole-container/asset/RSS/input-latency measurements.
Batch 3 library/search/retention and batch 4 real >24-hour/product/SSH/system
failure validation remain open. Legacy app entrypoints are unchanged so far.

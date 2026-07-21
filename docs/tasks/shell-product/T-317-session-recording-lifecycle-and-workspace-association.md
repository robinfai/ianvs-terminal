# T-317 Session Recording Lifecycle and Workspace Association

## Goal

Connect the verified Recording v1/native capture seam to a safe product lifecycle so a local
Session can start a redacted recording, atomically save it, and persist the resulting path in its
Workspace Session Descriptor.

## Scope

- Add a bounded local recording repository under Application Support with collision-safe file
  allocation, atomic NDJSON writes and validated reads.
- Start recording only for a live local Session; use `redact` as the product-default input policy.
- Stop native capture before writing, keep a complete recording in memory when the file write
  fails, and expose a retryable pending-save state.
- Update the live pane descriptor `recordingPath` only after the recording file is durably written.
- Finalize active or pending recordings before closing a pane/tab or switching Workspace; refuse
  the destructive lifecycle transition when persistence still fails.
- Finalize active recordings on observed process exit and best-effort controller disposal.
- Add a theme-derived, semantic title-bar control and command-palette action that reflect Start,
  Stop/Save and Retry Save states for the active Session.
- Surface bounded recording failures through the existing runtime-error UI and successful saves
  through product feedback.

## Non-goals

- Do not add checkpoint/seek, speed control, graphics asset bundles or Host Request/Response
  capture.
- Do not expose unredacted input as the product default or claim that PTY output is non-sensitive.
- Do not add recording rename/delete, a recording library, cloud sync or cross-version guarantees.
- Do not replace the existing viewport `InstantReplayStore` or add a full recording playback UI.
- Do not preserve an original PTY process across relaunch.

## Functional Acceptance

- Starting from the title bar or command palette sends one native start request with `redact`, and
  duplicate starts are suppressed.
- Stopping writes one valid schema-v1 NDJSON file and updates the active Session Descriptor with
  its absolute path; Workspace persistence retains that path.
- A write failure leaves the Session and PTY alive, records a pending-save state, and a later retry
  writes the same complete recording without issuing a second native stop.
- Pane/tab close and Workspace switch complete only after every affected recording is saved; a
  persistent save failure keeps the previous topology and runtime sessions intact.
- Process exit and controller disposal stop or cancel every active native recording without
  returning a partial recording as successful.
- The active-session control has stable test keys, semantic labels/tooltips, keyboard-accessible
  command-palette parity and theme-derived colors.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/recording/local_session_recording_repository_test.dart
flutter test test/sessions/session_recording_lifecycle_test.dart
flutter test test/shell/shell_recording_lifecycle_test.dart
cd ..
dart analyze example/lib/features/recording example/lib/features/sessions \
  example/lib/features/shell example/test/recording \
  example/test/sessions/session_recording_lifecycle_test.dart \
  example/test/shell/shell_recording_lifecycle_test.dart --fatal-infos
make format-check
make verify
```

## Result

- A local Application Support repository now allocates Workspace-partitioned, collision-safe
  `.ndjson` destinations, atomically writes canonical Recording v1 data, validates reads and
  retains failed destinations for a later retry.
- `SessionController` now owns redacted capture start/stop state, keeps a complete stopped
  recording in memory after a write failure, updates `recordingPath` only after durable save, and
  retries without issuing a second native stop.
- Pane/tab close and Workspace switching now finalize every affected recording first and refuse
  the destructive transition when persistence fails. Observed process exit and controller
  disposal also perform best-effort synchronous finalization.
- The active Session has a semantic, theme-derived title-bar control plus the same unified action
  in the searchable command palette. Start, Stop/Save, Retry Save and busy states have stable
  labels and test keys; successful start/save operations provide visible feedback.
- Eight focused tests pass across repository roundtrip/allocation (2), lifecycle, retry, switch,
  exit and disposal behavior (5), and title-bar/command-palette interaction (1). The affected
  Session and command-menu regression passes 123 tests, and fatal-info Flutter analysis is clean.
- `make format-check` reports 395 formatted files with zero changes. The final `make verify`
  passes 1,733 vendored Rust tests with one ignored test, 118 native core tests, 515 native session
  tests, 3 native `vttest` regressions, 24 `ianvs_pty` tests, 499 `ianvs_terminal` tests with one
  intentional skip, 12 documentation tests, 1,102 selected example CI tests, 4 macOS smoke tests,
  46 real PTY tests and all 17 Runner XCTest cases.
- Benchmark evidence is in `build/bench-results-ci/20260721T062119Z`; all six deterministic rows
  report `hash_match=true`. T-317 is closed.

## Risks / Follow-ups

- A recording remains sensitive because PTY output can contain commands, tokens and file content
  even when user input bytes are redacted.
- Crash or forced-kill durability beyond atomic completed writes requires a separately designed
  streaming/checkpoint format; this task owns graceful product lifecycle only.
- A future recording library and Replay UI can consume the validated files without changing the
  v1 capture contract.

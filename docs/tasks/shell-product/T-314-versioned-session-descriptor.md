# T-314 Versioned Local Session Descriptor

## Goal

Replace the Workspace v1 `profileId`/`cwd` relaunch intent with an independent, versioned
Session Descriptor that records enough local-session metadata for deterministic relaunch without
claiming that the original PTY process survived.

## Scope

- Add Session Descriptor schema v1 with a stable descriptor ID, profile ID, command and arguments,
  cwd, environment metadata, title, creation time, exit state, optional recording path and restart
  policy.
- Persist environment key names only; never persist environment values in the Workspace document.
- Advance the Workspace document to schema v2 and migrate unversioned/v1 `sessionIntent` leaves to
  `sessionDescriptor` leaves atomically.
- Preserve unsupported future Workspace and Session Descriptor documents without quarantine or
  overwrite.
- Carry descriptors in live pane state so descriptor identity, creation time and recording path
  survive later Workspace saves.
- Relaunch the saved command/cwd through the current local profile and current environment policy,
  always creating a new runtime session ID.
- Honor the `never` restart policy without invoking the runtime launcher.

## Non-goals

- Do not reconnect to or recover the original PTY process, scrollback or parser state.
- Do not persist environment values, credentials or other secrets.
- Do not add recording start/stop UI or automatically assign recording files; this task only
  defines and preserves the optional association field.
- Do not add Workspace collections, project identity, Recent Workspaces, remote/SSH restore,
  checkpoint/seek or playback UI.

## Schema Contract

Workspace v2 leaf:

```text
sessionDescriptor
├── schemaVersion = 1
├── id / profileId
├── command { program, arguments }
├── cwd
├── environment { keys, valuesRedacted = true }
├── title / createdAtUtc
├── exitState / exitCode
├── recordingPath
└── restartPolicy
```

The descriptor is relaunch intent, not a runtime-session handle. `id` remains stable across an app
restart while `SessionController` maps it to a newly created PTY session ID.

## Files In Scope

- `example/lib/features/workspace/local_session_descriptor.dart`
- `example/lib/features/workspace/local_workspace_models.dart`
- `example/lib/features/workspace/local_workspace_repository.dart`
- `example/lib/features/workspace/local_session_workspace_codec.dart`
- `example/lib/features/sessions/session_state.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/test/workspace/local_session_descriptor_test.dart`
- `example/test/workspace/local_workspace_repository_test.dart`
- `example/test/workspace/local_session_workspace_codec_test.dart`
- `example/test/sessions/session_controller_test.dart`

## Functional Acceptance

- The complete descriptor roundtrips deterministically and ignores additive unknown fields.
- Environment values supplied in unknown JSON fields are discarded and never re-emitted.
- Unversioned and Workspace v1 documents load and rewrite as Workspace v2 descriptors.
- Unsupported future Workspace or descriptor versions leave the original file byte-for-byte
  untouched and are not mislabeled as corruption.
- Live capture records actual launch command metadata, current cwd, title, creation time and exit
  state while preserving descriptor ID and recording path.
- Restore uses saved command/cwd/title, current profile environment values and new runtime session
  IDs.
- `restartPolicy: never` skips launch, enters the existing visible relaunch-failure path and never
  invokes the PTY backend.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/workspace/local_session_descriptor_test.dart \
  test/workspace/local_workspace_repository_test.dart \
  test/workspace/local_session_workspace_codec_test.dart
flutter test test/workspace test/sessions/session_controller_test.dart
cd ..
dart analyze example/lib/features/workspace example/lib/features/sessions \
  example/test/workspace example/test/sessions/session_controller_test.dart \
  --fatal-infos
make format-check
make verify
```

## Result

- Session Descriptor v1 and Workspace schema v2 are implemented with explicit legacy migration,
  unknown-field compatibility and structured future-version rejection.
- Live panes now retain their descriptor separately from runtime IDs; fresh sessions receive a UTC
  creation time, and restored descriptors retain their ID, creation time and recording path.
- Relaunch restores saved command, arguments, cwd and title while resolving environment values from
  the current profile/runtime policy. Persisted environment metadata contains sorted key names only.
- Focused descriptor/repository/codec tests pass 14 tests. The complete Workspace plus
  `SessionController` regression passes 135 tests, and focused `--fatal-infos` analysis reports no
  issues.
- The direct package gate passes 12 documentation tests, 24 `ianvs_pty` tests, 499
  `ianvs_terminal` tests with 1 intentional skip, and 1,132 example tests with 1 intentional skip.
- The complete `make verify` gate passes 1,733 vendored Rust tests with 1 ignored, 118 native unit
  tests, 515 native session tests, 3 native vttest regressions, 1,077 example CI tests, 4 macOS
  smoke tests, 46 real PTY tests, and all 16 Runner XCTest cases.
- Benchmark evidence is in `build/bench-results-ci/20260721T044538Z`; all six deterministic
  correctness rows report `hash_match=true`. T-314 is closed.

## Risks / Follow-ups

- `recordingPath` is a versioned association slot, but recording lifecycle/UI wiring remains a
  separate task.
- Project-scoped Workspace identity and Recent Workspaces remain the next Workspace slice.
- Command arguments can be operationally sensitive; they are required for relaunch fidelity, while
  environment values remain deliberately excluded. A future UI that exposes descriptors should
  apply an explicit redaction/display policy.

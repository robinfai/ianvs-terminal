# T-315 Project Workspace Identity and Recent Index

## Goal

Advance the single local Workspace document into a migration-safe collection foundation with
stable project identity and a bounded, versioned Recent Workspaces index.

## Scope

- Advance the Workspace document to schema v3 with required `id` and `name` plus optional
  `projectPath` identity fields.
- Derive deterministic project Workspace IDs from normalized absolute local paths; reject
  ambiguous relative paths.
- Add Recent Workspace index schema v1 with current Workspace ID, UTC last-opened time,
  deterministic dedupe and a ten-entry bound.
- Store independent Workspace documents under `ianvs_workspaces/` while retaining the legacy
  single-file path as a recoverable active-Workspace alias.
- Migrate an unversioned/schema-v1/schema-v2 legacy document to the default Workspace identity,
  collection document and index without deleting the source alias.
- Preserve unsupported future Workspace, Session Descriptor and Recent index documents without
  quarantine or overwrite.
- Preserve the loaded Workspace identity through live `SessionController` capture and subsequent
  debounced saves.

## Non-goals

- Do not add the project picker, Recent Workspaces menu or live Workspace switch UI in this task.
- Do not delete Workspace documents or implement retention beyond the bounded recent index.
- Do not require the project directory to be mounted or currently accessible; the persisted path
  is identity metadata, not a filesystem health claim.
- Do not reconnect an original PTY, add remote Workspace fields or wire recording lifecycle UI.

## Storage Contract

```text
ianvs_workspace_index.json            # index schema v1
ianvs_workspace_layout.json           # recoverable active alias
ianvs_workspaces/
└── workspace-<safe-id>.json           # Workspace schema v3
```

Workspace v3 identity:

```text
id
name
projectPath?
schemaVersion = 3
```

Recent index v1:

```text
schemaVersion = 1
currentWorkspaceId
recent[] { id, name, projectPath?, lastOpenedAtUtc }
```

## Files In Scope

- `example/lib/features/workspace/local_workspace_identity.dart`
- `example/lib/features/workspace/local_workspace_models.dart`
- `example/lib/features/workspace/local_workspace_repository.dart`
- `example/lib/features/workspace/local_session_workspace_codec.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/test/workspace/local_workspace_identity_test.dart`
- `example/test/workspace/local_workspace_repository_test.dart`
- `example/test/workspace/local_session_workspace_codec_test.dart`
- `example/test/sessions/session_controller_test.dart`

## Functional Acceptance

- Equivalent project paths with trailing separator differences resolve to the same stable ID.
- A schema-v3 Workspace roundtrips identity and ignores additive unknown fields.
- Current schema documents missing required identity fail through the corrupt-data boundary rather
  than silently colliding with the default Workspace.
- Two project Workspaces persist independently and can be reopened by ID.
- Opening a Workspace moves it to the front of a deduplicated, bounded recent list; layout saves do
  not fabricate a new identity.
- Legacy single-file layouts migrate to the default identity and remain recoverable through the
  active alias.
- Future Workspace, descriptor and index schemas remain byte-for-byte untouched.
- A loaded project identity survives real controller capture and persistence.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/workspace/local_workspace_identity_test.dart \
  test/workspace/local_workspace_repository_test.dart \
  test/workspace/local_session_workspace_codec_test.dart
flutter test test/workspace test/sessions/session_controller_test.dart
cd ..
dart analyze example/lib/features/workspace \
  example/lib/features/sessions/session_controller.dart \
  example/test/workspace example/test/sessions/session_controller_test.dart \
  --fatal-infos
make format-check
make verify
```

## Result

- Workspace schema v3, stable project identity, Recent index v1 and the independent collection
  repository are implemented.
- Legacy documents migrate to the default identity and collection without destructive deletion;
  unsupported future contracts remain outside the corruption-repair path.
- `LocalSessionWorkspaceCodec` and `SessionController` preserve the active identity across live
  capture and debounced persistence.
- Focused identity/repository/codec coverage passes 23 tests. The complete Workspace plus
  `SessionController` regression passes 146 tests, and focused `--fatal-infos` analysis reports no
  issues.
- The direct package gate passes 12 documentation tests, 24 `ianvs_pty` tests, 499
  `ianvs_terminal` tests with one intentional skip, and 1,143 example tests with one intentional
  skip.
- The final `make verify` passes 1,733 vendored Rust tests with one ignored test, 118 native core
  tests, 515 native session tests, 3 native `vttest` regressions, 24 `ianvs_pty` tests, 499
  `ianvs_terminal` tests with one intentional skip, 12 documentation tests, 1,088 selected example
  CI tests, 4 macOS smoke tests, 46 real PTY tests and all 16 Runner XCTest cases.
- Benchmark evidence is in `build/bench-results-ci/20260721T051058Z`; all six deterministic rows
  report `hash_match=true`. T-315 is closed.

## Risks / Follow-ups

- The collection APIs are now available, but a project picker, Recent Workspaces menu and safe live
  switch lifecycle are still required before the capability is product-visible.
- Path identity is textual and normalized for trailing separators; resolving symlinks, volume case
  behavior or moved projects requires an explicit future policy.
- Recording association remains represented by Session Descriptor `recordingPath`; lifecycle
  ownership and UI remain separate.

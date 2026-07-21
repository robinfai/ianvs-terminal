# T-312 Versioned Local Workspace Schema

## Goal

Add an explicit schema version and a bounded migration boundary to the existing local Workspace
layout document before wiring it into application startup.

## Scope

- Add the current Workspace schema version to every serialized layout.
- Treat the existing unversioned layout shape as legacy v1 and rewrite it after a successful load.
- Reject unsupported explicit schema versions without quarantining or overwriting their files.
- Keep malformed current documents on the existing corrupt-file quarantine and repair path.
- Add repository regressions for current, legacy, future and corrupt documents.

## Non-goals

- Do not restore or launch terminal sessions.
- Do not claim process continuity across application restarts.
- Do not add recent-workspace UI, recording association or remote session fields.
- Do not change the pane topology contract beyond adding `schemaVersion`.

## Files In Scope

- `example/lib/features/workspace/local_workspace_models.dart`
- `example/lib/features/workspace/local_workspace_repository.dart`
- `example/test/workspace/local_workspace_repository_test.dart`
- `docs/tasks/shell-product/T-312-versioned-local-workspace-schema.md`

## Functional Acceptance

- Every newly saved Workspace document contains `schemaVersion: 1`.
- An unversioned legacy layout loads with unchanged topology and is atomically rewritten as v1.
- A document written by a newer schema throws an explicit unsupported-version error and remains
  byte-for-byte untouched.
- A malformed schema field continues through the established quarantine and repaired-empty path.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/workspace/local_workspace_repository_test.dart
flutter test test/workspace
cd ..
dart analyze example/lib/features/workspace example/test/workspace --fatal-infos
```

## Result

- Added Workspace schema v1 to the persisted layout contract.
- Added automatic unversioned-to-v1 rewrite after successful decoding.
- Added a typed unsupported-version error outside the corrupt-file catch path so a future document
  is preserved rather than destructively repaired by an older application.
- The repository regressions and the complete 48-test Workspace suite pass; the wider focused
  Workspace/Session/Shell run also passes 144 tests.
- Focused Dart analysis, including info-level diagnostics, reports no issues.
- The final `make verify` passed the complete Rust, Dart/Flutter, macOS smoke, real PTY and XCTest
  gates. The new benchmark is `build/bench-results-ci/20260721T041743Z`; all six deterministic
  correctness rows are byte-identical to the T-311 baseline.

## Risks / Follow-ups

- Schema v1 still stores the legacy bounded `profileId` + `cwd` relaunch intent. A richer Session
  Descriptor requires a separate schema migration.
- This task establishes the file boundary only; T-313 owns application startup restore and live
  persistence wiring.

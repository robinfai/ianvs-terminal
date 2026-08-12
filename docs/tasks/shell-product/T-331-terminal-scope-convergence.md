# T-331 Terminal Scope Convergence

## Goal

Replace the Project Workspace product model with Terminal Layout, minimal
Relaunch Spec, Open Terminal at Folder and an independent Recording Library.

## Scope

- Persist one versioned local Terminal Layout.
- Accept only the current Terminal Layout schema; unsupported predecessor
  artifacts are outside the product contract and are not discovered, migrated,
  rewritten or deleted.
- Persist only profile/command/cwd as Relaunch Spec.
- Remove project identity, Recent Workspace and project switching UI/runtime.
- Open a new terminal at a selected folder.
- Store recordings in the independent current-format Recording Library.
- Keep internal completion diagnostics debug-only.
- Update current scope/architecture/roadmap contracts.

## Non-goals

- Project explorer, Git context, IDE tasks or project metadata.
- SSH implementation, remote domains or remote Workspace.
- Plugins, cloud sync or collaboration.
- Discovering, migrating or deleting predecessor user files.

## Acceptance

- Canonical layout JSON contains `ianvs-terminal-layout-v1` and no project
  identity.
- Canonical relaunch JSON contains only version, contract, profile, command and
  cwd; non-current shapes are rejected without mutation.
- Folder selection adds a terminal and preserves existing PTYs/recordings.
- Current and native UI expose Open Terminal at Folder and no project/recent
  switcher.
- Recordings use the single current flat-library format.
- Debug diagnostics are gated by `kDebugMode`.
- Machine-readable docs evidence and the complete repository gate pass.

## Verification Commands

```bash
cd example && flutter analyze --fatal-infos
cd example && flutter test
dart test test/docs_contract_test.dart
make verify
```

## Result

Implemented and accepted on 2026-07-23. Focused model, repository, controller,
recording and Widget tests passed during implementation.

Final repository-gate evidence:

- `make format-check` passed with 418 files unchanged.
- `make verify` passed with exit code 0.
- vendored core passed 1,733 unit tests and 11 doc-tests; native/core passed
  518 session tests and 3 vttest regressions.
- `ianvs_pty` passed 62 tests; `ianvs_terminal` passed 551 tests with one
  expected skip; the selected example suite passed 1,087 tests.
- benchmark smoke wrote `build/bench-results-ci/20260723T015509Z`.
- macOS smoke passed 4 tests and real PTY acceptance passed 46 tests.
- debug macOS build and all 17 Runner XCTest cases passed, including
  `testTerminalFolderFileMenuIsStandardAndIdempotent`.

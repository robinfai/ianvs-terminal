# T-316 Project Workspace Switcher

> Archival task record superseded by T-331. Workspace predecessor formats are
> not product inputs: current production code does not discover, migrate,
> rewrite or delete them.

## Goal

Make the T-315 project Workspace collection product-visible through a native project picker,
bounded Recent Workspaces menu and failure-safe live switching lifecycle.

## Scope

- Add a title-bar Workspace menu that names the active Workspace, exposes `Open Project…`, and
  lists the bounded Recent Workspaces index.
- Add a macOS `File > Open Project…` command with the standard `Command-O` shortcut and a native
  directory-only `NSOpenPanel` bridge.
- Save the current Workspace before switching when persistence is active.
- Prepare the target Workspace sessions before replacing the visible topology; close the old PTYs
  only after target activation succeeds.
- Launch an empty project Workspace with the effective default profile rooted at its project path.
- Keep the current Workspace and PTYs alive when selection is cancelled, loading fails, no launch
  profile is available, or target activation fails.
- Refresh Recent Workspaces after every successful switch and expose bounded failures through the
  existing visible runtime-error surface.

## Non-goals

- Do not delete, rename, pin or reorder Workspace documents.
- Do not resolve symlinks, moved projects or volume case aliases.
- Do not reconnect an original PTY process or add recording lifecycle ownership.
- Do not add multiple application windows or remote Workspace fields.

## Functional Acceptance

- Opening a new absolute project path creates or reuses its stable Workspace identity and launches
  the first terminal with that path as `cwd`.
- Opening a recent Workspace restores its persisted topology with new runtime session IDs.
- A successful switch activates the target index entry, atomically publishes the target topology,
  and closes every old runtime session.
- A failed target load or activation preserves the old identity, topology and runtime sessions.
- The title-bar menu shows the active Workspace, `Open Project…`, and recent entries without
  duplicating the active Workspace.
- The native menu command and title-bar action share the same picker/switch implementation; picker
  cancellation is a no-op.
- Controls have stable test keys, semantic labels/tooltips, keyboard access and theme-derived
  colors.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/sessions/session_controller_test.dart
flutter test test/shell/shell_workspace_switcher_test.dart
cd ..
dart analyze example/lib/features/workspace example/lib/features/sessions \
  example/lib/features/shell example/test/sessions/session_controller_test.dart \
  example/test/shell/shell_workspace_switcher_test.dart --fatal-infos
make format-check
make verify
```

## Result

- The title bar now names the active Workspace and exposes `Open Project…` plus bounded Recent
  Workspace entries without duplicating the active identity.
- macOS now exposes native `File > Open Project…` with `Command-O`; its directory-only
  `NSOpenPanel` and the title-bar action share one Flutter switch path, and cancellation is a no-op.
- Switching saves the current persistent layout, prepares the target topology and new PTYs before
  activation, publishes the target atomically, and closes old PTYs only after activation succeeds.
  Target load, launch or activation failures keep the prior identity, topology and PTYs alive.
- Empty projects launch the effective default profile with the selected project path as `cwd`.
  Controls use stable keys, semantic labels/tooltips and theme-derived colors.
- Focused repository/controller/widget coverage passes 98 tests; the complete Workspace,
  `SessionController` and Shell regression passes 487 tests, and fatal-info analysis reports no
  issues.
- The direct package gate passes 12 documentation tests, 24 `ianvs_pty` tests, 499
  `ianvs_terminal` tests with one intentional skip, and 1,149 example tests with one intentional
  skip.
- The final `make verify` passes 1,733 vendored Rust tests with one ignored test, 118 native core
  tests, 515 native session tests, 3 native `vttest` regressions, 24 `ianvs_pty` tests, 499
  `ianvs_terminal` tests with one intentional skip, 12 documentation tests, 1,094 selected example
  CI tests, 4 macOS smoke tests, 46 real PTY tests and all 17 Runner XCTest cases.
- Benchmark evidence is in `build/bench-results-ci/20260721T053640Z`; all six deterministic rows
  report `hash_match=true`. T-316 is closed.

## Risks / Follow-ups

- Recording association remains represented by Session Descriptor `recordingPath`; recording
  lifecycle ownership and UI remain separate.
- Project identity remains textual; resolving symlinks, volume case aliases and moved projects
  still requires an explicit future policy.
- A future Workspace manager may add rename, pin, remove and moved-project recovery after those
  behaviors receive explicit storage contracts.

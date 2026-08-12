# T-313 Local Workspace Session Restore

> Archival task record superseded by T-331. Workspace predecessor formats are
> not product inputs: current production code does not discover, migrate,
> rewrite or delete them.

## Goal

Wire the versioned local Workspace document into the real `SessionController` lifecycle so an
enabled application restart restores tab/pane topology by launching new terminal sessions, with
visible failure handling and no claim that the prior PTY process survived.

## Scope

- Convert live `SessionState` tab/pane trees into local Workspace relaunch intent.
- Preserve tab order, split direction, nested topology, split ratio, active tab and active pane.
- Prefer the shell integration current directory, then the launch-profile cwd, for relaunch cwd.
- When `workspace.restoreLayout` is enabled, load the Workspace during bootstrap and launch new
  sessions from current profiles.
- Debounce and serialize Workspace saves after relevant `SessionState` changes.
- Surface missing-profile or relaunch failures in a dismissible in-product error banner.
- Add pure codec, controller integration and widget regressions.

## Non-goals

- Do not recover, reconnect to or imply continuity of the original PTY process.
- Do not restore terminal output, scrollback, environment values or in-memory protocol state.
- Do not add remote/SSH persistence, recent-workspace UI, checkpoint/seek or recording playback.
- Do not yet introduce the richer Session Descriptor fields or Workspace collection metadata from
  the handoff; those remain separate migrations.

## Files In Scope

- `example/lib/features/workspace/local_session_workspace_codec.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_chrome.dart`
- `example/test/workspace/local_session_workspace_codec_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`
- `docs/tasks/shell-product/T-313-local-workspace-session-restore.md`

## Functional Acceptance

- Restored panes receive newly created runtime session IDs; persisted IDs are only mapping keys.
- Restored nested layouts retain direction and ratio, and focus resolves to the recreated active
  pane.
- A missing profile or failed relaunch is skipped without fabricating a live session; the remaining
  split branch collapses deterministically.
- Total relaunch failure falls back to the configured default local profile and keeps a visible,
  dismissible error explaining the skipped profile.
- With Workspace restore enabled, a live split/layout mutation produces a versioned relaunch-intent
  save through the real repository provider.
- With Workspace restore disabled, the existing default-session bootstrap remains unchanged.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/workspace/local_session_workspace_codec_test.dart
flutter test test/sessions/session_controller_test.dart --plain-name workspace
flutter test test/shell/shell_screen_phase3_test.dart --plain-name "workspace relaunch failures"
flutter test test/workspace test/sessions/session_controller_test.dart \
  test/shell/shell_screen_phase3_test.dart
cd ..
dart analyze example/lib/features/workspace example/lib/features/sessions \
  example/lib/features/shell example/test/workspace \
  example/test/sessions/session_controller_test.dart \
  example/test/shell/shell_screen_phase3_test.dart --fatal-infos
make verify
```

## Result

- Added a pure live-state/Workspace codec with deterministic failed-branch collapse and old-to-new
  session ID mapping.
- Connected the versioned repository to real bootstrap and state persistence only when
  `workspace.restoreLayout` is enabled.
- Added a 60 ms debounce and serialized save chain so rapid UI mutations cannot issue unordered
  Workspace writes.
- Added a dismissible runtime error banner for partial or total relaunch failures.
- Three codec, three controller and one widget regression pass. The complete focused
  Workspace/Session/Shell run passes 144 tests, and focused static analysis reports no issues.
- The final `make verify` passed: vendored Rust 1,733 tests with 1 ignored; native core 118 unit,
  515 session and 3 `vttest` regressions; `ianvs_pty` 24 tests; documentation 12 tests; example CI
  1,072 tests; macOS smoke 4 tests; real PTY 46 tests; and Runner XCTest 16 tests.
- Benchmark evidence is in `build/bench-results-ci/20260721T041743Z`; all six `hash_match` values
  are `true`, and the deterministic columns are byte-identical to the T-311 baseline.
- T-313 is closed. The broader Workspace lane remains active for the richer Session Descriptor,
  Recent Workspaces/project identity and recording association.

## Risks / Follow-ups

- Schema v1 relaunch intent only contains `profileId` and `cwd`; command/title/creation/exit/restart
  and recording metadata still require a versioned Session Descriptor design.
- Recent Workspaces and project-level Workspace identity are not implemented.
- Persistence is intentionally gated by `workspace.restoreLayout`; enabling that setting must have
  a valid platform application-support directory.

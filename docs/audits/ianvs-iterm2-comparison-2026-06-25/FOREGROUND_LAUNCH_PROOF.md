# Ianvs Terminal Foreground Launch Proof

Date: 2026-06-25

Scope: implementation and evidence for `T-UX-001`.

## Evidence Commands

```sh
cd example && flutter build macos --debug
cd example && xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'
bash -n tools/check_terminal_manual_matrix_prereqs.sh
cd example && flutter test test/app/macos_app_identity_test.dart test/shell/window_bridge_test.dart
cd example && python3 <direct-open-proof>
```

Latest results in this worktree:

- `flutter build macos --debug`: passed; produced `build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`.
- `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'`: passed; 9 `RunnerTests` cases.
- `bash -n tools/check_terminal_manual_matrix_prereqs.sh`: passed.
- `flutter test test/app/macos_app_identity_test.dart test/shell/window_bridge_test.dart`: passed.
- Direct-open proof: `open_exit=0`, `pgrep_exit=0`, app process observed.
- Current Codex host limitation: `frontmost_after_open=Codex`; explicit AppleScript `activate` exited 0 but `frontmost_after_activate=Codex`.

## Matrix

| Requirement | Result | Evidence |
| --- | --- | --- |
| Avoid relying only on Flutter tool foregrounding | Added app-side launch/reopen activation in `AppDelegate`. | `applicationDidFinishLaunching` schedules foreground activation; `applicationShouldHandleReopen` now foregrounds the preferred window. |
| Prefer the real Flutter window when foregrounding | Added `preferredForegroundWindow(from:)`, prioritizing `MainFlutterWindow`, then any key-capable window. | `testPreferredForegroundWindowChoosesFlutterWindowFirst` and `testPreferredForegroundWindowFallsBackToKeyCapableWindow` pass in `RunnerTests`. |
| Keep native test coverage runnable | Repaired RunnerTests host/module config for the current Dev app identity and aligned scheme/product metadata. | `xcodebuild test ...` now passes instead of failing on stale `Ianvs Terminal.app` / `Ianvs_Terminal` references; `macos_app_identity_test.dart` passes. |
| Separate product failure from host/tooling foreground limits | Expanded `check_terminal_manual_matrix_prereqs.sh` with direct bundle `open`, `open -n` retry, bundle metadata, AppleScript activation, and frontmost result fields. | `bash -n` passes; short preflight output includes Direct bundle `open` and AppleScript app activation sections. |
| Prove the bundle launches | Clean direct-open proof launched the app process with exit 0. | `open_exit=0`; `pgrep` found `Ianvs Terminal Dev`. |

## Current Limit

In this Codex desktop host, the app cannot become the frontmost process even when AppleScript activation succeeds. This means the current environment can prove that the bundle builds, opens, and starts a process, but it cannot prove user-facing foreground ownership. A standard Terminal/iTerm-launched macOS desktop run should use the updated preflight script to distinguish:

- Flutter tool `Failed to foreground app; open returned 1`.
- Direct bundle `open` success/failure.
- AppleScript activation success/failure.
- Actual frontmost app after each step.

The Flutter message itself is emitted by Flutter SDK `MacOSDevice.onAttached()` after it runs `open <applicationBundle>`. The repository changes do not patch the local Flutter SDK; they make Ianvs request foreground ownership from the app side and improve proof collection around the SDK message.

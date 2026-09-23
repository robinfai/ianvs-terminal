# Current Execution Target

The machine-readable authority is
[`CURRENT_EXECUTION_TARGETS.json`](CURRENT_EXECUTION_TARGETS.json). This page
explains the active lane and the product boundary that all new work must keep.

## Active lane

The single active lane is **`runtime-contract-stability`**.

Its purpose is to keep one exact current native/Dart boundary. Each wire slice
has explicit size/version bounds, rejects missing, unknown, case-aliased and
unsupported shapes, and has no predecessor symbol or downgrade route.

The current boundary consists of Runtime Capabilities, Runtime Event Batch,
SessionConfig, Session Request/Response, Host Request/Response, Diagnostic
Event, Terminal Frame Packet and Graphic Asset Packet v1. Previous wire versions do not authorize a predecessor symbol or downgrade route.

## Product boundary

- Profile and Session own reusable configuration and live runtime respectively.
- Terminal Layout persists tab/pane topology and a Relaunch Spec containing only
  profileId and optional cwd. Restoration creates fresh sessions from the current Profile.
- Open Terminal at Folder adds a session at the selected cwd.
- Recordings belong to an independent flat Recording Library.
- Unsupported Workspace structures are outside the runtime contract: the app
  neither imports nor deletes them.
- Toolbelt/completion panels are retired; user diagnostics export remains supported.

The authority is [TERMINAL_PRODUCT_SCOPE.md](TERMINAL_PRODUCT_SCOPE.md) and
[ADR-0003](DECISIONS/ADR-0003-terminal-scope-convergence.md).

## Current invariants

1. The app remains a terminal, not a project/IDE container.
2. Multi-tab and split-pane topology remain first-class terminal behavior.
3. Layout restoration launches fresh PTYs and never restores a dead runtime
   state as if it were launch intent.
4. Environment values and recording paths never enter Relaunch Spec.
5. Live SSH session creation uses the same exact SessionConfig v1 route and also
   requires the current native SSH capability. Replaying an SSH recording uses
   the isolated replay backend and does not open an SSH connection.
6. Optional API configuration sync is an existing capability. A managed team
   cloud, collaboration, plugin runtime/marketplace, project explorer and
   Git/IDE context remain outside the active lane.
7. Linux/Windows product claims remain blocked on real desktop-host evidence.

## Execution order

1. Preserve the exact-current architecture and real-PTY gates.
2. Implement one bounded runtime-contract slice per task without a downgrade
   route.
3. Share negative shape corpora across Dart, Rust and FFI boundaries.
4. Keep the Terminal Layout/Relaunch/Recording separation protected by source,
   repository, controller and Widget tests.
5. Run focused regressions, then the complete `make verify` entrypoint.
6. Update the machine-readable evidence and task result with fresh output.

## Acceptance commands

```bash
cd example && flutter analyze --fatal-infos
cd example && flutter test
dart test test/docs_contract_test.dart
make verify
```

The complete gate remains the final authority. A focused pass is evidence for
the changed slice, not a substitute for `make verify`.

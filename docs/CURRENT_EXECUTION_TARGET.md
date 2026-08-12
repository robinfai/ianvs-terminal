# Current Execution Target

The machine-readable authority is
[`CURRENT_EXECUTION_TARGETS.json`](CURRENT_EXECUTION_TARGETS.json). This page
explains the active lane and the product boundary that all new work must keep.

## Active lane

The single active lane is **`runtime-contract-stability`**.

Its purpose is to keep the native/Dart boundary versioned, capability-driven
and backward compatible. Each wire slice must have explicit size/version
bounds, new-Dart/old-native fallback evidence and old-Dart/new-native evidence
before any legacy symbol is considered for removal.

T-318 through T-330 closed the capability query, Event Envelope,
SessionConfig, Session Request/Response, Host Request/Response, Diagnostic
Event, Terminal Frame Packet and Graphic Asset Packet slices. Other Host
operations, file-download migration, recording wire changes and any old-symbol
removal remain separately scoped.

## Product scope convergence

T-331 supersedes the current-product claims made by T-312 through T-317:

- the durable UI/persistence concept is **Terminal Layout**, not Project
  Workspace;
- the restart contract is **Relaunch Spec** containing only profile,
  command/arguments and cwd;
- **Open Terminal at Folder** adds a terminal at the selected cwd without
  changing an application/project container;
- recordings belong to an independent flat **Recording Library**;
- Project Workspace identity, Recent Workspace and project switching are not
  current capabilities;
- unsupported Workspace/config/recording structures are outside the current
  product contract; runtime code neither imports nor deletes them;
- completion/wiring diagnostics are debug-only; diagnostics export remains a
  user capability.

The authoritative boundary is
[`TERMINAL_PRODUCT_SCOPE.md`](TERMINAL_PRODUCT_SCOPE.md) and the accepted
decision is
[`ADR-0003`](DECISIONS/ADR-0003-terminal-scope-convergence.md).

Historical task documents T-312 through T-317 remain unchanged as archival
implementation evidence only. Their compatibility and migration descriptions
are not product authority and do not override T-331 or the current scope
document.

## Current invariants

1. The app remains a terminal, not a project/IDE container.
2. Multi-tab and split-pane topology remain first-class terminal behavior.
3. Layout restoration launches fresh PTYs and never restores a dead runtime
   state as if it were launch intent.
4. Environment values and recording paths never enter Relaunch Spec.
5. SSH is deferred. A future implementation extends Profile/Session and does
   not restore Project Workspace.
6. Plugin runtime/marketplace, cloud sync, collaboration, project explorer and
   Git/IDE context remain outside the active lane.
7. Linux/Windows product claims remain blocked on real desktop-host evidence.

## Execution order

1. Preserve the complete compatibility and real-PTY gates.
2. Implement one bounded runtime-contract slice per task.
3. Add old/new compatibility tests before changing a preferred wire path.
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

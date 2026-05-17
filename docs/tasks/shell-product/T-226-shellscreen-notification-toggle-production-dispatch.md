# T-226 ShellScreen notification toggle production dispatch

## Milestone

P1/P4 action runtime and policy production wiring

## Intent

Route existing notification behavior through product-visible toggles and the
production action runtime adapter.

## Scope

- Add `ShellScreen` toggles for:
  - command-finished notifications
  - bell notifications
  - inactive-session activity notifications
- Gate the existing notification send paths with those toggles.
- Load and save toggle state through app preferences.
- Add command-menu entries for:
  - `toggleCommandFinishedNotify`
  - `toggleBellNotify`
  - `toggleActivityMonitor`
- Register the three actions in the command-menu production dispatch scope.
- Promote the three actions into the current default required production action
  set.

## Non-goals

- Do not add a silence-monitor action without a concrete `TerminalActionId`.
- Do not change notification delivery providers.
- Do not claim P4 policy wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- Command menu exposes the three notification toggles.
- `toggleCommandFinishedNotify`, `toggleBellNotify`, and
  `toggleActivityMonitor` execute through `ShellActionProductionRuntimeAdapter`.
- Existing command-finished, bell, and inactive-activity notification send paths
  respect the corresponding toggle.
- Notification state persists through app preferences.

## Status

Implemented as persisted `ShellScreen` notification toggle production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

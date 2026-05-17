# T-191 Local terminal Shell UI wiring exports

## Milestone

P0-P5 production wiring integration

## Intent

Provide a stable import surface for future `ShellScreen` production wiring so UI
code uses the high-level bundle, facade, snapshot, diagnostics, and verification
entry points instead of importing low-level manifest internals directly.

## Scope

- Add a shell UI wiring export file for the supported high-level surfaces.
- Export production wiring bundle/router/facade/snapshot entry points.
- Export completion diagnostics/menu/summary entry points.
- Export verification and backlog evidence entry points.

## Deliverables

- `example/lib/features/shell/local_terminal_shell_ui_wiring_exports.dart`
- `example/test/shell/local_terminal_shell_ui_wiring_exports_test.dart`

## Acceptance criteria

- Future UI code has one stable import path for Shell UI wiring diagnostics.
- The export surface favors high-level bundle/facade/snapshot objects.
- The export file does not expose fake action ids or mutate closure state.

## Status

Foundation implemented. Not verified in this session.

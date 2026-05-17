# T-192 Local terminal completion diagnostics panel

## Milestone

P0-P5 production wiring integration

## Intent

Provide a reusable read-only Flutter panel for displaying local terminal
completion blockers from a shell UI wiring snapshot.

## Scope

- Render completion title and blocked counts.
- Render grouped command-menu diagnostics sections.
- Keep entries read-only and non-mutating.
- Export the panel through the shell UI wiring export surface.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_panel.dart`
- `example/test/shell/local_terminal_completion_diagnostics_panel_test.dart`
- Update `local_terminal_shell_ui_wiring_exports.dart`.

## Acceptance criteria

- Pending completion snapshot renders blocked title and counts.
- The panel consumes high-level snapshot/facade data instead of low-level
  manifest internals.
- The panel does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

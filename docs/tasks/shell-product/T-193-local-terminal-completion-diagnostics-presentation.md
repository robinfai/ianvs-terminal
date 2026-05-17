# T-193 Local terminal completion diagnostics presentation

## Milestone

P0-P5 production wiring integration

## Intent

Keep completion diagnostics display strategy out of `ShellScreen` by defining a
small presentation model for inline panel, modal sheet, command-menu section, or
developer-panel rendering.

## Scope

- Build presentation state from `LocalTerminalShellUiWiringSnapshot`.
- Preserve display mode, visibility, title, blocked counts, and total blocked
  count.
- Export the presentation model through the shell UI wiring export surface.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_presentation.dart`
- `example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart`
- Update `local_terminal_shell_ui_wiring_exports.dart`.

## Acceptance criteria

- Pending snapshots produce visible blocked presentation state.
- Presentation mode is explicit and not hard-coded in `ShellScreen`.
- The model remains read-only and does not mutate closure state.

## Status

Foundation implemented. Not verified in this session.

# T-194 Local terminal completion diagnostics presentation resolver

## Milestone

P0-P5 production wiring integration

## Intent

Keep `ShellScreen` display-mode branching out of the production wiring path by
resolving completion diagnostics presentation state from a snapshot and a
preferred display mode.

## Scope

- Add a resolver for `LocalTerminalCompletionDiagnosticsPresentation`.
- Preserve preferred display mode.
- Hide completed diagnostics when requested.
- Export the resolver through the shell UI wiring export surface.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_presentation_resolver.dart`
- `example/test/shell/local_terminal_completion_diagnostics_presentation_resolver_test.dart`
- Update `local_terminal_shell_ui_wiring_exports.dart`.

## Acceptance criteria

- Blocked snapshots use the preferred presentation mode.
- The resolver remains read-only and does not mutate closure state.
- Display-mode policy stays outside future `ShellScreen` wiring.

## Status

Foundation implemented. Not verified in this session.

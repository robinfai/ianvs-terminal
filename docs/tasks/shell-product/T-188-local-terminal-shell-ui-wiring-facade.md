# T-188 Local terminal shell UI wiring facade

## Milestone

P0-P5 production wiring integration

## Intent

Expose production wiring evidence, completion summary, diagnostics, and menu
state from one read-only facade that future `ShellScreen` UI code can consume
after real callbacks are populated.

## Scope

- Build completion evidence report from a production wiring bundle and backlog
  evidence.
- Build completion summary from the same report.
- Build diagnostics view model from the same report.
- Build diagnostics action group and menu model from the diagnostics view model.
- Keep the facade read-only and avoid inferring verification.

## Deliverables

- `example/lib/features/shell/local_terminal_shell_ui_wiring_facade.dart`
- `example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart`
- Update completion diagnostics action group to build from an existing view
  model.
- Update completion diagnostics view model to build from evidence directly.

## Acceptance criteria

- Blocked pending evidence remains blocked through report, summary, diagnostics,
  and menu state.
- All UI-facing diagnostics are derived from the same completion evidence report.
- The facade does not mutate closure state or mark verification as passed.

## Status

Foundation implemented. Not verified in this session.

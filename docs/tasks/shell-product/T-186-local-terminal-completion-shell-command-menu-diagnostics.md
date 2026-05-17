# T-186 Local terminal completion shell command menu diagnostics

## Milestone

P0-P5 cross-milestone execution control

## Intent

Bridge completion diagnostics into the existing shell command menu diagnostics
shape without inventing fake `TerminalActionId` entries.

## Scope

- Adapt completion menu entries into command-menu diagnostic entries.
- Reuse `ShellCommandMenuDisabledReason` for blocked completion entries.
- Preserve completion section title and label.
- Export diagnostics as JSON-compatible data.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_shell_command_menu_diagnostics.dart`
- `example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart`

## Acceptance criteria

- Blocked completion entries produce disabled command-menu diagnostics.
- Diagnostics do not fabricate terminal action ids.
- The adapter remains read-only and does not mutate closure state.

## Status

Foundation implemented. Not verified in this session.

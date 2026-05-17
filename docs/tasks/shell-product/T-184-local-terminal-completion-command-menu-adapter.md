# T-184 Local terminal completion command menu adapter

## Milestone

P0-P5 cross-milestone execution control

## Intent

Adapt completion menu diagnostics into grouped command-menu section data so a
future `ShellScreen` command menu or developer panel can render blocked
completion state without depending on completion-controller internals.

## Scope

- Build grouped command-menu sections from `LocalTerminalCompletionController`.
- Preserve title, subtitle, enabled state, severity, and blocker state.
- Keep diagnostic entries read-only.
- Export grouped menu data as JSON-compatible output.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_command_menu_adapter.dart`
- `example/test/shell/local_terminal_completion_command_menu_adapter_test.dart`

## Acceptance criteria

- Blocked completion diagnostics are grouped into command-menu sections.
- Supplying P0 evidence does not hide remaining P1-P5 blockers.
- The adapter does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

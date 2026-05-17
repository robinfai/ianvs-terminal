# T-181 Local terminal completion diagnostics view model

## Milestone

P0-P5 cross-milestone execution control

## Intent

Expose the completion controller state as UI-friendly diagnostics sections for a
future `ShellScreen` or developer diagnostics surface.

## Scope

- Build diagnostics from `LocalTerminalCompletionController`.
- Render blocked milestones as diagnostic items.
- Render blocked real-wiring backlog tasks as diagnostic items.
- Render blocked verification gates as diagnostic items.
- Export diagnostics as JSON-compatible data.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_view_model.dart`
- `example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart`

## Acceptance criteria

- Pending completion state produces blocked diagnostics.
- Supplying P0 evidence does not hide remaining P1-P5 or verification blockers.
- The view model does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

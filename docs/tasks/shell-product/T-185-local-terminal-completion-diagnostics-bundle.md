# T-185 Local terminal completion diagnostics bundle

## Milestone

P0-P5 cross-milestone execution control

## Intent

Provide a single read-only diagnostics bundle for future UI or developer
surfaces so completion controller state, summary text, menu model, command-menu
sections, and JSON output can be consumed from one entry point.

## Scope

- Bundle `LocalTerminalCompletionController`.
- Expose completion summary text.
- Expose completion menu model.
- Expose grouped command-menu diagnostics.
- Export bundle state as JSON-compatible data.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_bundle.dart`
- `example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart`

## Acceptance criteria

- Pending completion state remains blocked.
- Supplying P0 evidence does not hide remaining P1-P5 or verification blockers.
- The bundle does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

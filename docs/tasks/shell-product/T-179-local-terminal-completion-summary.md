# T-179 Local terminal completion summary

## Milestone

P0-P5 cross-milestone execution control

## Intent

Render current completion evidence as a readable blocked/closeable summary so
developers can see which milestones, real-wiring tasks, and verification gates
still prevent objective closure.

## Scope

- Build a summary from `LocalTerminalCurrentCompletionState`.
- List blocked milestones and their effective blockers.
- List blocked real-wiring backlog tasks.
- List blocked verification gates.
- Export the summary as plain text and JSON-compatible data.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_summary.dart`
- `example/test/shell/local_terminal_completion_summary_test.dart`

## Acceptance criteria

- Blocked current state produces readable blocked summary text.
- Supplying P0 evidence does not hide remaining P1-P5 or verification blockers.
- The summary does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

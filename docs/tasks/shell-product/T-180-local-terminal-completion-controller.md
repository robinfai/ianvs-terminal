# T-180 Local terminal completion controller

## Milestone

P0-P5 cross-milestone execution control

## Intent

Provide a small controller facade that exposes current completion state, summary
text, JSON output, and closure status from one stable entry point for developer
diagnostics or future UI wiring.

## Scope

- Build a pending completion state through the existing conservative defaults.
- Expose `canCloseObjective`.
- Expose readable summary lines and plain text.
- Expose JSON-compatible state and summary output.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_controller.dart`
- `example/test/shell/local_terminal_completion_controller_test.dart`

## Acceptance criteria

- Pending controller state cannot close the objective.
- Supplying P0 evidence does not hide remaining production wiring blockers.
- The controller does not mutate state or infer verification.

## Status

Foundation implemented. Not verified in this session.

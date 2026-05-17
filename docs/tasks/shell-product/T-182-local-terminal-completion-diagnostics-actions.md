# T-182 Local terminal completion diagnostics actions

## Milestone

P0-P5 cross-milestone execution control

## Intent

Convert completion diagnostics into command-menu or developer-panel friendly
read-only action items so blocked objective state can be rendered without
changing closure state.

## Scope

- Build a diagnostics action group from `LocalTerminalCompletionController`.
- Flatten diagnostics sections into read-only action items.
- Preserve section title, item title, description, severity, and enabled state.
- Keep blocked diagnostics disabled so they cannot be mistaken for executable
  fixes.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_diagnostics_actions.dart`
- `example/test/shell/local_terminal_completion_diagnostics_actions_test.dart`

## Acceptance criteria

- Blocked completion state produces disabled diagnostic action items.
- Supplying P0 evidence does not hide remaining P1-P5 blockers.
- The action group does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

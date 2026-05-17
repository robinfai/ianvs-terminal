# T-183 Local terminal completion menu model

## Milestone

P0-P5 cross-milestone execution control

## Intent

Adapt completion diagnostics into a menu-friendly model so a future command menu
or developer diagnostics panel can render blocked objective state without
depending on completion-controller internals.

## Scope

- Build menu entries from `LocalTerminalCompletionController`.
- Preserve section title, label, description, enabled state, and severity.
- Keep blocked completion entries disabled and read-only.
- Export menu state as JSON-compatible data.

## Deliverables

- `example/lib/features/shell/local_terminal_completion_menu_model.dart`
- `example/test/shell/local_terminal_completion_menu_model_test.dart`

## Acceptance criteria

- Blocked completion state produces disabled menu entries.
- Supplying P0 evidence does not hide remaining P1-P5 blockers.
- The model does not mutate closure state or infer verification.

## Status

Foundation implemented. Not verified in this session.

# T-265 Missing backlog command menu diagnostics

## Goal

Add regression coverage proving missing required real-wiring backlog task ids propagate from diagnostics view models into action items, menu entries, and command-menu sections.

## Scope

- Update `example/test/shell/local_terminal_completion_diagnostics_actions_test.dart`.
- Update `example/test/shell/local_terminal_completion_menu_model_test.dart`.
- Update `example/test/shell/local_terminal_completion_command_menu_adapter_test.dart`.
- Use partial backlog evidence to assert missing T-165 through T-168 remain visible downstream.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- Missing required backlog tasks appear in diagnostics action items.
- Missing required backlog tasks appear in menu entries.
- Missing required backlog tasks appear in command-menu sections as blockers.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_diagnostics_actions_test.dart example/test/shell/local_terminal_completion_menu_model_test.dart example/test/shell/local_terminal_completion_command_menu_adapter_test.dart`

## Result

Added downstream diagnostics coverage for missing required real-wiring backlog task ids.

## Verification

Not run. The tests were updated but not executed in this session.

## Remaining Risks

- The updated tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

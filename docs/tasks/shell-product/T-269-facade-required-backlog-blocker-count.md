# T-269 Facade required backlog blocker count

## Goal

Expose the final required backlog blocker count directly from the shell UI wiring facade.

## Scope

- Update `LocalTerminalShellUiWiringFacade` with `requiredBacklogBlockerCount`.
- Include the count in facade JSON.
- Update shell UI wiring facade and snapshot tests to use the facade getter.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- UI callers can read the final required backlog blocker count without reaching into the report.
- Snapshot counts remain aligned with facade/report semantics.

## Verification Commands

- `flutter test example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart`

## Result

Added a facade-level required backlog blocker count and aligned snapshot tests to use it.

## Verification

Not run. The tests were updated but not executed in this session.

## Remaining Risks

- The updated tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

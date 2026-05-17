# T-248 Shell UI wiring facade current evidence regression

## Goal

Add regression coverage for `LocalTerminalShellUiWiringFacade` so the facade-level completion report preserves the current implemented-but-unverified backlog evidence.

## Scope

- Update `example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart`.
- Assert the facade report exposes T-164 as blocked with current production wiring evidence.
- Assert the facade report keeps T-169 blocked by verification blockers.

## Non-goals

- Do not mark verification gates as passed.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The facade layer preserves current backlog evidence independently from the snapshot factory test.
- The facade report remains non-closeable while verification is pending.

## Verification Commands

- `flutter test example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart`

## Result

Added focused regression coverage for current completion evidence at the shell UI wiring facade layer.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Full objective closure still requires the complete verification plan.

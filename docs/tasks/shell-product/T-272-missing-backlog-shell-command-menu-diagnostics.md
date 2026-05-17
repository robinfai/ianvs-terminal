# T-272 Missing backlog shell command-menu diagnostics

## Goal

Keep missing required real-wiring backlog tasks visible after completion
diagnostics are adapted into shell command-menu disabled reasons.

## Scope

- Add shell command-menu diagnostics regression coverage for missing required
  backlog tasks.
- Update task, audit, test-target, and verification-command documentation.

## Non-goals

- Do not change production runtime behavior.
- Do not mark backlog tasks verified.
- Do not run tests, static analysis, formatting, or manual verification.

## Acceptance

- Missing required backlog task ids appear as disabled shell command-menu
  diagnostic entries.
- Disabled reasons preserve the missing-backlog explanation.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart`

## Result

Added focused regression coverage for missing required backlog propagation into
shell command-menu disabled-reason diagnostics.

## Verification

Not run. The test was updated but not executed in this session.

## Remaining Risks

- The updated test may require formatting.
- Final objective closure still requires the full T-169 verification command and
  manual/integration evidence set.

# T-257 Productivity production callback baseline regression

## Goal

Add regression coverage for the current core P3 productivity production callback baseline while keeping advanced productivity gaps visible.

## Scope

- Update `example/test/productivity/shell_productivity_production_callbacks_test.dart`.
- Define the current core required productivity operations for live wiring.
- Assert the core baseline is ready when matching callbacks are supplied.
- Assert default all-operation wiring still reports advanced command-block/output-export gaps when only the core callbacks are supplied.

## Non-goals

- Do not mark P3 verified.
- Do not run tests in this task.
- Do not claim command-block jump, copy-last-output, or save-command-output UI is complete.

## Acceptance

- Prompt navigation, command-output select/copy, recent directory, search, clear search/scrollback, and read-only wiring remain protected by tests.
- Advanced productivity gaps remain visible under the all-operations contract.

## Verification Commands

- `flutter test example/test/productivity/shell_productivity_production_callbacks_test.dart`

## Result

Added focused regression coverage for the core P3 productivity production callback baseline and the remaining advanced productivity gaps.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Runtime and UI behavior still require the full verification plan.

# T-259 Visual production callback baseline regression

## Goal

Add regression coverage for the current core P5 visual production callback baseline while keeping advanced visual gaps visible.

## Scope

- Update `example/test/visual/local_terminal_visual_production_callbacks_test.dart`.
- Define the current core required visual operations for live wiring.
- Assert the core baseline is ready when matching callbacks are supplied.
- Assert default all-operation wiring still reports advanced theme/layout/export/graphics/timestamp/command-pane/editor gaps when only the core callbacks are supplied.

## Non-goals

- Do not mark P5 verified.
- Do not run tests in this task.
- Do not claim theme import/export, layout save/export, graphics storage, timestamps, command pane, or scrollback editor is complete.

## Acceptance

- Theme picker/apply, layout apply, scrollback export, pane visual policy, and split divider policy wiring remain protected by tests.
- Advanced visual gaps remain visible under the all-operations contract.

## Verification Commands

- `flutter test example/test/visual/local_terminal_visual_production_callbacks_test.dart`

## Result

Added focused regression coverage for the core P5 visual production callback baseline and the remaining advanced visual gaps.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Runtime and UI behavior still require the full verification plan.

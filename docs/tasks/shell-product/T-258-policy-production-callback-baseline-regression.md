# T-258 Policy production callback baseline regression

## Goal

Add regression coverage for the current core P4 policy production callback baseline while keeping advanced policy gaps visible.

## Scope

- Update `example/test/policies/local_terminal_policy_production_callbacks_test.dart`.
- Define the current core required policy operations for live wiring.
- Assert the core baseline is ready when matching callbacks are supplied.
- Assert default all-operation wiring still reports advanced notification and hotkey-window gaps when only the core callbacks are supplied.

## Non-goals

- Do not mark P4 verified.
- Do not run tests in this task.
- Do not claim silence/prompt-ready notifications or hotkey-window config/failure UI is complete.

## Acceptance

- Copy, paste, paste history, bracketed paste, large/multiline confirmation, OSC 52, bell/command/activity notifications, and hotkey toggle wiring remain protected by tests.
- Advanced policy gaps remain visible under the all-operations contract.

## Verification Commands

- `flutter test example/test/policies/local_terminal_policy_production_callbacks_test.dart`

## Result

Added focused regression coverage for the core P4 policy production callback baseline and the remaining advanced policy gaps.

## Verification

Not run. The tests were added but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Runtime and UI behavior still require the full verification plan.

# T-157 Local terminal policy production callbacks

## Milestone

P4 - Clipboard, notifications, and hotkey window

## Intent

Define the production callback contract that will let paste, clipboard,
notification, and hotkey-window UI/runtime behavior wire into the P4 policy
foundation.

## Scope

- Add policy production operation ids for clipboard, paste, notification, and
  hotkey-window behavior.
- Add a binding context and structured binding result.
- Add typed nullable callbacks for supported P4 operations.
- Add a wiring object that can run registered callbacks.
- Report missing required policy callbacks before P4 can close.

## Deliverables

- `example/lib/features/policies/local_terminal_policy_production_callbacks.dart`
- `example/test/policies/local_terminal_policy_production_callbacks_test.dart`

## Acceptance criteria

- Registered policy callbacks receive context and return structured results.
- Missing required operations are visible through the wiring object.
- Unsupported operations return a failed result instead of throwing.

## Status

Foundation implemented. Not verified in this session.

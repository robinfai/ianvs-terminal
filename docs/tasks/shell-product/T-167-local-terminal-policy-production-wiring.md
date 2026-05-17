# T-167 Local terminal policy production wiring

## Milestone

P4 - Clipboard, notifications, and hotkey window

## Intent

Populate policy production callbacks from real paste, clipboard, notification,
and hotkey-window behavior.

## Scope

- Wire paste, paste history, bracketed paste, and confirmation callbacks.
- Wire clipboard and OSC 52 callbacks.
- Wire bell, command-finished, activity, silence, and prompt-ready notification
  callbacks.
- Wire hotkey-window toggle, config, and failure-state callbacks.
- Convert policy wiring into a P4 domain summary.

## Deliverables

- `LocalTerminalPolicyProductionWiring` populated from real policy methods.
- P4 `LocalTerminalDomainWiringSummary`.
- Updated completion audit checklist evidence for P4.

## Acceptance criteria

- Required policy operations have registered callbacks.
- Read-only and large/multiline paste cannot bypass policy.
- Notifications honor focus and target policy.
- Required P4 tests and static analysis pass before closure.

## Status

Pending.

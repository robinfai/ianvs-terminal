# T-232 ShellScreen read-only production dispatch

## Milestone

P1/P4 action runtime and policy production wiring

## Intent

Implement per-session read-only mode as a real terminal input guard and route it
through the production action runtime.

## Scope

- Add read-only support to the example `TerminalInputController` wrapper.
- Preserve selection copy while read-only is enabled.
- Block keyboard input, paste, focus reports, mouse reports, and direct
  `ShellScreen` send-input helper paths while a session is read-only.
- Track read-only state per session in `ShellScreen`.
- Add a command-menu entry for enabling/disabling read-only mode.
- Register `toggleReadOnly` in command-menu production dispatch.
- Promote `toggleReadOnly` into the current default required production action
  set.

## Non-goals

- Do not persist read-only state across app restarts.
- Do not add profile-level read-only defaults.
- Do not change terminal runtime APIs.
- Do not claim full P4 policy persistence is complete.

## Deliverables

- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `toggleReadOnly` executes through `ShellActionProductionRuntimeAdapter`.
- Read-only sessions block terminal input from the viewport controller.
- Read-only sessions block `ShellScreen` helper sends such as paste, password
  send, autocomplete suffix send, auto composer send, and profile trigger text.
- Copying selected terminal text remains available.

## Status

Implemented as per-session read-only input guard production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-235 Clear scrollback production dispatch plumbing

## Milestone

P1/P5 action runtime and visual production wiring

## Intent

Wire `clearScrollback` through the Dart runtime and `ShellScreen` production
dispatch without pretending unsupported native backends can clear scrollback.

## Scope

- Add `TerminalRuntimeController.clearScrollback(sessionId)`.
- Use the PTY JSON request channel with request kind
  `terminal.clear_scrollback`.
- Clear the local viewport only when the backend returns `{"cleared": true}`.
- Add command-menu production dispatch for `clearScrollback`.
- Add a command-menu entry for `Clear scrollback`.
- Promote `clearScrollback` into the current required production action set as a
  backend-gated action.

## Non-goals

- Do not implement the native backend clear operation in this task.
- Do not clear only local UI state when the backend does not acknowledge clear.
- Do not send terminal escape bytes to the shell.
- Do not mark the feature verified.

## Deliverables

- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `clearScrollback` executes through `ShellActionProductionRuntimeAdapter`.
- Unsupported backends report that native runtime support is required.
- Local viewport state is cleared only after backend acknowledgement.
- Native backend support remains tracked separately.

## Status

Implemented as Dart/runtime production dispatch plumbing. Native request support
is tracked in T-236.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

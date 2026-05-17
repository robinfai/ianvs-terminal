# T-227 ShellScreen swap pane production dispatch

## Milestone

P1/P2 action runtime and workspace production wiring

## Intent

Implement a real live-session `swapPane` behavior and route it through the
production action runtime.

## Scope

- Add `SessionController.swapActivePaneWithSibling()`.
- Swap the active pane with the next pane, or with the previous pane when the
  active pane is already last.
- Preserve the active session after the swap.
- Add command-menu production dispatch for `swapPane`.
- Add a command-menu entry for `Swap active pane`.
- Promote `swapPane` into the current default required production action set.

## Non-goals

- Do not implement arbitrary drag/drop pane reordering.
- Do not change PTY sessions during pane swapping.
- Do not implement pane resize or zoom in this task.
- Do not claim P2 workspace wiring is complete.

## Deliverables

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `swapPane` changes pane order in live `SessionState`.
- The active pane remains active after the swap.
- Single-pane tabs skip/disable the action.
- `swapPane` executes through `ShellActionProductionRuntimeAdapter`.

## Status

Implemented as live-session pane swap production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-228 ShellScreen zoom pane production dispatch

## Milestone

P1/P2 action runtime and workspace production wiring

## Intent

Implement a real `ShellScreen` pane zoom behavior and route it through the
production action runtime.

## Scope

- Track a zoomed pane session id in `ShellScreen`.
- Render only the zoomed pane in the terminal workspace when zoom is active.
- Add command-menu production dispatch for `zoomPane`.
- Add a command-menu entry for zooming/unzooming the active pane.
- Promote `zoomPane` into the current default required production action set.

## Non-goals

- Do not persist zoom state to workspace storage in this task.
- Do not change PTY sessions or pane order.
- Do not implement pane resize in this task.
- Do not claim P2 workspace wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `zoomPane` executes through `ShellActionProductionRuntimeAdapter`.
- Multi-pane tabs can toggle between full split view and a single zoomed pane.
- Single-pane tabs skip/disable zoom.
- The active pane remains focused after toggling zoom.

## Status

Implemented as `ShellScreen` presentation-level pane zoom production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

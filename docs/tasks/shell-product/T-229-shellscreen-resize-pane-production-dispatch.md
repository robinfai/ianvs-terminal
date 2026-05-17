# T-229 ShellScreen resize pane production dispatch

## Milestone

P1/P2 action runtime and workspace production wiring

## Intent

Implement a concrete `resizePane` behavior for the current flat split UI and
route it through the production action runtime.

## Scope

- Track presentation flex weights per pane session in `ShellScreen`.
- Render split panes with the stored flex weight.
- Implement `Grow active pane` as the current concrete resize behavior.
- Register the action through the `resizePaneRight` callback alias, which
  resolves to `TerminalActionId.resizePane`.
- Add a command-menu entry for `Grow active pane`.
- Promote `resizePane` into the current default required production action set.

## Non-goals

- Do not implement directional shrink/grow controls in this task.
- Do not persist pane size ratios.
- Do not change PTY size scheduling beyond the existing viewport measurement
  behavior.
- Do not claim full P2 workspace persistence is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `resizePane` executes through `ShellActionProductionRuntimeAdapter`.
- Multi-pane tabs can increase the active pane's rendered flex.
- Single-pane tabs skip/disable the action.
- Existing viewport resize measurement continues to drive runtime resize after
  layout changes.

## Status

Implemented as presentation-level active-pane grow production dispatch.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

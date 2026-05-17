# T-216 ShellScreen copy command output production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Route the existing copy-last-command-output behavior through the production
action runtime adapter.

## Scope

- Add `copyCommandOutput` to the command-menu production dispatch scope.
- Reuse the existing command-output selection behavior.
- Copy the selected command output through the existing selection copy path.
- Promote `copyCommandOutput` into the current default required production
  action set.

## Non-goals

- Do not change shell integration prompt-mark detection.
- Do not change terminal selection or clipboard behavior.
- Do not migrate shortcut dispatch for this action in this task.
- Do not remove legacy switch fallback.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- `copyCommandOutput` can execute through `ShellActionProductionRuntimeAdapter`
  from the command-menu path.
- Missing active sessions skip action execution.
- Missing command output restores focus and skips action execution.
- Successful selection uses the existing `_copySelection` path.

## Status

Implemented as command-menu production dispatch coverage for
`copyCommandOutput`.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-223 ShellScreen theme picker production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Expose and route `openThemePicker` through the production action runtime using
the existing Defaults & appearance UI.

## Scope

- Add a command-menu entry for `openThemePicker`.
- Register `openThemePicker` in the command-menu production dispatch scope.
- Open the existing Defaults & appearance dialog as the concrete appearance
  control surface.
- Promote `openThemePicker` into the current default required production action
  set.

## Non-goals

- Do not create a separate theme-only dialog in this task.
- Do not migrate `applyTheme`.
- Do not implement layout templates or scrollback export.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- Command menu exposes `Theme picker`.
- `openThemePicker` executes through `ShellActionProductionRuntimeAdapter`.
- The action opens the existing Defaults & appearance UI.
- The current default required production action set includes `openThemePicker`.

## Status

Implemented as command-menu production dispatch coverage for `openThemePicker`.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

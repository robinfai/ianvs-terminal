# T-212 ShellScreen tooling production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Move existing command-menu tooling entry points through the production action
runtime adapter while keeping current `ShellScreen` behavior and fallback paths.

## Scope

- Add production callback fields for:
  - `toolbelt`
  - `advancedPaste`
  - `shellIntegrationUtilities`
  - `tmuxIntegration`
  - `coprocess`
  - `annotations`
  - `capturedOutput`
  - `passwordManager`
- Extend command-menu production dispatch with those callbacks.
- Preserve active-session guards and existing focus-restoration behavior.
- Preserve scoped action sets and legacy switch fallback.

## Non-goals

- Do not migrate shortcut dispatch for these tooling actions in this task.
- Do not change advanced paste, tmux, coprocess, annotations, captured output,
  or password manager behavior.
- Do not remove legacy switch branches.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_callbacks.dart`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Command-menu tooling actions execute through
  `ShellActionProductionRuntimeAdapter` when they are part of the scoped action
  set.
- Missing active sessions continue to skip action execution.
- Existing focus restoration remains in place for modal/tooling exits.
- Unscoped actions continue through the original switch paths.

## Status

Implemented as the command-menu tooling production dispatch expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

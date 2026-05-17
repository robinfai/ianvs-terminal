# T-210 ShellScreen shortcut UI action production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Continue reducing the command-menu/shortcut dispatch split by routing the next
safe shortcut UI actions through the production action runtime adapter.

## Scope

- Extend shortcut production dispatch with:
  - `autocomplete`
  - `openDefaults`
- Preserve scoped shortcut action sets and legacy switch fallback.
- Preserve active-session guard behavior for autocomplete.
- Preserve the existing defaults/appearance sheet behavior.

## Non-goals

- Do not migrate paste history, copy mode, instant replay, copy, paste, or tab
  activation in this task.
- Do not change shortcut resolution rules.
- Do not remove legacy switch branches.
- Do not claim shortcut production wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- `autocomplete` shortcut dispatch executes through
  `ShellActionProductionRuntimeAdapter` when an active session exists.
- `openDefaults` shortcut dispatch executes through
  `ShellActionProductionRuntimeAdapter`.
- Unscoped shortcut actions continue through the original switch path.

## Status

Implemented as the second shortcut production dispatch expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

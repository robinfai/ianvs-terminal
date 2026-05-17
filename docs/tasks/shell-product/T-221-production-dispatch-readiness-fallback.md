# T-221 Production dispatch readiness fallback

## Milestone

P1 action runtime production wiring

## Intent

Keep legacy `ShellScreen` switch dispatch usable as a safety fallback when a
scoped production adapter is not ready.

## Scope

- Require `ShellActionProductionRuntimeAdapter.isReady` before command-menu
  production dispatch short-circuits the legacy switch.
- Require `isReady` before shortcut production dispatch marks a key event
  handled.
- Let command-menu dispatch fall back to the legacy switch when production
  execution does not complete.

## Non-goals

- Do not change action scopes in this task.
- Do not remove legacy switch branches.
- Do not run verification commands.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- A not-ready scoped production adapter does not swallow command-menu actions.
- A not-ready scoped production adapter does not swallow shortcut actions.
- Completed production actions still short-circuit the legacy switch.
- Remaining fallback behavior stays intact for unscoped or not-ready actions.

## Status

Implemented as a production dispatch fallback safety fix.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

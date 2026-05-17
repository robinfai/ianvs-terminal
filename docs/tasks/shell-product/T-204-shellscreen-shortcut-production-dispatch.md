# T-204 ShellScreen shortcut production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Route the first low-risk keyboard shortcut actions in `ShellScreen` through the
production action runtime adapter so command-menu and shortcut dispatch start
sharing the same production wiring path.

## Scope

- Build a scoped `ShellActionProductionRuntimeAdapter` in the shortcut dispatch
  path.
- Register only synchronous, already-implemented shortcut actions:
  - `newTab`
  - `splitRight`
  - `splitDown`
- Keep shortcut parsing, repeat-key handling, command-menu modal guards, and
  existing fallback switch behavior unchanged.

## Non-goals

- Do not migrate copy, paste, paste history, search, autocomplete, command menu,
  settings, or policy-sensitive actions in this task.
- Do not remove the legacy switch branches until broader action runtime coverage
  is verified.
- Do not claim global shortcut wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- The three scoped shortcut actions execute through
  `ShellActionProductionRuntimeAdapter`.
- Missing default profile or active session guards remain equivalent to the
  previous switch behavior.
- Unscoped shortcut actions continue through the existing switch path.

## Status

Implemented as the first shortcut production dispatch bridge.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

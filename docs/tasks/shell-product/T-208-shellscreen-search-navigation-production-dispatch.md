# T-208 ShellScreen search and navigation production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Move the next safe set of existing `ShellScreen` search and shell-navigation
actions through the production action runtime adapter.

## Scope

- Extend command-menu production dispatch with:
  - `searchScrollback` -> `search`
  - `previousPrompt`
  - `nextPrompt`
  - `selectCommandOutput`
- Extend shortcut production dispatch with:
  - `searchScrollback` -> `search`
  - `previousPrompt`
  - `nextPrompt`
- Preserve scoped action sets and legacy switch fallback for unscoped actions.
- Preserve active-session guards and focus restoration behavior.

## Non-goals

- Do not migrate global search, autocomplete, auto composer, shell integration
  sheets, tmux, coprocess, annotations, captured output, password manager, or
  profile/defaults actions in this task.
- Do not add new search sub-action `TerminalActionId`s.
- Do not remove legacy switch branches.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Scoped search/navigation actions execute through
  `ShellActionProductionRuntimeAdapter`.
- Active-session guards remain explicit.
- `selectCommandOutput` keeps the existing behavior of restoring session focus
  when no command output is selected.
- Unscoped actions continue through the original switch paths.

## Status

Implemented as the first search/navigation production dispatch expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-207 ShellScreen aliased action production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Use the production action-name resolver to migrate the next safe set of
`ShellScreen` actions whose callback names intentionally differ from
`TerminalActionId` names.

## Scope

- Extend command-menu production dispatch with:
  - `closeTab` -> `closeActiveTab`
  - `toggleHotkeyWindow` -> `hotkeyWindow`
- Extend shortcut production dispatch with:
  - `closeTab` -> `closeActiveTab`
  - `toggleCommandPalette` -> `openCommandMenu`
  - `toggleHotkeyWindow` -> `hotkeyWindow`
- Preserve scoped action sets so partial production wiring remains explicit.
- Preserve legacy switch fallback for actions outside the scoped sets.

## Non-goals

- Do not migrate paste policy, search, autocomplete, profile/defaults, or visual
  actions in this task.
- Do not remove legacy switch branches.
- Do not claim global P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Aliased actions execute through `ShellActionProductionRuntimeAdapter` when
  they are part of the scoped action set.
- Guard behavior for missing active sessions remains explicit.
- Opening the command menu from shortcuts continues to be asynchronous and marks
  the key event handled.
- Remaining unscoped actions continue through the original switch paths.

## Status

Implemented as the first aliased-action production dispatch expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

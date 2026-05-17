# T-205 ShellScreen production dispatch helper

## Milestone

P1 action runtime production wiring

## Intent

Reduce duplication introduced by the first command-menu and shortcut production
dispatch patches so future action migrations use one local `ShellScreen`
production dispatch helper instead of repeating adapter construction and binding
checks.

## Scope

- Add a scoped production adapter builder inside `ShellScreen`.
- Add helper methods for awaited command-menu dispatch and unawaited shortcut
  dispatch.
- Keep the already-migrated action sets unchanged:
  - command menu: `newTab`, `splitRight`, `splitDown`, `copy`, `paste`,
    `pasteHistory`
  - shortcuts: `newTab`, `splitRight`, `splitDown`
- Preserve legacy switch fallback for all unscoped actions.

## Non-goals

- Do not migrate additional actions in this task.
- Do not change shortcut resolution, command-menu presentation, terminal input,
  paste policy, or session runtime behavior.
- Do not mark P1 production action wiring complete.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Both command-menu and shortcut production dispatch paths use the same local
  helper for scoped adapter construction.
- Command-menu production actions continue to await dispatch before returning.
- Shortcut production actions continue to dispatch asynchronously and mark the
  key event handled.
- Partial action coverage remains explicit through scoped action sets.

## Status

Implemented as a local `ShellScreen` production dispatch helper.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

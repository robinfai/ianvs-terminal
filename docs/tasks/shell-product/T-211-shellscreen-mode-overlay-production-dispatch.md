# T-211 ShellScreen mode and overlay production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Move the next set of existing mode and overlay actions through the production
action runtime adapter while preserving current `ShellScreen` behavior.

## Scope

- Add production callback fields for:
  - `copyMode`
  - `instantReplay`
- Reuse the existing `pasteHistory` production callback.
- Extend command-menu production dispatch with:
  - `copyMode`
  - `pasteHistory`
  - `instantReplay`
- Extend shortcut production dispatch with:
  - `copyMode`
  - `pasteHistory`
  - `instantReplay`
- Preserve active-session guards and existing overlay entry behavior.

## Non-goals

- Do not migrate copy/paste terminal input dispatch in this task.
- Do not change copy-mode selection semantics.
- Do not change paste history or instant replay storage behavior.
- Do not remove legacy switch branches.
- Do not claim P1 action runtime wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_callbacks.dart`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- `copyMode`, `pasteHistory`, and `instantReplay` can execute through
  `ShellActionProductionRuntimeAdapter` from both command-menu and shortcut
  paths.
- Missing active sessions continue to skip action execution.
- Unscoped actions continue through the original switch paths.

## Status

Implemented as the mode/overlay production dispatch expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

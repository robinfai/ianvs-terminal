# T-140 Shell command menu diagnostics

## Milestone

P1 - Local terminal action foundation

## Intent

Expose command menu availability and runtime execution failures as a UI-facing
diagnostics state so ShellScreen can render actionable reasons instead of
silently disabling local terminal actions.

## Scope

- Add a diagnostics state that summarizes enabled and disabled command menu
  items.
- Preserve action id, label, shortcut hint, disabled title, and disabled
  description for UI rendering.
- Convert the last external action executor error into the existing shell action
  error diagnostic model.
- Keep the diagnostics layer read-only and side-effect free.

## Deliverables

- `example/lib/features/shell/shell_command_menu_diagnostics.dart`
- `example/test/shell/shell_command_menu_diagnostics_test.dart`

## Acceptance criteria

- Disabled command menu items can be listed without re-running availability
  checks.
- A single action diagnostic can be looked up by `TerminalActionId`.
- Runtime executor failures are surfaced through the existing
  `ShellActionErrorDiagnostic` model.
- No production action execution behavior changes.

## Status

Foundation implemented. Not verified in this session.

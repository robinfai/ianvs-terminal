# T-238 Notification toggle preference persistence

## Milestone

P4 policy production wiring

## Intent

Persist command-finished, bell, and inactive-activity notification toggles using
the existing app preferences document and repository.

## Scope

- Add `TerminalAppNotifications` to app preferences.
- Default missing notification preferences to enabled for backward
  compatibility.
- Load notification preferences when `ShellScreen` initializes.
- Save notification preferences whenever a notification toggle changes.
- Keep delivery provider behavior unchanged.

## Non-goals

- Do not add a silence-monitor action without a concrete `TerminalActionId`.
- Do not change notification delivery implementation.
- Do not run verification commands.

## Deliverables

- `example/lib/features/preferences/app_preferences_models.dart`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Existing preference files without notification fields continue to load.
- Toggling command-finished, bell, or activity notifications writes app
  preferences.
- `ShellScreen` restores saved notification toggles on initialization.

## Status

Implemented as app-preferences persistence for notification toggles.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

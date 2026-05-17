# T-230 P1 production action baseline closure

## Milestone

P1 action runtime production wiring

## Intent

Record the current P1 production action baseline after the staged `ShellScreen`
production dispatch work, and separate implemented baseline actions from
remaining blockers.

## Implemented required baseline

- `newTab`
- `closeTab` -> `closeActiveTab`
- `reopenClosedTab`
- `duplicateCurrentCwd`
- `toolbelt`
- `splitRight`
- `splitDown`
- `closePane`
- `focusNextPane`
- `focusPreviousPane`
- `resizePane`
- `swapPane`
- `zoomPane`
- `copy`
- `copyCommandOutput`
- `copyMode`
- `paste`
- `advancedPaste`
- `pasteHistory`
- `instantReplay`
- `toggleReadOnly`
- `clearScrollback`
- `globalSearch`
- `autocomplete`
- `autoComposer`
- `searchScrollback` -> `search`
- `previousPrompt`
- `nextPrompt`
- `selectCommandOutput`
- `shellIntegrationUtilities`
- `openRecentDirectory`
- `tmuxIntegration`
- `coprocess`
- `annotations`
- `capturedOutput`
- `passwordManager`
- `toggleCommandPalette` -> `openCommandMenu`
- `toggleHotkeyWindow` -> `hotkeyWindow`
- `openDefaults`
- `defaults`
- `profiles`
- `dynamicProfiles`
- `openThemePicker`
- `applyLayoutTemplate`
- `exportScrollback`
- `toggleCommandFinishedNotify`
- `toggleBellNotify`
- `toggleActivityMonitor`

## Remaining blockers

No action-level implementation blocker is currently listed. Verification remains
pending.

## Non-goals

- Do not mark P1 verified.
- Do not claim P2-P5 completion.
- Do not treat the required baseline as a replacement for tests, analysis, or
  manual UI verification.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`
- `example/lib/features/shell/shell_action_production_action_name_resolver.dart`
- `example/lib/features/shell/shell_action_production_callbacks.dart`
- `example/lib/features/shell/local_terminal_current_completion_state.dart`
- `example/lib/features/shell/local_terminal_real_wiring_backlog_evidence.dart`

## Acceptance criteria

- The current required production action baseline is explicitly listed.
- Known blockers remain visible and are not silently promoted.
- Verification remains pending until analyze/tests/manual UI checks are run.

## Status

Recorded as the current unverified P1 production action baseline closure.
`T-239` also wires the completion-backlog evidence so implemented production
groups remain blocked on verification instead of being reported as pending.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this record.

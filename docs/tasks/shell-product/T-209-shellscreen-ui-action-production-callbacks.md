# T-209 ShellScreen UI action production callbacks

## Milestone

P1 action runtime production wiring

## Intent

Extend production action callbacks and migrate the next command-menu UI actions
through the production action runtime adapter.

## Scope

- Add production callback fields for:
  - `globalSearch`
  - `autocomplete`
  - `autoComposer`
  - `openDefaults`
  - `defaults`
  - `profiles`
  - `dynamicProfiles`
- Register matching command-menu production callbacks in `ShellScreen`.
- Preserve scoped command-menu action sets and legacy switch fallback.
- Preserve active-session and tab-count guards.

## Non-goals

- Do not migrate shortcut dispatch in this task.
- Do not change default production action-set requirements.
- Do not change profile/defaults sheet behavior.
- Do not claim P1 production action wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_callbacks.dart`
- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- Command-menu actions for global search, autocomplete, auto composer,
  defaults, profiles, and dynamic profile import can execute through
  `ShellActionProductionRuntimeAdapter`.
- Guards for missing active sessions or empty tab lists remain explicit.
- Unscoped actions continue through the original switch paths.

## Status

Implemented as a command-menu UI action production callback expansion.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

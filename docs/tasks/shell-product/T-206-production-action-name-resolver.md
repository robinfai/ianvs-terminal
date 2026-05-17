# T-206 Production action name resolver

## Milestone

P1 action runtime production wiring

## Intent

Remove the structural mismatch between production callback names and
`TerminalActionId` names so production wiring audits can distinguish real missing
bindings from known naming aliases.

## Scope

- Add a production action-name resolver.
- Resolve known equivalent names:
  - `closeTab` -> `closeActiveTab`
  - `searchScrollback` -> `search`
  - `toggleCommandPalette` -> `openCommandMenu`
  - `toggleHotkeyWindow` -> `hotkeyWindow`
- Use the resolver in production binding construction.
- Use the resolver in production action-set required/optional action lookup.
- Remove required default action names that do not currently have
  `TerminalActionId` equivalents:
  - `nextSearchMatch`
  - `previousSearchMatch`
  - `clearSearch`

## Non-goals

- Do not add new terminal actions in this task.
- Do not migrate additional `ShellScreen` behavior.
- Do not treat search sub-actions as production-dispatch complete until they have
  explicit `TerminalActionId` coverage or a separate dispatch model.
- Do not claim P1 production action wiring is complete.

## Deliverables

- `example/lib/features/shell/shell_action_production_action_name_resolver.dart`
- `example/lib/features/shell/shell_action_production_binding_builder.dart`
- `example/lib/features/shell/shell_action_production_action_set.dart`

## Acceptance criteria

- Production binding builder accepts known callback-name aliases.
- Production action-set audits resolve known aliases before marking names
  unknown.
- Impossible required names are no longer part of the default production action
  set.
- Remaining missing bindings continue to surface as production wiring blockers.

## Status

Implemented as a naming resolver and default action-set cleanup.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

# T-203 ShellScreen command menu production dispatch

## Milestone

P1 action runtime production wiring

## Intent

Move the first safe subset of existing `ShellScreen` command-menu actions
through the production action runtime adapter without changing their user-visible
behavior.

## Scope

- Build a `ShellActionProductionRuntimeAdapter` inside the command-menu dispatch
  path.
- Register only actions that already have direct `ShellScreen` behavior and
  matching `TerminalActionId` names:
  - `newTab`
  - `splitRight`
  - `splitDown`
  - `copy`
  - `paste`
  - `pasteHistory`
- Leave unregistered command-menu actions on the existing switch dispatch path.
- Preserve existing guard behavior for missing default profile, missing active
  session, or missing selection controller.

## Non-goals

- Do not migrate keyboard shortcut dispatch in this task.
- Do not claim default production action wiring is complete.
- Do not register actions whose production callback names do not currently match
  `TerminalActionId` names.
- Do not change terminal input, PTY, paste policy, notification, or layout
  behavior.

## Deliverables

- `example/lib/features/shell/shell_screen.dart`

## Acceptance criteria

- The command menu executes the six scoped actions through
  `ShellActionProductionRuntimeAdapter`.
- Unsupported or not-yet-migrated menu actions continue through the previous
  switch path.
- The adapter action set is intentionally scoped to the registered production
  callbacks so partial wiring is not mistaken for global completion.

## Status

Implemented as an initial production dispatch bridge for command-menu actions.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this patch.

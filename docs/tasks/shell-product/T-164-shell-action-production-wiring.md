# T-164 Shell action production wiring

## Milestone

P1 - Local terminal action foundation

## Intent

Populate the typed shell action production callbacks from the real shell UI and
runtime dispatch path so P1 action/config behavior moves from foundation to
production wiring.

## Scope

- Instantiate `ShellActionProductionCallbacks` from real shell action handlers.
- Connect the production runtime adapter or executor to the shell action dispatch
  path.
- Route command menu and shortcut-triggered actions through the production wiring
  state.
- Surface production wiring and dispatch diagnostics when actions fail.

## Deliverables

- Production callback population in the shell UI/runtime layer.
- `ShellActionProductionClosureManifest` populated from real wiring evidence.
- Updated completion audit checklist evidence for P1.

## Acceptance criteria

- Required P1 production actions have registered callbacks.
- Blocking production binding diagnostics are empty.
- Command menu and shortcut dispatch do not bypass the action registry.
- Required P1 tests and static analysis pass before closure.

## Status

Pending.

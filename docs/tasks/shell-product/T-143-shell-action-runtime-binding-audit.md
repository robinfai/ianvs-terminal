# T-143 Shell action runtime binding audit

## Milestone

P1 - Local terminal action foundation

## Intent

Add a structured audit object for production action bindings so the UI/runtime
wiring phase can prove which required `TerminalActionId` callbacks are still
missing.

## Scope

- Compare required production actions against registered runtime bindings.
- Report missing required bindings.
- Report unplanned registered bindings so extra callbacks do not silently drift
  outside the supported action set.

## Deliverables

- `example/lib/features/shell/shell_action_runtime_binding_audit.dart`
- `example/test/shell/shell_action_runtime_binding_audit_test.dart`

## Acceptance criteria

- Missing required actions are exposed as both a set and diagnostic items.
- Unplanned registered bindings are exposed as both a set and diagnostic items.
- Completion is true only when no required bindings are missing.

## Status

Foundation implemented. Not verified in this session.

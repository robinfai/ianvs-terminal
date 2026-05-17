# T-146 Shell action production binding diagnostics

## Milestone

P1 - Local terminal action foundation

## Intent

Convert production binding build/audit results into stable diagnostic items that
can be rendered by a settings panel, developer surface, or completion audit.

## Scope

- Report unknown required action names as blocking diagnostics.
- Report unknown optional action names as advisory diagnostics.
- Report unknown production callback names as blocking diagnostics.
- Report missing required bindings as blocking diagnostics.
- Report unplanned registered bindings as advisory diagnostics.

## Deliverables

- `example/lib/features/shell/shell_action_production_binding_diagnostics.dart`
- `example/test/shell/shell_action_production_binding_diagnostics_test.dart`

## Acceptance criteria

- A clean build/audit result has no diagnostic items.
- Blocking diagnostics prevent production wiring closure.
- Advisory diagnostics remain visible without blocking core closure.

## Status

Foundation implemented. Not verified in this session.

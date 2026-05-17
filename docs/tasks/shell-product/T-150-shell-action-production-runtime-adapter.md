# T-150 Shell action production runtime adapter

## Milestone

P1 - Local terminal action foundation

## Intent

Bridge typed production callbacks into an external-executor function shape that
runtime dispatch can call without depending on production wiring internals.

## Scope

- Build a production executor from typed callbacks and the production action set.
- Expose readiness from the production executor.
- Adapt `ShellActionBindingContext` into production executor invocation.
- Return only `ShellActionBindingResult` to the runtime boundary.

## Deliverables

- `example/lib/features/shell/shell_action_production_runtime_adapter.dart`
- `example/test/shell/shell_action_production_runtime_adapter_test.dart`

## Acceptance criteria

- Ready production callbacks can be invoked through the external executor
  function.
- Unready production wiring returns an unavailable binding result.
- Runtime-facing callers do not need to know about binding build results,
  binding audits, or diagnostics internals.

## Status

Foundation implemented. Not verified in this session.

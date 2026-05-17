# T-170 Local terminal action domain router

## Milestone

P1-P5 production wiring integration

## Intent

Route P1 shell action production callbacks through P2-P5 domain wiring so real
`ShellScreen` callbacks can be populated once per domain and reused by the
action layer.

## Scope

- Convert workspace production wiring into shell action callbacks.
- Convert productivity production wiring into shell action callbacks.
- Convert policy production wiring into shell action callbacks.
- Convert visual production wiring into shell action callbacks.
- Omit callbacks for missing domain operations so P1 action audits still expose
  gaps.

## Deliverables

- `example/lib/features/shell/local_terminal_action_domain_router.dart`
- `example/test/shell/local_terminal_action_domain_router_test.dart`

## Acceptance criteria

- Registered domain callbacks can be invoked through shell action bindings.
- Missing domain operations do not produce fake action callbacks.
- Domain failure codes are mapped into shell action binding failure codes.

## Status

Foundation implemented. Not verified in this session.

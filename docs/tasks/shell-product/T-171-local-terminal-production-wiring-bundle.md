# T-171 Local terminal production wiring bundle

## Milestone

P0-P5 production wiring integration

## Intent

Provide a single bundle that assembles P0 boundary state, P2-P5 domain
production callbacks, the P1 action-domain router, the P1 action closure
manifest, P2-P5 domain summaries, and the cross-milestone production wiring
manifest.

## Scope

- Build workspace, productivity, policy, and visual production wiring from typed
  callbacks.
- Route domain wiring into shell action production callbacks.
- Build P1 action wiring and closure state from routed callbacks.
- Build P2-P5 domain summaries.
- Build the cross-milestone production wiring manifest.

## Deliverables

- `example/lib/features/shell/local_terminal_production_wiring_bundle.dart`
- `example/test/shell/local_terminal_production_wiring_bundle_test.dart`

## Acceptance criteria

- Ready domain callbacks can produce a closeable cross-milestone manifest when
  verification status is explicitly marked passed.
- Missing domain callbacks remain visible in both domain and action closure
  results.
- The bundle does not default tests or analysis to passing.

## Status

Foundation implemented. Not verified in this session.

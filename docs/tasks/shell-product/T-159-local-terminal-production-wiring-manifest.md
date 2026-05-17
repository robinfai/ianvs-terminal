# T-159 Local terminal production wiring manifest

## Milestone

P1-P5 cross-milestone execution control

## Intent

Prevent any single milestone from being treated as sufficient completion by
combining P1-P5 production wiring readiness, tests, analysis, and blockers into
one closure manifest.

## Scope

- Add a production milestone manifest with wiring, test, analysis, blocker, and
  note fields.
- Add a cross-milestone manifest that can close only when every included
  milestone can close.
- Expose blocked milestones and JSON-compatible output.

## Deliverables

- `example/lib/features/shell/local_terminal_production_wiring_manifest.dart`
- `example/test/shell/local_terminal_production_wiring_manifest_test.dart`

## Acceptance criteria

- The manifest closes only when all included milestones can close.
- Missing tests or analysis remain visible as blockers.
- Output is JSON-compatible for completion audits or diagnostics.

## Status

Foundation implemented. Not verified in this session.

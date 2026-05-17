# T-161 Local terminal production wiring manifest builder

## Milestone

P1-P5 cross-milestone execution control

## Intent

Provide the single builder that combines the P1 action closure manifest and
P2-P5 domain wiring summaries into the cross-milestone production wiring
manifest.

## Scope

- Convert the P1 action closure manifest into a P1 milestone manifest.
- Convert P2-P5 domain summaries into milestone manifests.
- Treat missing domain summaries as blockers.
- Require explicit test and static-analysis status for each P2-P5 domain.

## Deliverables

- `example/lib/features/shell/local_terminal_production_wiring_manifest_builder.dart`
- `example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart`

## Acceptance criteria

- Missing domain summaries prevent overall closure.
- Ready and verified domain summaries can produce a closeable overall manifest.
- The builder never defaults tests or analysis to passing.

## Status

Foundation implemented. Not verified in this session.

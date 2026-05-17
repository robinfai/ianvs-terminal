# T-169 Local terminal verification and closure

## Milestone

P0-P5 cross-milestone execution control

## Intent

Collect the real verification evidence required to close the local terminal
P0-P5 execution plan.

## Scope

- Populate P0-P5 closure manifests from real production wiring.
- Run and record required unit/widget/integration tests.
- Run and record static analysis.
- Run and record formatting confirmation.
- Collect manual or integration evidence for local shell smoke, paste/focus
  safety, multipane behavior, notification behavior, and hotkey-window failure
  paths.
- Update the completion audit checklist with real evidence.

## Deliverables

- Populated cross-milestone production wiring manifest with `canCloseAll: true`.
- Updated `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`.
- Recorded command/manual evidence.

## Acceptance criteria

- Every P0-P5 milestone manifest can close.
- Tests, static analysis, and formatting are recorded as passed.
- Manual/integration gaps are either closed or explicitly accepted as blockers.
- The completion audit checklist has no remaining blockers.

## Status

Pending.

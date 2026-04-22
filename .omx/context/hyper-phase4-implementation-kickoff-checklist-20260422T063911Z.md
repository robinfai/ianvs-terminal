# Context Snapshot — Hyper Phase 4 Implementation Kickoff Checklist

## Task Statement
Once the formal Phase 4 PRD and test-spec exist, create the actual implementation task and move the default repo lane from Phase 4 planning to Phase 4 implementation.

## Inputs
- `.omx/plans/prd-hyper-like-phase4-interaction-polish.md`
- `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`
- `docs/tasks/TEMPLATE.md`
- `docs/TESTING.md`
- `.omx/context/defaultprofileid-deprecation-review-parking-lot-20260421T094305Z.md`

## Kickoff Gate
- Both formal Phase 4 planning files exist.
- `T-055` is closed.
- No higher-priority lifecycle, focus, or startup regression is overriding the main lane.
- The `defaultProfileId` deprecation review remains parked and is not opened in this round.

## Kickoff Sequence
1. Confirm the formal Phase 4 PRD and test-spec both exist and their wording is locked.
2. Create `docs/tasks/T-056-hyper-phase4-interaction-polish.md` from `docs/tasks/TEMPLATE.md`.
3. Pull `Goal`, `Scope`, `Non-goals`, and `Functional Acceptance` from the formal PRD.
4. Pull `Verification Commands`, `Manual QA`, and `Done When` from the formal test-spec.
5. Keep the implementation task limited to the three approved slices:
   - session start / exit presentation
   - focus transition clarity
   - behavior-preserving feedback
6. In `Risks / Follow-ups`, state that:
   - the `defaultProfileId` deprecation review is not part of this task
   - any non-Phase-4 finding discovered during implementation must split into a focused task instead of being absorbed into `T-056`
7. Record in `.omx/notepad.md` that Phase 4 has moved from the planning lane to the implementation lane.

## Task Shape Rules
- Default to one implementation task: `docs/tasks/T-056-hyper-phase4-interaction-polish.md`.
- Do not pre-split multiple Phase 4 implementation tasks unless the formal PRD or test-spec explicitly requires it.
- Do not create the formal `defaultProfileId` review artifact or any deprecation implementation task during kickoff.

## Parking Lot After Kickoff
- Keep the `defaultProfileId` deprecation review parked.
- Revisit that parked review only after `T-056` is complete or clearly no longer blocks the main lane.
- When that gate opens, continue with `.omx/context/defaultprofileid-deprecation-review-kickoff-checklist-20260422T064230Z.md` instead of opening the parked context directly.

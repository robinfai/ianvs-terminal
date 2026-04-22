# Context Snapshot — `defaultProfileId` Deprecation Review Kickoff Checklist

## Task Statement
Once `T-055` is closed, the formal Phase 4 planning pair exists, and `T-056` is complete or no longer blocks the main lane, convert the parked `defaultProfileId` deprecation topic into the formal review artifact.

## Inputs
- `.omx/context/defaultprofileid-deprecation-review-parking-lot-20260421T094305Z.md`
- `.omx/plans/prd-hyper-like-phase4-interaction-polish.md`
- `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`
- `docs/tasks/T-056-hyper-phase4-interaction-polish.md`
- `docs/TESTING.md`
- `docs/tasks/TEMPLATE.md`

## Kickoff Gate
- `T-055` is closed.
- The formal Phase 4 PRD and test-spec both exist.
- `T-056` is complete or clearly no longer blocks the defaults / lifecycle lane.
- No higher-priority lifecycle, focus, or startup regression is currently overriding the defaults lane.

## Kickoff Sequence
1. Confirm the gate conditions above are all true.
2. Create the formal review artifact:
   - `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`
3. Turn the parked context's `Current Repo Facts`, `Required Sections For The Future Review`, `Removal Preconditions`, and `Allowed Verdicts` into the initial review-document skeleton.
4. State explicitly that this round produces only the formal review artifact, not a narrowing or removal implementation task.
5. Record in `.omx/notepad.md` that the topic has moved from parked state to the active review lane.

## Review Boundaries
- Do not create a narrowing or removal implementation task during kickoff.
- Do not modify `app/lib/`, `app/test/`, or `native/core/`.
- Do not mix remaining Phase 4 implementation work into this review.

## After Review
- The completed review must end with exactly one parked verdict:
  - `Not ready`
  - `Ready for narrowing`
  - `Ready for removal`
- If the verdict is `Not ready`, stop after the formal review and do not create implementation work yet.
- If the verdict is `Ready for narrowing` or `Ready for removal`, continue with `.omx/context/defaultprofileid-deprecation-implementation-kickoff-checklist-20260422T065644Z.md` instead of creating a `docs/tasks/T-0NN-*` task directly from the review.

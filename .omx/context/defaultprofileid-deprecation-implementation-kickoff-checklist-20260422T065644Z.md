# Context Snapshot — `defaultProfileId` Deprecation Implementation Kickoff Checklist

## Task Statement
Once the formal `defaultProfileId` deprecation review has been completed and its verdict is locked, convert that verdict into the next implementation task or explicitly stop without creating implementation work.

## Inputs
- `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`
- `.omx/context/defaultprofileid-deprecation-review-parking-lot-20260421T094305Z.md`
- `docs/tasks/TEMPLATE.md`
- `docs/TESTING.md`

## Kickoff Gate
- `T-055` is closed.
- The formal Phase 4 PRD and test-spec both exist.
- `T-056` is complete or clearly no longer blocks the defaults / lifecycle lane.
- `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md` exists and contains a final locked verdict.
- No higher-priority lifecycle, focus, or startup regression is currently overriding the defaults lane.

## Verdict Mapping
- `Not ready`
  - Do not create an implementation task.
  - Treat the formal review as the current source of truth for why the topic remains parked.
  - Record in `.omx/notepad.md` that the topic stays parked after review.
- `Ready for narrowing`
  - Create one focused follow-up task:
    - `docs/tasks/T-0NN-terminalprofiles-defaultprofileid-narrowing.md`
- `Ready for removal`
  - Create one focused follow-up task:
    - `docs/tasks/T-0NN-terminalprofiles-defaultprofileid-removal.md`

## Kickoff Sequence
1. Confirm the gate conditions above are all true and read the formal review's final verdict.
2. If the verdict is `Not ready`, stop at the documentation layer and do not create an implementation task.
3. If the verdict is `Ready for narrowing` or `Ready for removal`, create exactly one follow-up task from `docs/tasks/TEMPLATE.md`.
4. Pull the task's `Goal`, `Scope`, `Non-goals`, `Acceptance`, `Verification`, and `Risks / Follow-ups` directly from the formal review.
5. State explicitly in the new task that it must not absorb remaining Phase 4 work or unrelated defaults / lifecycle fixes.
6. If the verdict is `Ready for removal`, carry forward the formal review's confirmed removal preconditions instead of reopening the review question.
7. Record in `.omx/notepad.md` whether the topic has moved from the active review lane into an implementation lane or remains parked.

## Task Shape Rules
- One completed formal review may create at most one implementation task.
- Do not create both narrowing and removal tasks in the same kickoff round.
- Do not perform code implementation during this kickoff.
- Choose the next available `T-0NN` number at kickoff time instead of reserving a task number early.

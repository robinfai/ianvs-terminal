# T-274 Verification readiness checklist

## Goal

Add a verification readiness checklist that distinguishes runnable verification
entry points from actual passing evidence.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md`.
- Link the checklist from docs and audit surfaces.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not mark verification gates passed.
- Do not change production code.
- Do not replace the verification command plan or completion audit checklist.

## Acceptance

- Each required automated and manual gate has a readiness state.
- The checklist records what evidence is still missing before closure.
- The checklist explicitly prevents treating readiness as completion.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a verification readiness checklist covering formatting, analysis,
focused tests, broader tests, manual gates, and evidence recording.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- Readiness can become stale if new tests or gates are added without updating
  the checklist.
- The overall objective remains blocked until the gates are actually executed
  and recorded.

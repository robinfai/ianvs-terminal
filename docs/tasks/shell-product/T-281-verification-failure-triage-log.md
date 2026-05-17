# T-281 Verification failure triage log

## Goal

Add a failure triage log for recording blocking verification failures and their
smallest follow-up fix tasks.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.
- Link the triage log from docs, command batches, handoff, and evidence ledger.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not record synthetic failures.
- Do not mark any gate passed.
- Do not change production code.

## Acceptance

- Failed verification batches have a standard place to record first blockers.
- Failure rows can be mapped to likely P1-P5 or T-169 owners.
- The log explains how failures become follow-up fix tasks and when rows can be
  resolved.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a verification failure triage log for future failed batch evidence.

## Verification

Not run. This task only updates documentation and records no actual failure or
passing evidence.

## Remaining Risks

- The log is empty until verification actually runs.
- Real closure still depends on executing batches, fixing failures, and
  recording passing evidence.

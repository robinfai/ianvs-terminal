# T-292 Verification helper README

## Goal

Add a local README for the verification helper scripts that explains their
purpose, invocation convention, and evidence boundary.

## Scope

- Add `tools/LOCAL_TERMINAL_VERIFICATION_HELPERS.md`.
- Link the helper README from verification docs.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not change script file modes.
- Do not update the canonical evidence ledger.

## Acceptance

- Helper purposes are listed in one local README.
- The README explains why docs use `bash tools/<script>.sh`.
- The README states that helpers have not been executed and do not close the
  objective.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a README for the local-terminal verification helper scripts.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- Helper scripts remain unexecuted and may need syntax fixes when first used.
- Objective closure still depends on real verification evidence.

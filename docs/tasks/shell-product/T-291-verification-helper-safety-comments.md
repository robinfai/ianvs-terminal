# T-291 Verification helper safety comments

## Goal

Make the local-terminal verification helper scripts more explicit about which
paths are read-only, which paths execute verification, and why script output is
not completion evidence.

## Scope

- Add shellcheck shell hints and safety comments to the verification helper
  scripts.
- Clarify helper usage text around ledger and audit checklist updates.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the canonical evidence ledger.

## Acceptance

- Helper scripts state whether they are read-only or execution helpers.
- Helper usage text states that ledger and audit checklist updates are still
  required before closure.
- No helper claims to close the objective automatically.

## Verification Commands

- Not run in this task.

## Result

Added shell comments and clearer safety text to the local-terminal verification
helper scripts.

## Verification

Not run. The helper scripts were updated but not executed in this session.

## Remaining Risks

- The scripts still have not been syntax-checked or executed.
- Real closure still depends on running verification and recording evidence.

# T-296 Verification status authorization state

## Goal

Show the current verification authorization state in the read-only verification
status helper.

## Scope

- Update `tools/local_terminal_verification_status.sh` to print that
  verification is currently not authorized.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the canonical evidence ledger.

## Acceptance

- The status helper output includes the authorization gate path.
- The status helper output states that verification is currently not authorized.
- The helper remains read-only and does not execute verification.

## Verification Commands

- Not run in this task.

## Result

Updated the read-only verification status helper to include the current
authorization state.

## Verification

Not run. The helper was updated but not executed in this session.

## Remaining Risks

- The helper has not been syntax-checked or executed.
- The objective remains blocked until verification is authorized, executed, and
  recorded.

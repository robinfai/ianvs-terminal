# T-285 Verification status helper

## Goal

Add a lightweight helper that prints the local-terminal final verification
status and the relevant handoff, command, ledger, and script entry points.

## Scope

- Add `tools/local_terminal_verification_status.sh`.
- Link the helper from global docs and final verification handoff.
- Update task and status indexes.

## Non-goals

- Do not run the helper.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update evidence files with synthetic results.

## Acceptance

- The helper prints the current blocked status.
- The helper lists the primary handoff, audit docs, command docs, evidence docs,
  and verification helper scripts.
- The helper explicitly states that it does not run verification.

## Verification Commands

- Not run in this task.

## Result

Added a local verification status helper script for navigation and handoff.

## Verification

Not run. The helper was added but not executed in this session.

## Remaining Risks

- The helper has not been syntax-checked or executed.
- The objective remains blocked until real verification evidence is recorded.

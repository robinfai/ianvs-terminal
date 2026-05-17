# T-286 Verification helper index

## Goal

Add an index that explains the local-terminal verification helper scripts and
separates safe inspection commands from commands that execute verification.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md`.
- Link the helper index from docs, testing, final handoff, and command batches.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update evidence files with synthetic results.

## Acceptance

- Each helper script has an explicit purpose and side-effect profile.
- Read-only inspection commands are separated from execution commands.
- The index states that helpers do not update the canonical evidence ledger.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a helper index for local-terminal verification status, batch, and capture
scripts.

## Verification

Not run. The helper scripts were not executed in this session.

## Remaining Risks

- The helper scripts are still unexecuted and may need syntax fixes when first
  used.
- The objective remains blocked until real verification evidence is recorded.

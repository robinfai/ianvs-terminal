# T-282 Testing known-issues verification links

## Goal

Expose the local-terminal final verification workflow from the global testing
and known-issues documents.

## Scope

- Link local-terminal verification batches and final handoff from
  `docs/TESTING.md`.
- Record the current P0-P5 wired-but-unverified closure risk in
  `docs/KNOWN_ISSUES.md`.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not mark any gate passed.
- Do not change production code.
- Do not update stale product-gap rows outside this verification-linking task.

## Acceptance

- Global testing docs point to the local-terminal verification batch script and
  handoff.
- Known issues explicitly state that current local-terminal P0-P5 closure is
  blocked by missing verification evidence.
- The task record preserves that no validation was run.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added global testing and known-issues links for the local-terminal verification
closure workflow.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- The linked verification script and command batches still have not been
  executed.
- The objective remains blocked until evidence is recorded.

# T-278 Final verification handoff

## Goal

Add a single final verification handoff that connects the completion audit,
readiness checklist, command batches, evidence ledger, record examples, runbook,
and manual template.

## Scope

- Add `docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md`.
- Link the handoff from docs and key verification/audit surfaces.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not mark any gate passed.
- Do not change production code.
- Do not replace the underlying command plan, ledger, or runbook.

## Acceptance

- The handoff states the current blocked completion state.
- The handoff lists required reading, execution order, stop conditions, closure
  criteria, and final report shape.
- The handoff preserves the rule that only real evidence can close the
  objective.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a final verification handoff for executing and recording the remaining
closure loop.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- The handoff must be followed by real verification execution before it can
  support closure.

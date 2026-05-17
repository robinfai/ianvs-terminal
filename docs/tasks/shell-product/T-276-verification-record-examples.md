# T-276 Verification record examples

## Goal

Add examples showing how real verification ledger rows should be converted into
`LocalTerminalVerificationGateRecord` values.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md`.
- Link the examples from docs, ledger, runbook, readiness, and command plan.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not mark any gate passed.
- Do not change production code.
- Do not replace the ledger or runbook.

## Acceptance

- Examples cover formatting, static analysis, unit/widget/integration tests,
  manual gates, batch recording, and failed/skipped gates.
- Examples preserve the rule that only real command/manual evidence may be
  recorded as passed.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added verification record examples aligned with
`LocalTerminalVerificationGateRecord` and
`LocalTerminalVerificationPlanRecords.defaultPending().toRecorder()`.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- Examples must not be mistaken for real verification output.
- The objective remains blocked until actual records are collected and all
  required gates pass.

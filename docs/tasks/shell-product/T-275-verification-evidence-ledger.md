# T-275 Verification evidence ledger

## Goal

Add a fill-in verification evidence ledger for recording the real command and
manual evidence required before T-169 can close.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
- Link the ledger from docs, readiness, runbook, and audit surfaces.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not mark any gate passed.
- Do not change production code.
- Do not replace the manual template, command plan, readiness checklist, or
  evidence recording runbook.

## Acceptance

- The ledger lists every required verification gate from
  `LocalTerminalVerificationEvidence.defaultRequiredGates`.
- Every gate starts as pending.
- The ledger includes fields for command output, manual observations, and
  conversion into verification evidence records.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a verification evidence ledger with pending automated gates, manual gates,
production wiring backlog rows, and recording fields for future real evidence.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- The ledger must be filled with real command/manual evidence before it can
  support closure.
- The overall objective remains blocked until every required gate is recorded as
  passed.

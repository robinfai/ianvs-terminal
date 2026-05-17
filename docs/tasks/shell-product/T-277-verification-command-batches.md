# T-277 Verification command batches

## Goal

Add copy-ready verification command batches so the final verification loop can
be executed and recorded consistently.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`.
- Link the command batches from docs, command plan, readiness checklist, ledger,
  and record examples.
- Update task and status indexes.

## Non-goals

- Do not run any command.
- Do not mark any gate passed.
- Do not change production code.
- Do not replace the verification command plan or evidence ledger.

## Acceptance

- Formatting, static analysis, focused completion diagnostics, P1, P2-P5,
  verification evidence, broader tests, integration, and manual gates have
  explicit command or recording batches.
- Each batch maps to the relevant `LocalTerminalVerificationGate`.
- The document preserves the rule that commands must be executed and recorded
  before evidence can pass.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added verification command batches for the final verification loop.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- The broader and integration test batches still require final command choice
  based on project stability and available targets.
- The objective remains blocked until batches are executed and recorded.

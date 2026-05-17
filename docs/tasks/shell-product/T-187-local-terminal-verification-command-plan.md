# T-187 Local terminal verification command plan

## Milestone

P0-P5 verification and closure

## Intent

Define the concrete command and manual verification evidence required for T-169
before the local terminal objective can close.

## Scope

- Map required verification gates to concrete commands or manual scenarios.
- Define required evidence for formatting, static analysis, unit tests, widget
  tests, integration tests, and manual gates.
- Map verification evidence into `LocalTerminalVerificationEvidence`.
- Preserve skipped or missing required gates as blockers.

## Deliverables

- `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md`

## Acceptance criteria

- Every default required verification gate has a command or manual scenario.
- Evidence requirements are explicit.
- The plan states that no verification has been run in this session.

## Status

Created. The plan documents required verification; it does not execute it.

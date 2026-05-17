# T-177 Local terminal default verification gates

## Milestone

P0-P5 verification and closure

## Intent

Provide a default required verification gate set so T-169 starts from a complete
pending verification state instead of relying on callers to remember every test,
analysis, formatting, and manual gate.

## Scope

- Add default required verification gates to `LocalTerminalVerificationEvidence`.
- Add a factory that creates pending required evidence for every default gate.
- Ensure a missing required gate is not treated as passed.

## Deliverables

- Update `example/lib/features/shell/local_terminal_verification_evidence.dart`.
- Update `example/test/shell/local_terminal_verification_evidence_test.dart`.

## Acceptance criteria

- Default required evidence contains unit, widget, integration, manual, static
  analysis, and formatting gates.
- Default evidence starts blocked until real verification is recorded.
- `gatePassed` returns false when the gate is missing.

## Status

Foundation implemented. Not verified in this session.

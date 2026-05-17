# T-195 Local terminal verification evidence recorder

## Milestone

P0-P5 verification and closure

## Intent

Provide an immutable recorder for verification command/manual outcomes so T-169
can update `LocalTerminalVerificationEvidence` without hand-writing the full
gate list.

## Scope

- Start from the default pending required verification gates.
- Record passed or failed evidence for a specific gate.
- Preserve command strings, output lines, and notes.
- Convert recorded evidence into T-169 real-wiring backlog evidence.

## Deliverables

- `example/lib/features/shell/local_terminal_verification_evidence_recorder.dart`
- `example/test/shell/local_terminal_verification_evidence_recorder_test.dart`

## Acceptance criteria

- Recorder starts with every default required gate pending.
- Recording command evidence updates the matching gate.
- Failed required gates remain blockers in T-169 backlog evidence.

## Status

Foundation implemented. Not verified in this session.

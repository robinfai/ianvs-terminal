# T-196 Local terminal verification evidence batch recording

## Milestone

P0-P5 verification and closure

## Intent

Allow T-169 verification evidence to be recorded from a batch of command/manual
results without hand-writing repetitive chained recorder calls.

## Scope

- Add a verification gate record value object.
- Add `recordAll(...)` to `LocalTerminalVerificationEvidenceRecorder`.
- Preserve command strings, output lines, notes, required state, and status for
  each record.

## Deliverables

- Update `example/lib/features/shell/local_terminal_verification_evidence_recorder.dart`.
- Update `example/test/shell/local_terminal_verification_evidence_recorder_test.dart`.

## Acceptance criteria

- Multiple verification gate records can update evidence in one call.
- Passed and failed gate states are preserved.
- Batch recording still leaves unrecorded required gates pending.

## Status

Foundation implemented. Not verified in this session.

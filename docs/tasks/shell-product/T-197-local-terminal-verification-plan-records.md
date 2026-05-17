# T-197 Local terminal verification plan records

## Milestone

P0-P5 verification and closure

## Intent

Provide default pending verification gate records that mirror the verification
command plan and can be fed directly into the verification evidence recorder.

## Scope

- Add default pending records for formatting, static analysis, tests, and manual
  gates.
- Preserve command strings and execution notes.
- Convert default records into a verification evidence recorder.

## Deliverables

- `example/lib/features/shell/local_terminal_verification_plan_records.dart`
- `example/test/shell/local_terminal_verification_plan_records_test.dart`

## Acceptance criteria

- Default records cover every default required verification gate.
- Default records start pending.
- Converting the records to a recorder keeps verification blocked until real
  evidence is recorded.

## Status

Foundation implemented. Not verified in this session.

# T-289 Verification helper execution warning

## Goal

Make verification helper execution paths print an explicit warning that scripts
do not update the evidence ledger or close the objective automatically.

## Scope

- Update `tools/local_terminal_verification_batches.sh`.
- Update `tools/local_terminal_verification_capture.sh`.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the evidence ledger.

## Acceptance

- Running a verification batch will print that ledger updates remain manual.
- Running the capture wrapper will print that captured logs still require human
  review before ledger updates.
- The warning preserves the closure rule that script output alone is not
  completion evidence.

## Verification Commands

- Not run in this task.

## Result

Added execution warnings to the verification batch and capture helper scripts.

## Verification

Not run. The scripts were updated but not executed in this session.

## Remaining Risks

- The scripts have still not been syntax-checked or executed.
- The objective remains blocked until verification evidence is actually
  recorded.

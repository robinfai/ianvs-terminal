# T-290 Verification capture gate hints

## Goal

Have the verification capture wrapper annotate future captured runs with the
verification gates affected by each batch.

## Scope

- Update `tools/local_terminal_verification_capture.sh` to include gate hints in
  `summary.txt` and `ledger-entry.md`.
- Update task and status indexes.

## Non-goals

- Do not run the wrapper.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the canonical evidence ledger.

## Acceptance

- Future single-batch captures show the relevant gate or gates.
- Future `all-automated` captures are marked as an aggregate covering
  formatting, static analysis, unit tests, and widget tests.
- Gate hints remain advisory and do not replace ledger review.

## Verification Commands

- Not run in this task.

## Result

Updated the capture wrapper to write verification gate hints into future
captured summaries and ledger-entry templates.

## Verification

Not run. The wrapper was updated but not executed in this session.

## Remaining Risks

- The wrapper has not been syntax-checked or executed.
- Gate hints are maintained manually and may need updating if batches change.

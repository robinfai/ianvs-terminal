# T-284 Verification capture ledger entry template

## Goal

Have the verification capture wrapper generate a ledger-entry template beside
future captured batch logs.

## Scope

- Update `tools/local_terminal_verification_capture.sh` to create
  `ledger-entry.md` for future captured runs.
- Update documentation that describes the capture wrapper output.
- Update task and status indexes.

## Non-goals

- Do not run the wrapper.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not auto-write the canonical evidence ledger.

## Acceptance

- Future captured runs produce `summary.txt`, `output.log`, and
  `ledger-entry.md`.
- The generated ledger entry keeps verification status as `pending` until real
  output is reviewed.
- Failed runs still require a triage-log row.

## Verification Commands

- Not run in this task.

## Result

Updated the capture wrapper so future explicit runs generate a ledger-entry
template next to the captured output.

## Verification

Not run. The wrapper was updated but not executed in this session.

## Remaining Risks

- The wrapper has not been syntax-checked or executed.
- Generated ledger entries will still require human review before being copied
  into the canonical evidence ledger.

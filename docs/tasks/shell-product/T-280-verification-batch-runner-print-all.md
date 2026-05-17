# T-280 Verification batch runner print all

## Goal

Allow the local verification batch runner to print the full automated command
sequence without executing it.

## Scope

- Update `tools/local_terminal_verification_batches.sh` to support
  `print all-automated`.
- Update the command-batches and final handoff docs.
- Update task and status indexes.

## Non-goals

- Do not run the script.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the evidence ledger.

## Acceptance

- The script usage documents `print all-automated`.
- `print all-automated` is intended to show the automated sequence without
  execution.
- Existing explicit `run <batch>` and `run all-automated` behavior remains the
  only execution path.

## Verification Commands

- Not run in this task.

## Result

Added `print all-automated` support to the verification batch runner script.

## Verification

Not run. The script was updated but not executed in this session.

## Remaining Risks

- The script has still not been syntax-checked or executed.
- Real closure still depends on running and recording the verification batches.

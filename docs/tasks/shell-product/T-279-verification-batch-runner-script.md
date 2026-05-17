# T-279 Verification batch runner script

## Goal

Add a local script entry point for listing, printing, and explicitly running the
verification command batches.

## Scope

- Add `tools/local_terminal_verification_batches.sh`.
- Link the script from command-batch and final handoff documentation.
- Update task and status indexes.

## Non-goals

- Do not run the script.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not update the evidence ledger with synthetic output.

## Acceptance

- The script lists available batches.
- The script can print commands without executing them.
- The script requires explicit `run <batch>` or `run all-automated` before
  executing verification commands.
- Manual and integration batches remain instructions unless a concrete target is
  chosen.

## Verification Commands

- Not run in this task.

## Result

Added a local verification batch runner script aligned with the command-batches
document.

## Verification

Not run. The script was added but not executed in this session.

## Remaining Risks

- The script itself has not been syntax-checked or executed.
- The command batches may reveal formatting, analyzer, or test failures when
  actually run.

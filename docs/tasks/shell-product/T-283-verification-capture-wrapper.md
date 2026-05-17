# T-283 Verification capture wrapper

## Goal

Add a wrapper that can explicitly run verification batches later while capturing
stdout, stderr, and exit status for ledger entry.

## Scope

- Add `tools/local_terminal_verification_capture.sh`.
- Link the capture wrapper from verification command batches, final handoff, and
  global testing docs.
- Update task and status indexes.

## Non-goals

- Do not run the wrapper.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not write synthetic evidence to the ledger.

## Acceptance

- The wrapper can list and print batches by delegating to the batch runner.
- The wrapper requires explicit `run <batch>` or `run all-automated` before
  execution.
- Captured output is intended for
  `docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
- Failed captured runs are intended for
  `docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.

## Verification Commands

- Not run in this task.

## Result

Added a local verification capture wrapper that writes future batch logs and
summary metadata under `build/local-terminal-verification/`.

## Verification

Not run. The wrapper was added but not executed in this session.

## Remaining Risks

- The wrapper has not been syntax-checked or executed.
- Captured logs still require manual ledger and triage-log updates.

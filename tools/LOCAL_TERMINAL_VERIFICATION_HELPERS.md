# Local Terminal Verification Helpers

This directory contains helper scripts for the local-terminal P0-P5 final
verification loop.

These helpers are operational aids only. They do not mark verification gates as
passed, do not update the canonical evidence ledger, and do not close the
objective.

## Helpers

| Script | Purpose | Runs verification |
| --- | --- | --- |
| `local_terminal_verification_status.sh` | Print current verification status and relevant docs/scripts. | No |
| `local_terminal_verification_batches.sh` | List, print, or explicitly run verification batches. | Only with `run ...` |
| `local_terminal_verification_capture.sh` | Explicitly run verification batches and capture logs/templates. | Only with `run ...` |

## Invocation Convention

Use `bash tools/<script>.sh ...` rather than relying on executable file mode:

```sh
bash tools/local_terminal_verification_status.sh
bash tools/local_terminal_verification_batches.sh print all-automated
bash tools/local_terminal_verification_capture.sh print all-automated
bash tools/local_terminal_verification_capture.sh run broader
bash tools/local_terminal_verification_capture.sh run integration
bash tools/local_terminal_verification_capture.sh run all-automated
```

The current documentation intentionally uses `bash ...` so the helpers remain
usable even if executable bits are not preserved by an archive, checkout, or
copy operation.

## Evidence Rule

After any command that executes verification:

1. Review the output or captured log.
2. Fill `docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
3. If the command failed, fill
   `docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.
4. Convert ledger rows into `LocalTerminalVerificationGateRecord` values only
   after gate rules are satisfied.

## Current Status

The helper scripts have been executed in this session. The latest full captured
automated run is:

```text
build/local-terminal-verification/20260516T145142Z-all-automated
```

Formatting, static analysis, focused completion, P1, cross-milestone, P2, P3,
P4, P5, verification-evidence, and terminal package batches have passing
evidence.

The latest `broader` rerun passed after the visibility, paste, zoom, and hotkey
fixes:

```text
build/local-terminal-verification/20260516T171406Z-broader
```

The integration batch also passed after the helper was corrected to build the
debug native core, run from `example`, and execute the integration files
sequentially:

```text
build/local-terminal-verification/20260516T171644Z-integration
```

Ledger-to-record conversion is represented by
`LocalTerminalVerificationPlanRecords.latestPassed()`. The commands below are
for refreshing evidence, not for closing a currently pending conversion step.

```sh
bash tools/local_terminal_verification_capture.sh run broader
bash tools/local_terminal_verification_capture.sh run integration
```

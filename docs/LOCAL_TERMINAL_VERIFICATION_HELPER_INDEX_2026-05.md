# Local Terminal Verification Helper Index

Date: 2026-05-16

Purpose: document the local helper scripts that support final local-terminal
verification execution.

This index is not verification evidence. None of the helpers mark gates passed
or update the canonical evidence ledger automatically.
Machine-readable helper metadata is also available in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`.
Manifest maintenance rules are documented in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md`.
The local helper README is `../tools/LOCAL_TERMINAL_VERIFICATION_HELPERS.md`.
Verification execution authorization is documented in
`LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md`.

## Helper Scripts

| Script | Safe read-only actions | Execution actions | Writes output | Updates ledger | Intended use |
| --- | --- | --- | --- | --- | --- |
| `tools/local_terminal_verification_status.sh` | Prints current verification status, handoff docs, evidence docs, and helper commands | None | No | No | Navigation only. |
| `tools/local_terminal_verification_batches.sh` | `list`, `print <batch>`, `print all-automated` | `run <batch>`, `run all-automated` | Command output to terminal only | No | Run explicit verification batches after approval. |
| `tools/local_terminal_verification_capture.sh` | `list`, `print <batch>` | `run <batch>`, `run all-automated` | `build/local-terminal-verification/<timestamp>-<batch>/output.log`, `summary.txt`, `ledger-entry.md` | No | Run explicit verification batches and capture output for later ledger entry. |

Execution helpers print warnings that ledger updates remain manual and script
success alone is not closure evidence.
The capture helper writes advisory gate hints into future `summary.txt` and
`ledger-entry.md` files; those hints still require human review before ledger
updates.

Latest captured automated run:
`build/local-terminal-verification/20260516T145142Z-all-automated`.

## Safe Inspection Commands

These commands should not run verification:

```sh
bash tools/local_terminal_verification_status.sh
bash tools/local_terminal_verification_batches.sh list
bash tools/local_terminal_verification_batches.sh print all-automated
bash tools/local_terminal_verification_capture.sh print all-automated
```

## Commands That Execute Verification

These commands run verification and should be used only when verification
execution is intended:

```sh
bash tools/local_terminal_verification_capture.sh run broader
bash tools/local_terminal_verification_capture.sh run integration
bash tools/local_terminal_verification_batches.sh run <batch>
bash tools/local_terminal_verification_batches.sh run all-automated
bash tools/local_terminal_verification_capture.sh run <batch>
bash tools/local_terminal_verification_capture.sh run all-automated
```

## Evidence Rule

After any execution command:

1. Review command output or captured logs.
2. Fill `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
3. If the command failed, fill
   `LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.
4. Convert reviewed ledger rows into `LocalTerminalVerificationGateRecord`
   values only after the gate rule is satisfied.

Do not treat helper output, script existence, or captured logs as closure by
itself.

## Current Status

The helper scripts have been executed in this session. Formatting, static
analysis, focused completion/P1/P2-P5/cross-milestone/verification-evidence
batches have passing captured evidence. The latest `broader` rerun passed in
`build/local-terminal-verification/20260516T171406Z-broader`, and the latest
integration batch passed in
`build/local-terminal-verification/20260516T171644Z-integration`.

Ledger-to-record conversion is represented by
`LocalTerminalVerificationPlanRecords.latestPassed()`.

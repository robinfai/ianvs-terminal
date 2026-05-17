# Local Terminal Verification Authorization Gate

Date: 2026-05-16

Purpose: make explicit when it is acceptable to run the final verification
batches for the local-terminal P0-P5 objective.

This document exists because the current objective cannot close without real
verification, but verification commands should not be run unless execution is
explicitly intended.

## Current Gate State

Status: **verification authorized in this session**.

The user authorized verification with `运行验证闭环` on 2026-05-16. Automated
verification was executed through the capture helper.

Latest full-run evidence directory:
`build/local-terminal-verification/20260516T145142Z-all-automated`.

Current execution blocker: all required verification gates now have passing
ledger evidence. The remaining work is canonical evidence conversion and final
completion-report rebuild.

## What Counts As Authorization

Any of the following user instructions is sufficient authorization to start the
automated verification loop:

- `运行验证闭环`
- `run verification`
- `run the verification batches`
- `run format analyze and tests`
- `run all-automated verification`

If the user authorizes only a subset, run only that subset and record the
remaining gates as pending.

## What Does Not Count As Authorization

The following are not enough by themselves:

- Asking whether plans exist.
- Asking whether competitor-derived features are covered.
- Asking for current status.
- Asking to continue planning.
- Asking to prepare scripts or docs.
- A tool/helper/script existing in the repository.

## Authorized Automated Sequence

When execution quota is available, resume with:

```sh
bash tools/local_terminal_verification_capture.sh run broader
```

If that passes, either rerun the full automated sequence or explicitly carry
forward the same-session focused-batch evidence already recorded in the ledger:

```sh
bash tools/local_terminal_verification_capture.sh run all-automated
```

or, if capture is not desired:

```sh
bash tools/local_terminal_verification_batches.sh run all-automated
```

Then run the integration smoke batch:

```sh
bash tools/local_terminal_verification_capture.sh run integration
```

Copy reviewed results into:

- `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`
- `LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md` when failures occur
- `LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` after real evidence is available

## Manual Gate Authorization

Manual gates still require intentional observation. Use:

- `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`
- `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`

Manual gates must not be marked passed from automated test success alone.

## Closure Rule

Even after authorization and execution, do not mark the objective complete until:

- Every required verification gate is recorded as `passed`.
- T-164 through T-169 backlog evidence is present and verified.
- `LocalTerminalCompletionEvidenceReport.canCloseObjective == true`.
- `LocalTerminalProductionWiringManifest.canCloseAll == true`.
- The audit checklist contains real evidence references.

## Current Status

Verification authorization has been given and partial automated evidence has
been recorded. The objective remains blocked because broader, integration/smoke,
manual gates, and canonical verification-evidence conversion are not complete.

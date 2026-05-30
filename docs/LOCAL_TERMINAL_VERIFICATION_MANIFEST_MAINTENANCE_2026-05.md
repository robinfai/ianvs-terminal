# Local Terminal Verification Manifest Maintenance

Date: 2026-05-16

Purpose: define how to maintain
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` without turning it into an
unreviewed source of truth.

The JSON manifest is a machine-readable index. It is not verification evidence,
not a replacement for the completion audit checklist, and not a completion
claim.

## Source Of Truth Order

When documents disagree, use this order:

1. `LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`
2. `LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md`
3. `LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md`
4. `LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`
5. `LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`

The manifest should mirror the Markdown sources. It should not introduce new
gates, new closure rules, or new completion semantics by itself.

## Update Triggers

Update the manifest when any of these change:

- Required verification gate names.
- Batch ids.
- Batch-to-gate mappings.
- Helper script paths or side effects.
- Verification authorization state or authorization gate path.
- Required backlog task ids.
- Canonical document paths.
- Closure rules.

Do not update the manifest to mark a gate as passed unless the canonical
evidence ledger and audit checklist already contain real passing evidence.

## Maintenance Checklist

Before using the manifest for tooling:

- Confirm every required gate is represented.
- Confirm every executable batch is represented.
- Confirm helper scripts are marked with accurate side effects.
- Confirm the authorization state matches
  `LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md`.
- Confirm `updatesLedger` remains `false` for helpers that do not write the
  canonical ledger.
- Confirm closure rules still require real evidence.
- Confirm `completionStatus` remains blocked until verified evidence exists.

## Evidence Boundary

The manifest can support tooling that prints commands, checks missing fields, or
builds dashboards.

The manifest cannot:

- Close T-169.
- Mark T-164 through T-168 verified.
- Replace real command output.
- Replace manual observations.
- Replace `LocalTerminalVerificationEvidence`.
- Override the completion audit checklist.

## Current Status

The manifest has been updated to mirror the authorized state after automated
and integration gates passed; manual/integration-backed gates and evidence
conversion are complete for the required baseline. It was parsed with
`python3 -m json.tool docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`.

It still must not be used as passing verification evidence. The canonical
ledger and audit checklist remain the evidence authorities.

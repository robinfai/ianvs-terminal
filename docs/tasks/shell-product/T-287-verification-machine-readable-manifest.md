# T-287 Verification machine-readable manifest

## Goal

Add a machine-readable manifest for the local-terminal final verification
handoff, gates, batches, helper scripts, and closure rules.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`.
- Link the manifest from docs, helper index, command batches, and final handoff.
- Update task and status indexes.

## Non-goals

- Do not run verification commands.
- Do not run helper scripts.
- Do not mark any gate passed.
- Do not replace the canonical Markdown audit and evidence documents.

## Acceptance

- The manifest lists required verification gates and their current pending
  status.
- The manifest maps batches to gates.
- The manifest lists helper script side effects.
- The manifest preserves closure rules that require real evidence.

## Verification Commands

- Not run for this documentation/data-only task.

## Result

Added a JSON verification manifest for future tooling and review.

## Verification

Not run. The manifest was added but not parsed or validated in this session.

## Remaining Risks

- The JSON manifest may require syntax validation before use by tooling.
- The manifest can become stale if verification batches or gates change.

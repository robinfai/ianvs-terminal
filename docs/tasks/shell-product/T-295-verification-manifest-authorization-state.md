# T-295 Verification manifest authorization state

## Goal

Expose the current verification authorization state in the machine-readable
verification manifest.

## Scope

- Update `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` with the
  authorization gate document and current `not_authorized` state.
- Update manifest maintenance rules.
- Update task and status indexes.

## Non-goals

- Do not run helper scripts.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not parse or validate the JSON manifest.

## Acceptance

- The manifest lists the authorization gate document.
- The manifest records that verification is currently not authorized.
- The manifest includes examples of authorizing and non-authorizing requests.

## Verification Commands

- Not run for this documentation/data-only task.

## Result

Added authorization metadata to the machine-readable verification manifest.

## Verification

Not run. The manifest was updated but not parsed or used as verification
evidence.

## Remaining Risks

- The JSON manifest still needs syntax validation before tooling relies on it.
- Verification remains blocked until explicit authorization and recorded
  passing evidence exist.

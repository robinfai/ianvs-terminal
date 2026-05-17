# T-288 Verification manifest maintenance

## Goal

Document how the machine-readable verification manifest should be maintained
without making it an unreviewed source of truth.

## Scope

- Add `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md`.
- Link the maintenance note from docs and the manifest-related verification
  surfaces.
- Update task and status indexes.

## Non-goals

- Do not parse or validate the JSON manifest.
- Do not run verification commands.
- Do not mark any gate passed.
- Do not change production code.

## Acceptance

- The maintenance note defines source-of-truth ordering.
- The maintenance note lists update triggers and maintenance checks.
- The maintenance note preserves that the JSON manifest is not completion
  evidence.

## Verification Commands

- Not run for this documentation-only task.

## Result

Added a manifest maintenance note for future tooling and review.

## Verification

Not run. This task only updates documentation and records no passing evidence.

## Remaining Risks

- The JSON manifest still has not been parsed or schema-validated.
- The objective remains blocked until real verification evidence is recorded.

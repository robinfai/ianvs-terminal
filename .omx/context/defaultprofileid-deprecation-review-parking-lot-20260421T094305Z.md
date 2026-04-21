# Context Snapshot — `defaultProfileId` Deprecation Review Parking Lot

## Task Statement
Once `T-055` is closed and the formal Phase 4 planning pair exists, write the review artifact:

- `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`

This parking-lot context exists so the later review can start from grounded repo facts instead of reopening the entire compatibility-window question.

## Gate / Preconditions
Do not create the formal review artifact until all of the following are true:
- `docs/tasks/T-055-terminal-manual-matrix-execution.md` satisfies `Done When`.
- `.omx/plans/prd-hyper-like-phase4-interaction-polish.md` exists.
- `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md` exists.
- No higher-priority lifecycle, focus, or startup regression is currently overriding the defaults lane.

If any gate fails, keep this topic parked and do not create `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`.

## Current Repo Facts
- `.omx/plans/prd-hyper-like-phase3-persistence-defaults.md` already defines `TerminalAppPreferencesDocument.defaults.defaultProfileId` as the canonical app-defaults source of truth and treats `TerminalProfilesDocument.defaultProfileId` as a compatibility-window legacy field.
- `app/lib/features/sessions/session_controller.dart` still keeps `_legacyDefaultProfileId` in memory.
- `_bootstrap()` still uses the legacy field when preferences are absent and `allowLegacyFallback` is true.
- `setDefaultProfile()` and `resetDefaultProfile()` write only `TerminalAppPreferencesDocument`.
- `saveProfile()` and `deleteProfile()` still save `TerminalProfilesDocument(defaultProfileId: _legacyDefaultProfileId ?? '', ...)`, so the legacy field is still being written through the profile document path.
- `app/lib/features/profiles/profile_models.dart` still includes `defaultProfileId` in `TerminalProfilesDocument`.
- `app/lib/features/profiles/profile_repository.dart` still fully loads and saves the field via `flutterm_profiles.json`.
- Current tests still protect the compatibility window as intentional behavior:
  - `app/test/sessions/session_controller_phase3_test.dart`
  - `app/test/sessions/session_controller_test.dart`
  - `app/test/shell/shell_screen_phase3_test.dart`
  - `app/test/profiles/profile_repository_test.dart`

## Required Sections For The Future Review
The future `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md` must include:
- `Requirements Summary`
- `Current Ownership State`
- `Legacy Read-Path Inventory`
- `Legacy Write-Path Inventory`
- `Compatibility Window Consumers`
- `Removal Preconditions`
- `Risk Review`
- `Decision Options`
- `Recommended Verdict`
- `Follow-up Tasks`

## Minimum Inventory The Review Must Capture
### Legacy read-path inventory
At minimum, review these paths:
- bootstrap fallback in `app/lib/features/sessions/session_controller.dart`
- any UI fallback wording or shell exposure that still explains legacy-default behavior
- any tolerant-read behavior coming from `app/lib/features/profiles/profile_repository.dart`

### Legacy write-path inventory
At minimum, review these paths:
- `saveProfile()` in `app/lib/features/sessions/session_controller.dart`
- `deleteProfile()` in `app/lib/features/sessions/session_controller.dart`
- `ProfileRepository.save()` writing `TerminalProfilesDocument`

### Compatibility-window consumers
At minimum, review these consumers:
- Phase 3 shell defaults UI fallback language in `app/test/shell/shell_screen_phase3_test.dart`
- session-controller compatibility tests in `app/test/sessions/session_controller_phase3_test.dart`
- broader session-controller regression coverage in `app/test/sessions/session_controller_test.dart`
- profile-repository disk compatibility tests in `app/test/profiles/profile_repository_test.dart`

## Removal Preconditions That Must Be Explicit In The Review
Do not allow the future review to stay vague. It must explicitly evaluate whether all of the following are true:
- preferences are proven to be the only long-term defaults source of truth
- bootstrap no longer needs legacy `defaultProfileId` as a normal path
- save/delete profile flows no longer need to write the legacy field back into the profile document
- shell Phase 3 UI no longer relies on legacy fallback copy as a primary user path
- tests can move from “compatibility window is protected behavior” to either “legacy path only for migration fixtures” or full removal
- the repository strategy for old on-disk profile docs is explicit:
  - one-time migration, or
  - tolerant-read without keeping the schema field alive
- the review names a minimum verification chain for any future removal implementation

## Allowed Verdicts
The future review must end with exactly one of these verdicts:
- `Not ready`
  - keep the compatibility window
  - list blockers
  - do not open implementation work yet
- `Ready for narrowing`
  - open one implementation task to reduce the compatibility window
  - do not remove the schema field yet
- `Ready for removal`
  - open one implementation task to remove the legacy field, shrink read/write paths, and update tests/docs

The review must not end with a vague “needs more investigation” summary.

## Do Not Do
- Do not create `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md` before the gate opens.
- Do not mix the review into the formal Phase 4 PRD or test-spec.
- Do not pre-create `docs/tasks/T-056-*`.
- Do not change `app/lib/`, `app/test/`, or `native/core/` as part of this parked review preparation.

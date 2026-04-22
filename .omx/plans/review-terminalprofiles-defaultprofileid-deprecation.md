# Review — `TerminalProfilesDocument.defaultProfileId` Deprecation

## Requirements Summary

This review decides whether the legacy `TerminalProfilesDocument.defaultProfileId` field can move out of the current compatibility window. The decision must respect the existing source-of-truth contract: app defaults now live in `TerminalAppPreferencesDocument.defaults.defaultProfileId`, while old profile documents may still exist on disk and must not be broken casually.

This round produces only the formal review artifact. It does not create a narrowing or removal task, and it does not modify any production or test code.

## Current Ownership State

- Canonical ownership already belongs to `TerminalAppPreferencesDocument.defaults.defaultProfileId`, as established by the Phase 3 persistence plan.
- `SessionController` now owns only the remaining read-side compatibility window:
  - `_legacyDefaultProfileId` remains in memory
  - `_bootstrap()` still reads the legacy field when preferences are absent and `allowLegacyFallback` is true
  - `setDefaultProfile()` and `resetDefaultProfile()` write only preferences
  - `saveProfile()` and `deleteProfile()` no longer write the legacy field back into `TerminalProfilesDocument`
- `ProfileRepository` still tolerant-reads the legacy field from `flutterm_profiles.json`, but steady-state writes no longer emit it.
- Shell defaults UI no longer presents fallback as a primary compatibility-window path; the remaining legacy behavior is now runtime/bootstrap-only.

## Legacy Read-Path Inventory

Current legacy read paths still in play:

- `app/lib/features/sessions/session_controller.dart`
  - `_bootstrap()` normalizes `profiles.defaultProfileId` into `_legacyDefaultProfileId`
  - `_resolveBootstrapPreferences()` still chooses the legacy field when preferences are absent and the legacy id still matches a profile
- `app/lib/features/profiles/profile_repository.dart`
  - `load()` still decodes `TerminalProfilesDocument` as-is, including older docs that still carry the key
  - tolerant read is now explicitly migration-oriented behavior rather than a steady-state write contract

## Legacy Write-Path Inventory

Current legacy write paths still in play:

- `app/lib/features/profiles/profile_models.dart`
  - `TerminalProfilesDocument.defaultProfileId` still exists, but it is now nullable and omitted from steady-state JSON writes

There are no remaining intentional steady-state write paths for the legacy field. The remaining exposure is schema/read compatibility only.

## Compatibility Window Consumers

The compatibility window is still protected and observable in current tests:

- `app/test/sessions/session_controller_phase3_test.dart`
  - protects bootstrap pref-over-legacy precedence
  - protects legacy fallback when preferences are absent
  - protects “setDefaultProfile writes only app preferences”
  - now protects `saveProfile()` keeping legacy ids out of steady-state profile writes
- `app/test/sessions/session_controller_test.dart`
  - duplicates the same compatibility guarantees in broader regression coverage
  - now protects `deleteProfile()` repair-write without re-emitting the legacy field
- `app/test/profiles/profile_repository_test.dart`
  - protects on-disk compatibility for profile documents that still carry `defaultProfileId`
  - protects first-launch and steady-state writes omitting the legacy field
- `app/test/shell/shell_screen_phase3_test.dart`
  - protects the narrowed defaults copy that no longer presents fallback as a steady-state primary path

Today these tests still protect the legacy bootstrap/read path, but they no longer treat legacy write-through or fallback wording as normal repo behavior.

## Removal Preconditions

Required preconditions and current evaluation:

- preferences are proven to be the only long-term source of truth
  - **Met**
  - `setDefaultProfile()` / `resetDefaultProfile()` already write only preferences
- bootstrap no longer needs legacy `defaultProfileId` as a normal path
  - **Not met**
  - preferences-absent bootstrap still intentionally falls back to legacy
- save/delete profile flows no longer need to write the legacy field back into profile docs
  - **Met**
  - steady-state save/delete no longer re-emit the legacy field
- shell Phase 3 UI no longer relies on legacy fallback copy as a primary user path
  - **Met**
  - UI copy now presents fallback as current behavior, not compatibility-window policy
- tests can move from “compatibility window is protected behavior” to migration-only or full removal
  - **Partially met**
  - write-path and UI tests have narrowed, but bootstrap legacy fallback is still intentionally protected
- repository strategy for older on-disk profile docs is explicit
  - **Met**
  - the repo now tolerant-reads old docs while omitting the field from new writes
- minimum verification chain for future implementation is known
  - **Met**
  - see `Follow-up Tasks` below

## Risk Review

- **The repo is no longer in a broad compatibility-window state**
  - write-path propagation is gone
  - steady-state shell/defaults copy no longer treats legacy fallback as normal user intent
- **The remaining risk is now concentrated**
  - removing the field would mainly affect bootstrap fallback, tolerant read behavior, and the tests that still protect that path
- **Keeping the read-path indefinitely is now the bigger maintenance cost**
  - it leaves a second source of truth in runtime bootstrap even though canonical ownership has already converged on preferences
- **Shared-doc risk must stay separate**
  - `T-055 forced-closed` manual-matrix risk is unrelated and should not influence this defaults decision

## Decision Options

### Option 1 — `Not ready`

Keep the current compatibility window untouched.

- Pros:
  - zero additional migration risk right now
  - avoids another defaults-focused code change
- Cons:
  - no longer matches the repo's actual narrowed state
  - leaves the legacy bootstrap path and field alive after the write-path problem is already solved

### Option 2 — `Ready for narrowing`

Open one focused implementation task that narrows the compatibility window without removing the schema field yet.

- Pros:
  - was the right transition step before `T-057`
  - minimizes removal risk if narrowing work had not yet landed
- Cons:
  - is now stale relative to current repo facts
  - would duplicate work that has already been completed in `1689d1b`

### Option 3 — `Ready for removal`

Open one implementation task that removes the field, shrinks read/write paths, and rewrites the compatibility contract in one round.

- Pros:
  - matches the repo's current state after narrowing landed
  - finishes the deprecation in one focused follow-up instead of reopening another intermediate step
- Cons:
  - still needs careful handling for older on-disk docs that may carry the legacy key
  - requires deliberate test rewrites from “legacy fallback works” to “legacy key is ignored safely”

## Recommended Verdict

Final locked verdict: `Ready for removal`

Rationale:

- The canonical source of truth is already stable and exclusive for configured defaults: preferences own the decision.
- The previously blocking compatibility breadth has been narrowed:
  - steady-state write-through is gone
  - new profile documents omit the legacy field
  - shell/defaults UI no longer presents fallback as a primary steady-state path
- The remaining problem has collapsed into a single focused lane:
  - remove `_legacyDefaultProfileId`
  - drop bootstrap reliance on legacy profile-doc defaults
  - retire the remaining legacy-field schema/read contract
  - update tests to treat old on-disk keys as ignorable historical data rather than active default-selection input

`Ready for narrowing` is now outdated because the narrowing work already landed in `1689d1b`. `Not ready` would leave a mostly-retired legacy path alive without a remaining architectural reason.

## Follow-up Tasks

This review still does **not** create an implementation task directly. The next step should go through:

- `.omx/context/defaultprofileid-deprecation-implementation-kickoff-checklist-20260422T065644Z.md`

That kickoff should create exactly one focused removal task whose target is:

- remove `_legacyDefaultProfileId` and bootstrap legacy fallback from runtime decision-making
- remove `TerminalProfilesDocument.defaultProfileId` from the runtime schema surface
- keep tolerant handling for older on-disk documents that still include the key, but ignore it for default selection
- rewrite tests from “legacy fallback is supported runtime behavior” toward “legacy key is safely ignored historical input”

Minimum verification chain for that future removal task should include:

- `cd /Users/robinfai/personal/flutterm/app`
- `flutter analyze`
- `flutter test test/sessions/session_controller_phase3_test.dart`
- `flutter test test/sessions/session_controller_test.dart`
- `flutter test test/profiles/profile_repository_test.dart`
- `flutter test integration_test/flutterm_smoke_test.dart`

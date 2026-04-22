# Review — `TerminalProfilesDocument.defaultProfileId` Deprecation

## Requirements Summary

This review decides whether the legacy `TerminalProfilesDocument.defaultProfileId` field can move out of the current compatibility window. The decision must respect the existing source-of-truth contract: app defaults now live in `TerminalAppPreferencesDocument.defaults.defaultProfileId`, while old profile documents may still exist on disk and must not be broken casually.

This round produces only the formal review artifact. It does not create a narrowing or removal task, and it does not modify any production or test code.

## Current Ownership State

- Canonical ownership already belongs to `TerminalAppPreferencesDocument.defaults.defaultProfileId`, as established by the Phase 3 persistence plan.
- `SessionController` still owns the active compatibility window:
  - `_legacyDefaultProfileId` remains in memory
  - `_bootstrap()` still reads the legacy field when preferences are absent and `allowLegacyFallback` is true
  - `setDefaultProfile()` and `resetDefaultProfile()` already write only preferences
  - `saveProfile()` and `deleteProfile()` still write the legacy field back into `TerminalProfilesDocument`
- `ProfileRepository` still persists the legacy field through `flutterm_profiles.json`.
- Shell defaults UI still exposes fallback wording for the compatibility window instead of treating legacy behavior as fully retired.

## Legacy Read-Path Inventory

Current legacy read paths still in play:

- `app/lib/features/sessions/session_controller.dart`
  - `_bootstrap()` normalizes `profiles.defaultProfileId` into `_legacyDefaultProfileId`
  - `_resolveBootstrapPreferences()` still chooses the legacy field when preferences are absent and the legacy id still matches a profile
- `app/lib/features/profiles/profile_repository.dart`
  - `load()` still decodes `TerminalProfilesDocument` as-is, including the legacy field
  - tolerant read remains part of normal repository behavior, not a fixture-only migration helper
- `app/lib/features/shell/shell_screen.dart`
  - shell defaults summary and defaults dialog still support the “configured default vs effective fallback default” distinction that makes the compatibility window user-visible

## Legacy Write-Path Inventory

Current legacy write paths still in play:

- `app/lib/features/sessions/session_controller.dart`
  - `saveProfile()` writes `TerminalProfilesDocument(defaultProfileId: _legacyDefaultProfileId ?? '', profiles: nextProfiles)`
  - `deleteProfile()` writes the same legacy field back through `TerminalProfilesDocument` before any preferences-side repair write happens
- `app/lib/features/profiles/profile_repository.dart`
  - `save()` persists whatever `TerminalProfilesDocument` it receives, so the schema field remains part of normal writes
- `app/lib/features/profiles/profile_models.dart`
  - `TerminalProfilesDocument` still requires `defaultProfileId` in both the constructor and JSON encoding/decoding contract

## Compatibility Window Consumers

The compatibility window is still protected and observable in current tests:

- `app/test/sessions/session_controller_phase3_test.dart`
  - protects bootstrap pref-over-legacy precedence
  - protects legacy fallback when preferences are absent
  - protects “setDefaultProfile writes only app preferences”
- `app/test/sessions/session_controller_test.dart`
  - duplicates the same compatibility guarantees in broader regression coverage
  - explicitly protects `deleteProfile()` keeping the legacy field written while preferences perform repair-write
- `app/test/shell/shell_screen_phase3_test.dart`
  - protects fallback wording in the defaults dialog during the compatibility window
- `app/test/profiles/profile_repository_test.dart`
  - protects on-disk compatibility for profile documents that still carry `defaultProfileId`

Today these tests do not treat legacy behavior as migration-only. They still treat it as supported repo behavior.

## Removal Preconditions

Required preconditions and current evaluation:

- preferences are proven to be the only long-term source of truth
  - **Met for configured writes**
  - `setDefaultProfile()` / `resetDefaultProfile()` already write only preferences
- bootstrap no longer needs legacy `defaultProfileId` as a normal path
  - **Not met**
  - preferences-absent bootstrap still intentionally falls back to legacy
- save/delete profile flows no longer need to write the legacy field back into profile docs
  - **Not met**
  - both `saveProfile()` and `deleteProfile()` still do this today
- shell Phase 3 UI no longer relies on legacy fallback copy as a primary user path
  - **Not met**
  - fallback messaging is still explicitly protected in `shell_screen_phase3_test.dart`
- tests can move from “compatibility window is protected behavior” to migration-only or full removal
  - **Not met**
  - current tests still codify the compatibility window as intentional runtime behavior
- repository strategy for older on-disk profile docs is explicit
  - **Partially met**
  - tolerant read exists, but the repo has not yet committed to “read old docs but stop writing legacy field” versus one-time migration
- minimum verification chain for future implementation is known
  - **Met**
  - see `Follow-up Tasks` below

## Risk Review

- **Removal now is too early**
  - removing the field today would require simultaneous schema, bootstrap, save/delete, UI-copy, and test-contract changes
  - that is broader than a safe first follow-up for this lane
- **Keeping the current window forever is also wrong**
  - canonical ownership is already preferences-first, so continuing to write legacy state indefinitely only extends dual-write ambiguity
- **The lowest-risk next move is narrowing**
  - stop normal write-path propagation first
  - keep tolerant read for older on-disk documents until a later review decides whether full removal is safe
- **Shared-doc risk must stay separate**
  - `T-055 forced-closed` manual-matrix risk is unrelated and should not influence this defaults decision

## Decision Options

### Option 1 — `Not ready`

Keep the current compatibility window untouched.

- Pros:
  - zero migration risk right now
  - avoids touching defaults/lifecycle behavior after `T-056`
- Cons:
  - leaves canonical ownership and normal write behavior misaligned
  - preserves unnecessary legacy writes in routine profile mutations

### Option 2 — `Ready for narrowing`

Open one focused implementation task that narrows the compatibility window without removing the schema field yet.

- Pros:
  - aligns normal write behavior with the existing preferences-first contract
  - keeps tolerant read available for older on-disk profile docs
  - creates a bounded task instead of a full deprecation swing
- Cons:
  - still leaves a second review/removal step later
  - requires deliberate test rewriting from “protected compatibility” to “narrowed compatibility”

### Option 3 — `Ready for removal`

Open one implementation task that removes the field, shrinks read/write paths, and rewrites the compatibility contract in one round.

- Pros:
  - finishes the deprecation in a single implementation lane
  - removes dual-source ambiguity completely
- Cons:
  - too broad for the current repo state
  - current bootstrap, repository schema, UI fallback wording, and tests are not yet reduced enough to make this a narrow change

## Recommended Verdict

Final locked verdict: `Ready for narrowing`

Rationale:

- The canonical source of truth is already stable: preferences own configured defaults.
- The remaining problem is not conceptual uncertainty; it is leftover compatibility breadth.
- The repo is ready to narrow normal behavior by stopping routine legacy write-back and by shrinking which code paths still treat legacy defaults as first-class runtime behavior.
- The repo is **not** ready for full removal because bootstrap fallback, schema shape, fallback UI wording, and multiple tests still intentionally encode the compatibility window.

`Ready for removal` would skip the needed intermediate contraction step. `Not ready` would ignore that the repo has already finished the source-of-truth decision and now mainly needs cleanup of the remaining compatibility surface.

## Follow-up Tasks

This review does **not** create an implementation task directly. The next step should go through:

- `.omx/context/defaultprofileid-deprecation-implementation-kickoff-checklist-20260422T065644Z.md`

That kickoff should create exactly one focused narrowing task whose target is:

- stop normal `saveProfile()` / `deleteProfile()` flows from writing legacy `defaultProfileId` back into `TerminalProfilesDocument`
- keep tolerant read for older on-disk profile documents during the narrowed compatibility window
- reduce shell/UI wording that treats legacy fallback as a primary steady-state path
- rewrite tests from “compatibility window is protected runtime behavior” toward “legacy path is narrowed compatibility behavior”

Minimum verification chain for that future narrowing task should include:

- `cd /Users/robinfai/personal/flutterm/app`
- `flutter analyze`
- `flutter test test/sessions/session_controller_phase3_test.dart`
- `flutter test test/sessions/session_controller_test.dart`
- `flutter test test/profiles/profile_repository_test.dart`
- `flutter test test/shell/shell_screen_phase3_test.dart`
- `flutter test integration_test/flutterm_smoke_test.dart`

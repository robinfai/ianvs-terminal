# Context Snapshot — Hyper Phase 4 Formal Writeup Checklist

## Task Statement
Once `T-055` is fully resolved, convert the existing Phase 4 skeleton into the formal pair of planning artifacts:

- `.omx/plans/prd-hyper-like-phase4-interaction-polish.md`
- `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`

This checklist exists so the next planner can write both files in one pass without reopening the scope or guessing the order of work.

## Gate Check Before Writing
Do not start formal Phase 4 writeup until all of the following are true:
- `docs/tasks/T-055-terminal-manual-matrix-execution.md` is either:
  - normally closed with explicit results for all four manual matrix lanes, or
  - explicitly `forced-closed` with a clear override record
- If the repo is using the `forced-closed` path, `docs/TESTING.md` and `docs/KNOWN_ISSUES.md` must both say the manual matrix remains unexecuted and survives only as a documented known risk.
- Every product `fail` from a real `T-055` run has already been split into a focused task.
- Every host/tooling `blocked` result from a real `T-055` run has already been split into an environment task.
- No higher-priority lifecycle, focus, or startup regression is currently overriding the main lane.

If any gate fails, stop and return to `T-055` or its follow-up tasks instead of writing the formal Phase 4 plan files.

## Formal PRD Writeup Order
Write `.omx/plans/prd-hyper-like-phase4-interaction-polish.md` first.

Use these sources in order:
1. `.omx/context/hyper-phase4-interaction-polish-skeleton-20260421T084736Z.md`
2. `.omx/plans/prd-hyper-like-terminal-evolution.md`
3. `.omx/plans/prd-hyper-like-phase3-ui-experience.md`

Required sections:
- `Requirements Summary`
- `Grounding / Current Code Facts`
- `Boundaries / Non-goals`
- `Concrete Delivery Slices`
- `Acceptance Criteria`
- `Risks / Mitigations`
- `ADR`

Required grounding anchors:
- `app/test/shell/shell_screen_phase2a_test.dart`
- `app/test/shell/shell_screen_phase2b_test.dart`
- `app/test/widget_test.dart`
- `app/integration_test/flutterm_smoke_test.dart`

Required content rules:
- Keep only the three already-approved delivery slices:
  - session start / exit presentation
  - focus transition clarity
  - behavior-preserving feedback
- State explicitly that protected terminal semantics remain unchanged.
- State explicitly that launcher / dialog / empty-state close-flow focus ownership should become clearer.
- State explicitly that session start / exit / recovery states should become easier to understand.
- Keep keyboard-heavy smoke behavior unchanged.

## Formal Test-Spec Writeup Order
Only start the test-spec after the PRD wording is locked.

Write `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md` second.

Use these sources in order:
1. `.omx/context/hyper-phase4-interaction-polish-skeleton-20260421T084736Z.md`
2. `.omx/plans/test-spec-hyper-like-terminal-evolution.md`
3. `docs/TESTING.md`

Required sections:
- `Testing Principles`
- `Protected Regression Reruns`
- `Targeted Automation`
- `Manual Smoke`
- `Phase Gate`

Required minimum regression chain:

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

If Phase 4 directly consumes session lifecycle state, also add:

```bash
flutter test test/sessions/session_controller_test.dart
```

Required targeted-automation rules:
- add only shell-level lifecycle / focus-visible tests
- prefer extending `app/test/shell/`
- do not create new test surface for copy-only text tweaks, spacing-only changes, color-only changes, or light animation that introduces no new state

Required manual smoke:
- session start -> active state
- launcher open/close -> focus return
- defaults/dialog close -> terminal viewport regain focus
- tab close / shell exit -> empty-state transition
- empty-state -> `New Tab` recovery
- `pwd`, `echo hello`, `ls`, copy/paste, scroll, resize

## Same-Round Submission Rule
The formal PRD and test-spec must land in the same planning commit.

Before that commit:
- verify both files follow the skeleton section structure
- verify both files keep terminal input / selection / copy-paste / scroll / resize / PTY semantics protected
- verify neither file mixes in the `defaultProfileId` deprecation review
- verify neither file absorbs unrelated `T-055` findings that should remain focused tasks

Do not create, in the same round or earlier:
- `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`
- any `docs/tasks/T-056-*`

## Handoff Outcome
After this checklist is executed correctly:
- the repo contains the formal Phase 4 PRD and test-spec
- an implementation agent can work from those two files plus `docs/TESTING.md`
- the `defaultProfileId` deprecation review still remains a later, separate planning step
- when that later step begins, start from `.omx/context/defaultprofileid-deprecation-review-parking-lot-20260421T094305Z.md` instead of reopening the compatibility-window question from scratch
- once the formal planning pair exists, continue with `.omx/context/hyper-phase4-implementation-kickoff-checklist-20260422T063911Z.md` instead of stopping at planning completion

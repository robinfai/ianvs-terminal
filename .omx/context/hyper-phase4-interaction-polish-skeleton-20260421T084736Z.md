# Context Snapshot — Post-T-055 Hyper Phase 4 Interaction Polish Skeleton

## Task Statement
Define the exact skeleton for the future Hyper-like Phase 4 PRD and test-spec without creating those `.omx/plans/` files before `T-055` is actually closed.

## Desired Outcome
Leave a repo-native handoff artifact that tells the next planner exactly how to write:

- `.omx/plans/prd-hyper-like-phase4-interaction-polish.md`
- `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`

The intent is to make those two plan files routine to draft once `T-055` is resolved, while keeping current work inside the gate.

## Gate / Preconditions
- `docs/tasks/T-055-terminal-manual-matrix-execution.md` must have explicit results for all four manual matrix lanes.
- No new product-level `fail` may still be blocking priority.
- Any host/tooling `blocked` result must already be split to the environment lane.
- Before those conditions are true, do **not** create the formal Phase 4 plan files and do **not** start the `defaultProfileId` deprecation review.

## Grounding / Current Code Facts
- Existing Hyper-like umbrella plan already defines Phase 4 as `interaction polish within existing contracts` in `.omx/plans/prd-hyper-like-terminal-evolution.md`.
- Existing test baseline already says Phase 4 must rerun protected regressions plus lifecycle/focus smoke in `.omx/plans/test-spec-hyper-like-terminal-evolution.md`.
- `app/test/shell/shell_screen_phase2a_test.dart` already covers launcher open/close behavior.
- `app/test/shell/shell_screen_phase2b_test.dart` already covers launcher close restoring terminal focus.
- `app/test/widget_test.dart` already covers last-tab close and shell-exit empty-state paths.
- `app/integration_test/ianvs_smoke_test.dart` already covers command menu, defaults close, and empty-state recovery.
- `docs/TESTING.md` already defines the standard shell / launcher / defaults verification commands that Phase 4 must reuse.

## Future PRD Skeleton
The future `.omx/plans/prd-hyper-like-phase4-interaction-polish.md` should contain these fixed sections:

### Requirements Summary
- `smoother lifecycle presentation`
- `clearer focus transitions`
- `refined but behavior-preserving feedback`

### Grounding / Current Code Facts
- Cite the existing shell/focus/lifecycle tests listed above.
- State explicitly that Phase 4 is polishing launcher / focus / empty-state expression, not redefining the state machine.

### Boundaries / Non-goals
- Do not change terminal input / selection / copy-paste / scroll / resize / PTY semantics.
- Do not introduce Rust core / PTY / FFI changes unless Flutter-only insufficiency is proven first.
- Do not expand into settings / customization / renderer / cross-platform work.
- Route non-Phase-4 product findings back into focused tasks instead of absorbing them here.

### Concrete Delivery Slices
- `Slice 1: session start / exit presentation`
  - Polish session bootstrap, shell exit, last-tab close, and empty-state recovery presentation.
  - Allow microcopy, hierarchy, placeholder, and timing-feedback changes only.
  - Do not change session creation or destruction contracts.
- `Slice 2: focus transition clarity`
  - Make launcher close, dialog close, tab switch, and empty-state recovery focus ownership easier to understand.
  - Allow visible focus cues or supporting shell copy.
  - Do not add shortcut scope or alter input routing.
- `Slice 3: behavior-preserving feedback`
  - Improve close/open/exit/recover feedback completeness.
  - Allow lightweight status hints, microcopy, and consistent empty/loading phrasing.
  - Do not add persisted state, settings, or background flows.

### Acceptance Criteria
- protected terminal semantics unchanged
- focus owner after launcher / dialog / empty-state close-flow is clearer
- session start / exit / recovery states are understandable
- manual smoke for `pwd`, `echo hello`, `ls`, copy/paste, scroll, and resize still matches current behavior

### Risks / Mitigations
- breadth drift
- focus/input regressions
- polish accidentally changing state rules
- unrelated post-`T-055` findings being mixed into Phase 4

### ADR
- `Decision`
- `Drivers`
- `Alternatives considered`
- `Why chosen`
- `Consequences`
- `Follow-ups`

## Future Test-Spec Skeleton
The future `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md` should contain these fixed sections:

### Testing Principles
- Existing terminal behavior remains a protected regression contract.
- Phase 4 proves clearer shell/UI expression, not broader state behavior.
- Any focus-sensitive change must carry keyboard-path evidence.

### Protected Regression Reruns
Minimum command chain:

```bash
cd /Users/robinfai/personal/ianvs_terminal/app
flutter analyze
flutter test test/widget_test.dart
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test integration_test/ianvs_smoke_test.dart
```

If the Phase 4 change consumes session lifecycle state directly, also rerun:

```bash
flutter test test/sessions/session_controller_test.dart
```

### Targeted Automation
- Add or extend shell-level widget tests only for newly exposed lifecycle / focus-visible behavior.
- Prefer `app/test/shell/shell_screen_phase4_test.dart` or an equivalent bounded extension under `app/test/shell/`.
- Keep reusing `app/test/widget_test.dart` for empty-state / exit recovery paths.
- Do not add core / FFI tests unless the change genuinely crosses that boundary.
- Do not add new tests for copy-only text changes, spacing-only changes, or light animation tweaks that introduce no new state.

### Manual Smoke
- session start -> active state
- launcher open/close -> focus return
- defaults/dialog close -> terminal viewport regain focus
- tab close / shell exit -> empty-state transition
- empty-state -> `New Tab` recovery
- keyboard-heavy smoke: `pwd`, `echo hello`, `ls`, copy/paste, scroll, resize

### Phase Gate
- check acceptance criteria line-by-line
- keep the protected regression baseline green
- sync related docs
- if anyone proposes core / PTY work, require explicit proof that Flutter-only is insufficient

## Parking Lot After Phase 4
Do not create the file yet, but reserve this review artifact name:

- `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`

That review starts only after:
- `T-055` is closed
- the Phase 4 PRD and test-spec both exist
- Phase 4 does not expose a higher-priority lifecycle or focus regression

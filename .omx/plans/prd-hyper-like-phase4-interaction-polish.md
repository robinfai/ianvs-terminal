# PRD — Hyper-like Phase 4 Interaction Polish

## Requirements Summary
Phase 4 should polish the existing shell interaction layer without changing protected terminal behavior contracts. The approved delivery stays limited to:
- smoother lifecycle presentation
- clearer focus transitions
- refined but behavior-preserving feedback

## Grounding / Current Code Facts
- `app/test/shell/shell_screen_phase2a_test.dart` already covers launcher open/close behavior and keeps the launcher path deterministic.
- `app/test/shell/shell_screen_phase2b_test.dart` already covers launcher close restoring terminal focus and protects the shortcut/focus boundary.
- `app/test/widget_test.dart` already covers last-tab close, shell-exit empty-state, and empty-state recovery paths.
- `app/integration_test/flutterm_smoke_test.dart` already covers command menu, defaults close, and empty-state recovery smoke.
- `docs/TESTING.md` already defines the standard Flutter verification chain and the shell/manual-smoke wording that Phase 4 should reuse.
- `T-055` was `forced-closed` on `2026-04-22`; the manual terminal matrix remains an acknowledged known risk, and Phase 4 must not pretend to resolve or supersede that missing evidence.

## Boundaries / Non-goals
- Do not change terminal input, selection, copy/paste, scroll, resize, PTY, or host-feature semantics.
- Do not introduce Rust core, PTY, or FFI changes unless Flutter-only insufficiency is explicitly proven first.
- Do not expand into settings IA, richer customization, renderer work, SSH, or cross-platform work.
- Do not absorb the parked `defaultProfileId` deprecation review into this phase.
- Do not reframe the missing `T-055` manual matrix as passed; keep it as a documented known risk outside this scope.
- Route any unrelated product finding into a focused task instead of widening Phase 4.

## Concrete Delivery Slices
### Slice 1 — Session start / exit presentation
- Polish bootstrap, shell exit, last-tab close, and empty-state recovery presentation.
- Allow microcopy, hierarchy, placeholder, and lightweight timing-feedback changes only.
- Do not change session creation, session destruction, or shell lifecycle rules.

### Slice 2 — Focus transition clarity
- Make launcher close, dialog close, tab switch, and empty-state recovery focus ownership easier to understand.
- Allow visible focus cues, supporting shell copy, or clearer shell-surface affordances.
- Do not alter shortcut routing, key handling, or terminal input ownership rules.

### Slice 3 — Behavior-preserving feedback
- Improve close/open/exit/recover feedback completeness and consistency.
- Allow lightweight status hints, microcopy cleanup, and more intentional empty/loading phrasing.
- Do not add persisted state, background flows, or new command surfaces.

## Acceptance Criteria
- Protected terminal semantics remain unchanged.
- Launcher, dialog, tab-close, and empty-state close flows make the current focus owner clearer.
- Session start, exit, and recovery states are easier to understand without redefining the state machine.
- Keyboard-heavy smoke for `pwd`, `echo hello`, `ls`, copy/paste, scroll, and resize still matches current behavior.
- Phase 4 documentation and implementation do not claim to close the unresolved manual-matrix risk left by `T-055 forced-closed`.

## Risks / Mitigations
- **Breadth drift**: keep work inside the three approved slices and split anything else into a focused task.
- **Focus/input regressions**: rerun the protected shell/widget/integration baseline and require keyboard-path evidence for focus-sensitive changes.
- **Polish mutating state behavior**: keep changes in Flutter shell/UI surfaces and treat existing lifecycle behavior as protected.
- **Missing manual-matrix risk getting forgotten**: keep `docs/TESTING.md` and `docs/KNOWN_ISSUES.md` explicit that `T-055` was forced-closed rather than completed.

## ADR
### Decision
Proceed with Hyper-like Phase 4 as a shell-polish phase inside existing terminal contracts, even though `T-055` was force-closed rather than completed.

### Drivers
- The repo needs a live product-planning lane instead of an indefinite off-machine handoff wait state.
- Existing Phase 2 and Phase 3 shell/lifecycle tests already provide strong protected-regression anchors for UI polish work.
- The highest-value next step remains shell-level interaction polish, not deeper architecture or defaults review work.

### Alternatives considered
- Wait for a real target-machine manual matrix before any new planning.
- Mix the unresolved manual-matrix work into Phase 4.
- Use Phase 4 to reopen broader settings/customization scope.

### Why chosen
The forced-close override keeps the unresolved manual-matrix risk visible while still letting the repo move onto the next bounded planning step. Restricting Phase 4 to shell-level polish avoids pretending that missing manual evidence is solved and avoids turning the phase into a catch-all.

### Consequences
- Phase 4 planning now proceeds with an explicit documented risk rather than a completed manual matrix.
- Shared docs must continue to state that VT220, powerline, trackpad, and DPI proof remains missing.
- `T-056` implementation kickoff and the parked `defaultProfileId` review remain later, separate steps.

### Follow-ups
- Create `docs/tasks/T-056-hyper-phase4-interaction-polish.md` only through the existing implementation kickoff checklist.
- Keep the `defaultProfileId` deprecation review parked until `T-056` no longer blocks that lane.
- If future product decisions need real manual-matrix proof, open a new focused task rather than reviving `T-055`.

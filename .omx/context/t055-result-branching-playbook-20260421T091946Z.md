# Context Snapshot — T-055 Result Branching Playbook

## Historical Status
- Superseded on `2026-04-22 15:12 CST / 2026-04-22T07:12:08Z` when `T-055` was `forced-closed` through `.omx/context/t055-forced-close-override-checklist-20260422T071208Z.md`.
- Retain this file only as the normal-path branching guide for a target-machine run that never happened.
- Do not treat it as a current operator entrypoint.

## Task Statement
When a target machine finishes `T-055 Terminal Manual Matrix Execution`, split every resulting `blocked` or `fail` outcome into the correct follow-up task instead of leaving repair work inside `T-055`.

## Gate / Constraints
- Use this playbook only after the target machine has explicit `T-055` results.
- Do not pre-reserve task numbers; always take the next available `docs/tasks/T-0NN`.
- Do not modify the `Execution Record Template` in `docs/tasks/T-055-terminal-manual-matrix-execution.md`.
- Do not treat host/tooling `blocked` results as product regressions.
- Do not create empty placeholder tasks for branch types that did not occur.
- Keep formal Phase 4 `.omx/plans/` artifacts and the `defaultProfileId` deprecation review gated until `T-055` is fully resolved.

## Numbering Rule
- Recompute the next available task number from `docs/tasks/` at the time of branching.
- If the next available number is `T-056`, the first new task becomes `T-056`; later tasks in the same run increment in discovery order.
- If one target-machine run produces multiple branches, assign numbers in the order the results are confirmed.
- Do not reserve future numbers for branches that have not happened yet.

## Branch Matrix
### host/tooling `blocked`
- foreground / target-machine environment blocker
  - task slug: `terminal-manual-matrix-target-machine-unblock`
  - use when the machine cannot provide a real foreground interactive desktop path, or when the matrix is blocked by missing target-machine prerequisites
- `HardwareKeyboard` / macOS keyboard-chain environment blocker
  - task slug: `macos-hardware-keyboard-environment`
  - use when the blocker is a host input-chain or duplicated key-event environment problem rather than a terminal product defect

### product `fail`
- VT220 behavior gap
  - task slug: `terminal-vt220-gap`
- prompt / glyph / trailing background fidelity gap
  - task slug: `terminal-prompt-fidelity-gap`
- trackpad scrolling interaction gap
  - task slug: `terminal-trackpad-scrollback-gap`
- font metric / DPI resize / window-size translation gap
  - task slug: `terminal-dpi-resize-translation-gap`
- `flutter run -d macos` reached a real foreground interactive state but exposed a product startup fault
  - do not reuse an environment slug
  - name the task after the product fault itself
  - default fallback slug if no narrower product label is available: `terminal-macos-startup-foreground-failure`

## Creation Rules
- Open one focused task per `fail`.
- Open one environment task per host/tooling `blocked`.
- If multiple results occur in the same run, do not merge them into a single umbrella repair task.
- `T-055` stays a results-and-pointers task only; do not mix repair work into it.

## Required Task Body
Base each new task on `docs/tasks/TEMPLATE.md`.

Required sections:
- `Goal`
- `Scope`
- `Non-goals`
- `Functional Acceptance`
- `Verification Commands`
- `Manual QA`
- `Done When`
- `Risks / Follow-ups`

Required content inside those sections:
- minimum repro
- impact range
- result source time and machine
- the exact `T-055` matrix item that triggered the task
- one minimum verification command or one explicit manual acceptance line
- for `terminal-dpi-resize-translation-gap`, also require:
  - shell-driven or viewport-driven path
  - X-axis, Y-axis, or both
  - prompt / cell metric / DPI condition
  - whether measured cell size had already been established

## Per-Branch Defaults
### Environment tasks
- `Goal` should focus on reproducing and unblocking the host/tooling condition.
- `Non-goals` must explicitly say the task does not repair terminal product logic.
- `Verification Commands` should stay on the environment reproduction chain, such as:
  - `command -v vttest`
  - `flutter run -d macos`
  - log capture or foreground-desktop confirmation steps
- default first step is docs / repro / blocker ownership, not product code changes.

### Product tasks
- `Goal` should focus on one user-visible defect only.
- `Non-goals` must explicitly exclude other matrix lanes.
- `Verification Commands` must include at least one minimum automated command or one explicit manual acceptance line.
- `Manual QA` should reuse the exact matrix step that triggered the `fail`, rather than expanding into a broader smoke pass.
- default first step is writing minimum repro plus verification line, then scoping implementation work afterward.
- `terminal-dpi-resize-translation-gap` follow-up tasks must explicitly distinguish shell-driven vs viewport-driven behavior before any implementation work is scoped.

## T-055 Back-Reference Rule
- Every new task must reference `T-055` in its opening paragraph or in `Risks / Follow-ups`.
- The matching result entry in `docs/tasks/T-055-terminal-manual-matrix-execution.md` should gain one line stating which task number now owns the follow-up.
- `T-055` should keep the result summary and the task pointer, but not the repair narrative.

## Do Not Do
- Do not pre-create `T-056+` task files.
- Do not pre-create `.omx/plans/prd-hyper-like-phase4-interaction-polish.md`.
- Do not pre-create `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`.
- Do not pre-create `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`.

# Context Snapshot — T-055 Forced Close Override Checklist

## Task Statement
Explicitly close `T-055 Terminal Manual Matrix Execution` without completing the off-machine run, preserve the unexecuted manual-matrix gap as a documented known risk, and switch the repo's live planning lane to the formal Phase 4 writeup chain.

## Inputs
- `docs/tasks/T-055-terminal-manual-matrix-execution.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `.omx/context/t055-terminal-manual-matrix-off-machine-20260422T032930Z.md`
- `.omx/context/t055-target-machine-execution-runbook-20260421T085450Z.md`
- `.omx/context/t055-result-branching-playbook-20260421T091946Z.md`
- `.omx/context/hyper-phase4-formal-writeup-checklist-20260421T093447Z.md`

## Override Gate
- The repo has made an explicit decision to stop the off-machine `T-055` execution path instead of waiting for a target-machine run.
- `docs/tasks/T-055-terminal-manual-matrix-execution.md` contains a final disposition record using the exact status word `forced-closed`.
- That final disposition record states the unresolved manual-matrix lanes and says the task is closing by override, not by completed execution.
- `docs/TESTING.md` and `docs/KNOWN_ISSUES.md` both say the manual matrix remains unexecuted and currently survives only as a documented risk.
- The live handoff artifacts have been rewritten into historical or superseded records instead of operator entrypoints.

## Override Sequence
1. Add the `forced-closed` final disposition record to `docs/tasks/T-055-terminal-manual-matrix-execution.md`.
2. Rewrite the `Off-Machine Handoff` section into a historical summary and tighten `Post-T-055 Default Next Step` to the Phase 4 formal writeup lane.
3. Mark the active snapshot, target-machine runbook, and branching playbook as historical or superseded records rather than live entrypoints.
4. Mark the normal closeout and post-close archive checklists as normal-path only; if `T-055` closes without a target-machine run, this override checklist is the only allowed owner.
5. Update `docs/TESTING.md` and `docs/KNOWN_ISSUES.md` so the missing VT220, powerline, trackpad, and DPI evidence stays visible as a known risk.
6. Record the forced close and the Phase 4 lane switch in `.omx/notepad.md`.
7. Continue directly with `.omx/context/hyper-phase4-formal-writeup-checklist-20260421T093447Z.md` and land the formal Phase 4 PRD + test-spec in the same round.

## Terminology Rules
- Use the exact status word `forced-closed`.
- Do not describe `T-055` as `done`, `resolved`, `completed`, or `verified`.
- State explicitly that the terminal manual matrix remains unexecuted.
- If future work needs real manual-matrix proof, open a new focused task instead of reviving the old live handoff chain.

## Phase 4 Handoff
- After the override is recorded, the active planning entrypoints are:
  - `.omx/context/hyper-phase4-interaction-polish-skeleton-20260421T084736Z.md`
  - `.omx/context/hyper-phase4-formal-writeup-checklist-20260421T093447Z.md`
- This override round may create only the formal Phase 4 PRD + test-spec.
- Do not create `docs/tasks/T-056-hyper-phase4-interaction-polish.md` in the same step.
- Do not create `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md` in the same step.

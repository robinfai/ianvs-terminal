# Context Snapshot — T-055 Result Closeout Checklist

## Applicability
- Use this checklist only after a target machine actually completes the `T-055` matrix run and fills the task's `Execution Record Template`.
- If the repo decides to stop the run and close `T-055` by override instead, do not use this checklist; use `.omx/context/t055-forced-close-override-checklist-20260422T071208Z.md` instead.

## Task Statement
After a target machine completes `T-055 Terminal Manual Matrix Execution`, synchronize the results into the task document and shared docs, then decide whether `T-055` can close or must stay open with explicit follow-up owners.

## Inputs
- `docs/tasks/T-055-terminal-manual-matrix-execution.md`
- `.omx/context/t055-target-machine-execution-runbook-20260421T085450Z.md`
- `.omx/context/t055-result-branching-playbook-20260421T091946Z.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

## Closeout Sequence
1. Confirm all seven result items in the `Execution Record Template` are filled:
   - `command -v vttest`
   - `integration_test/ianvs_smoke_test.dart`
   - `flutter run -d macos`
   - `VT220 vttest`
   - `powerline / ANSI prompt fidelity`
   - `trackpad scrollback`
   - `font-metric / DPI resize`
2. For every `blocked` or `fail`, use the branching playbook to create the correct follow-up task and write the new task number back into the matching `T-055` result entry.
3. Update `docs/TESTING.md` with the latest manual-matrix baseline, recommended commands, and current validation wording.
4. Update `docs/KNOWN_ISSUES.md` with any still-accepted product or environment limitation exposed by the run.
5. Check `T-055` `Done When` against the now-updated task record and shared docs.
6. If every closeout condition is satisfied, close `T-055`; otherwise keep it open and record the remaining blocker or follow-up owner explicitly.
7. If `T-055` is truly closed, continue with `.omx/context/t055-post-close-archive-checklist-20260422T062718Z.md` to archive the live handoff artifacts and switch the default planning lane to Phase 4.

## Document Sync Rules
- `docs/TESTING.md` should record the latest execution baseline, recommended commands, and current validation contract only.
- `docs/KNOWN_ISSUES.md` should record still-accepted product or environment boundaries only; do not paste the full execution record into it.
- `docs/tasks/T-055-terminal-manual-matrix-execution.md` remains a results-and-pointers task; do not move repair narratives into it.

## Closure Rules
- Close `T-055` only when all four manual matrix lanes have explicit results, every `fail` or `blocked` outcome has a follow-up owner, and `docs/TESTING.md` plus `docs/KNOWN_ISSUES.md` are synchronized.
- If the run produced only partial results, or if any follow-up task is still missing, keep `T-055` open and state the remaining blocker clearly.

## Phase 4 Gate
- Begin the existing Phase 4 skeleton and formal writeup flow only after `T-055` is truly closed.
- Do not treat a partially-filled matrix or unsplit follow-up as sufficient to begin Phase 4 planning.

# Context Snapshot — T-055 Off-Machine Manual Matrix Execution

## Task Statement
Resume `T-055 Terminal Manual Matrix Execution` on a standard interactive macOS development machine instead of the current blocked host.

## Desired Outcome
Complete the off-machine manual-matrix run, record all required `pass` / `fail` / `blocked` outcomes in the existing `T-055` template, and split any resulting environment or product follow-up tasks without changing terminal product logic in this handoff step.

## Known Facts / Evidence
- Branch for continuation: `codex/hyper-first-shell`
- Stop-point freeze commit: `78508cd`
- Stop-point evidence time: `2026-04-21 14:52 CST`
- Current host is blocked for `T-055` execution.
- `./tools/check_terminal_manual_matrix_prereqs.sh` on the current host reports:
  - `command -v vttest`: `blocked`
  - `integration_test/flutterm_smoke_test.dart`: `pass`
  - `flutter run -d macos`: `blocked`
- Current host still reports `Failed to foreground app; open returned 1` during `flutter run -d macos`.
- Current host lacks:
  - installed `vttest`
  - a confirmed interactive macOS foreground path
  - physical trackpad validation conditions
  - alternate font-metric / DPI validation conditions

## Constraints
- Do not treat host/tooling blockers as terminal product regressions.
- Keep using the existing `T-055` execution record template; do not invent a new record format.
- Do not modify terminal product logic as part of the handoff itself.
- Do not start `Phase 4` planning until `T-055` is fully resolved and no product `fail` remains.

## Target Machine Preconditions
- App can be foregrounded to a real interactive macOS desktop.
- `vttest` is installed.
- A physical trackpad is available.
- At least one alternate font or DPI condition is available for resize verification.

## Target Machine Execution Steps
1. `git fetch origin`
2. `git checkout codex/hyper-first-shell`
3. `git pull --ff-only origin codex/hyper-first-shell`
4. Confirm you are on the latest pushed `HEAD` for `codex/hyper-first-shell`, not only the older freeze commit `78508cd`.
5. Run `./tools/check_terminal_manual_matrix_prereqs.sh`
6. Run `cd app && flutter run -d macos`
7. Confirm foreground interaction manually on the target machine.
8. Execute the four manual matrix lanes:
   - `VT220 vttest`
   - `powerline / ANSI prompt fidelity`
   - `trackpad scrollback`
   - `font-metric / DPI resize`
9. Write all results back into `docs/tasks/T-055-terminal-manual-matrix-execution.md`

## Result Recording
- Use the existing execution template in `docs/tasks/T-055-terminal-manual-matrix-execution.md`.
- Required recorded items:
  - `command -v vttest`
  - `integration_test/flutterm_smoke_test.dart`
  - `flutter run -d macos`
  - `VT220 vttest`
  - `powerline / ANSI prompt fidelity`
  - `trackpad scrollback`
  - `font-metric / DPI resize`
- Every item must be `pass`, `fail`, or `blocked`.

## Branching Rules
- host/tooling `blocked`:
  - return to the environment-unblock lane
  - create an environment task instead of a product regression task
- product `fail`:
  - create a focused task with minimal repro, impact range, and minimum verification line
- all matrix results explicit and no product `fail`:
  - close `T-055`
  - only then start `Phase 4` PRD + test-spec planning

## Key Files
- `docs/tasks/T-055-terminal-manual-matrix-execution.md`
- `tools/check_terminal_manual_matrix_prereqs.sh`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

# Context Snapshot — T-055 Off-Machine Manual Matrix Execution

## Task Statement
Resume `T-055 Terminal Manual Matrix Execution` on a standard interactive macOS development machine instead of the current unsuitable local host.

## Desired Outcome
Complete the off-machine manual-matrix run, record all required `pass` / `fail` / `blocked` outcomes in the existing `T-055` template, and split any resulting environment or product follow-up tasks without changing terminal product logic in this handoff step.

## Current Continuation Baseline
- Branch for continuation: `codex/hyper-first-shell`
- Continuation `HEAD`: `6f8b44d394c1005cd1cf07a67db5010c959bd074`
- Current local-host verdict: `unsuitable local host`

## Latest Local Evidence
- Latest preflight evidence time: `2026-04-22 11:11 CST`
- Latest fixed-port run evidence time: `2026-04-22 10:11 CST`
- Host: `BINGHUILUO-MC6`
- macOS: `26.3.1 (25D771280a)`
- Frontmost app during preflight: `Codex`

## Facts That Are No Longer Blockers
- `command -v vttest`: `pass`
  - `vttest` available at `/opt/homebrew/bin/vttest`
- `flutter doctor -v`: `pass`
- `flutter devices`: `pass`
- `integration_test/flutterm_smoke_test.dart`: `pass`

## Remaining Local Blockers
- `flutter run -d macos` still reports `Failed to foreground app; open returned 1`
- `UI elements enabled`: `false`
- The current session cannot complete verified viewport click + keyboard input
- Physical trackpad validation conditions are still missing
- Alternate font-metric / DPI validation conditions are still missing

## Foreground / Accessibility Facts
- The fixed-port run still launched the app, exposed a Dart VM Service, and produced a visible app process.
- The app still was not confirmed as the frontmost interactive app.
- This session still lacks usable accessibility conditions for a decisive input check.
- This is not a terminal product regression.
- This is a host/accessibility/foreground-condition blocker.

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
4. Confirm `HEAD` is `6f8b44d394c1005cd1cf07a67db5010c959bd074` or a newer descendant, not the older local stop-point commits.
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

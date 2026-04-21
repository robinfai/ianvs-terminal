# Context Snapshot — T-055 Target Machine Execution Runbook

## Task Statement
Complete `T-055 Terminal Manual Matrix Execution` on a standard interactive macOS development machine and write all results back into the existing `docs/tasks/T-055-terminal-manual-matrix-execution.md` template.

## Gate / Constraints
- Do not modify terminal product logic while executing this runbook.
- Do not invent a new result template; use the existing `Execution Record Template` in `docs/tasks/T-055-terminal-manual-matrix-execution.md`.
- Do not treat host/tooling `blocked` results as terminal product regressions.
- Do not create formal Phase 4 `.omx/plans/` artifacts until `T-055` is fully resolved and no product `fail` remains.
- Keep the existing off-machine stop-point snapshot `.omx/context/t055-terminal-manual-matrix-off-machine-20260421T081004Z.md` as the baseline for why this run must happen on another machine.

## Target Machine Preconditions
- App can be foregrounded to a real interactive macOS desktop.
- `vttest` is installed and callable from `PATH`.
- A physical trackpad is available.
- At least one alternate font or DPI condition is available for resize verification.

## Execution Sequence
1. `git fetch origin`
2. `git checkout codex/hyper-first-shell`
3. `git pull --ff-only origin codex/hyper-first-shell`
4. Record `git rev-parse HEAD`
5. Run `./tools/check_terminal_manual_matrix_prereqs.sh`
6. Run `cd app && flutter run -d macos`
7. Manually confirm the app is foregrounded and interactive on the real desktop.
8. Execute the four manual matrix lanes in order:
   - `VT220 vttest`
   - `powerline / ANSI prompt fidelity`
   - `trackpad scrollback`
   - `font-metric / DPI resize`
9. Write every result back into `docs/tasks/T-055-terminal-manual-matrix-execution.md` using the existing `Execution Record Template`.

## Recording Rules
Use only `pass`, `fail`, or `blocked` for every item.

### `command -v vttest`
- `pass`: returns an executable path.
- `blocked`: `vttest` is not installed or the machine cannot provide it.
- `fail`: `vttest` exists but cannot be launched or used normally.

### `integration_test/flutterm_smoke_test.dart`
- `pass`: command exits with code `0`.
- `blocked`: target machine cannot provide a runnable macOS Flutter host condition.
- `fail`: command exits non-zero for a reason that is not just missing host/tooling conditions.

### `flutter run -d macos`
- `pass`: app builds and a human confirms real foreground desktop interaction.
- `blocked`: `Failed to foreground app; open returned 1` appears, the run times out without confirmed foreground interaction, or the host does not provide real desktop interaction.
- `fail`: the app reaches a real foreground interactive state, but a reproducible app-start product fault prevents the matrix from continuing.

### `VT220 vttest`
- `pass`: VT220 device attributes, keyboard, and screen-update checks pass.
- `blocked`: `vttest`, VT220 profile, or another execution prerequisite is missing.
- `fail`: a clear VT220 behavior gap is reproduced.

### `powerline / ANSI prompt fidelity`
- `pass`: color, reverse video, trailing background, and glyph alignment all look correct.
- `blocked`: a real prompt, font, or other fidelity precondition is missing.
- `fail`: a clear prompt or glyph fidelity problem is reproduced.

### `trackpad scrollback`
- `pass`: physical-trackpad scrollback, thumb drag, and return-to-bottom behavior all work.
- `blocked`: no physical trackpad is available.
- `fail`: a clear scrolling interaction problem is reproduced.

### `font-metric / DPI resize`
- `pass`: resize and window-size translation behave correctly across at least two font-metric or DPI conditions.
- `blocked`: no alternate font or DPI condition is available.
- `fail`: a clear resize or window-size translation problem is reproduced.

## Evidence Checklist
- absolute date and time
- machine identifier or short host description
- branch name and `HEAD`
- whether `flutter run -d macos` observed a Dart VM Service
- whether `Failed to foreground app; open returned 1` was observed
- whether foreground interaction was manually confirmed

## Branching Rules
- host/tooling `blocked`:
  - return to `T-054 Terminal Manual Matrix Unblock`
  - create or update an environment task instead of a product regression task
- product `fail`:
  - open a focused task with minimum repro, impact range, and minimum verification command or manual acceptance line
- all four manual matrix lanes explicit and no product `fail`:
  - close `T-055`
  - only then begin the formal Phase 4 PRD + test-spec work

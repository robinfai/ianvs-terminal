# T-302 Compatibility Baseline

## Goal

Execute handoff Iteration 01 by replacing compatibility assumptions with layer-by-layer evidence,
deterministic real PTY fixtures and observable resize/reflow diagnostics.

## Scope

- Inventory reusable Rust, Dart/Flutter, integration and helper test assets.
- Publish a Parse/State/Frame/Runtime/UI/Verified capability matrix.
- Add deterministic real-shell and alternate-screen TUI integration fixtures.
- Retain and identify the Unicode width/cursor fixture.
- Expose resize replay count, byte and elapsed-time diagnostics.
- Cover untruncated replay and truncated transcript boundary behavior.
- Publish compatibility-specific known issues and manual verification steps.
- Run `make bootstrap`, `make analyze`, `make test` and `make verify`.

## Non-goals

- Do not perform the Iteration 02 frame-pipeline refactor.
- Do not split the large native session module in this task.
- Do not implement Iteration 03 recording/replay.
- Do not add a new large product feature or redesign the UI.
- Do not claim Linux, Windows, SSH or unexecuted manual evidence.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `example/integration_test/real_pty_acceptance_test.dart`
- `docs/compatibility/`
- `docs/TESTING.md`
- `docs/README.md`
- `docs/tasks/README.md`
- `test/docs_contract_test.dart`

## Functional Acceptance

- Capability matrix covers basics, input, OSC, graphics and shell integration with six-layer status.
- A real `/bin/sh` starts, accepts input, emits output and exits through the macOS app runtime.
- A deterministic alternate-screen TUI starts, resizes, accepts input, restores primary screen and exits.
- Unicode version changes prove width, styled-column and cursor behavior across resize.
- Untruncated resize replay preserves a long logical line and records replay metrics.
- Truncated transcript resize returns a snapshot and records that replay was skipped.
- Missing external/platform/manual evidence remains explicitly visible.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
make bootstrap
make analyze
make test
make verify
```

Focused commands are documented in
[CAPABILITY_MATRIX.md](../../compatibility/CAPABILITY_MATRIX.md).

## Manual QA

Not required to satisfy deterministic Iteration 01 acceptance. Supplemental host and visual lanes
are documented in [MANUAL_VERIFICATION.md](../../compatibility/MANUAL_VERIFICATION.md) and must be
recorded as `pass`, `fail` or `blocked` when run.

## Done When

- All functional acceptance items have repository evidence.
- All four required Make targets have accurate recorded results.
- Documentation links and compatibility contracts pass.
- Iteration 02 and Iteration 03 remain untouched.

## Risks / Follow-ups

- Real `vttest` remains supplemental and depends on the host binary.
- Linux/Windows, SSH, cross-DPI visuals and physical input devices remain outside the automated
  baseline.
- A truncated transcript cannot recreate discarded history during resize.

## Verification Record

| Command | Result | Evidence |
| --- | --- | --- |
| `make bootstrap` | PASS | Dependencies resolved; 21 newer incompatible package versions were informational only |
| `make analyze` | PASS | `ianvs_pty`, `ianvs_terminal` and `example` all reported `No issues found` with fatal infos enabled |
| `make test` | PASS | Root docs, PTY, terminal package and example unit/widget suites all passed; existing skipped coverage remained explicit |
| `make verify` | PASS | Rust, Dart/Flutter, docs, benchmark, macOS smoke 4/4, real PTY 46/46 and Runner XCTest 16/16 passed |
| `./tools/vttest_gui_nightly.sh --release-gate` | PASS | Supplemental real GUI + PTY + Homebrew `vttest` gate passed after T-303 removed two test-harness races |

Focused Rust resize/reflow tests and all three focused real PTY compatibility tests also passed on
2026-07-21. The CI benchmark evidence directory was
`build/bench-results-ci/20260720T170816Z`.

## Result

- Added the six-layer compatibility matrix, test inventory, compatibility known issues and manual
  verification runbook.
- Added deterministic real shell and alternate-screen TUI app-level fixtures; retained the existing
  Unicode/width/cursor fixture as explicit baseline evidence.
- Added cumulative resize replay count/byte/microsecond diagnostics plus a truncated-replay skip
  counter, with passing untruncated and truncated boundary tests.
- Homebrew `vttest` 20251205 was installed after the required baseline closed. The supplemental real
  GUI gate now passes on this host; T-303 records the deterministic PTY and viewport synchronization
  fixes and the final summary path.
- `flutter test -d macos` continued to print the known non-fatal
  `Failed to foreground app; open returned 1` message while all product assertions passed.
- Iteration 02 frame-pipeline refactoring and Iteration 03 recording/replay were not started.

## Acceptance Audit

| Iteration 01 acceptance item | Status | Evidence |
| --- | --- | --- |
| Six-layer capability matrix with source/test evidence | PASS | `docs/compatibility/CAPABILITY_MATRIX.md` |
| At least one real shell E2E | PASS | Named macOS real PTY shell lifecycle test |
| At least one alternate-screen TUI E2E | PASS | Named deterministic alternate-screen macOS real PTY test |
| At least one resize/reflow test | PASS | Untruncated replay and truncated boundary Rust tests |
| Unicode width/cursor fixture | PASS | OSC 1337 UnicodeVersion macOS real PTY test |
| Known issues and manual steps | PASS | `docs/compatibility/KNOWN_ISSUES.md` and `MANUAL_VERIFICATION.md` |
| Accurate required command results | PASS | All four Make targets recorded above |
| No large feature/UI expansion | PASS | Only tests, diagnostics and evidence docs were added for this iteration |

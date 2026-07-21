# T-299 OSC 72 Test Format Gate

## Goal

Restore the repository-wide Dart format gate for the existing OSC 72 drag/drop
controller test.

## Scope

- Format `example/test/shell/osc72_drag_drop_controller_test.dart` with the
  workspace Dart formatter.
- Re-run the repository format check.

## Non-goals

- Do not change OSC 72 behavior or test assertions.
- Do not refactor the controller or expand drag/drop coverage.
- Do not change production code.

## Files In Scope

- `example/test/shell/osc72_drag_drop_controller_test.dart`
- `docs/tasks/verification-gates/T-299-osc72-test-format-gate.md`
- `docs/tasks/README.md`

## Functional Acceptance

- The repository format check no longer reports the OSC 72 test as changed.
- The formatting-only diff does not alter test behavior or assertions.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
make format-check
```

## Manual QA

Not applicable: this task is a formatter-only test-source correction.

## Done When

- The file is formatter-clean.
- `make format-check` passes.
- No production file or test assertion changes.

## Risks / Follow-ups

- The formatter version is supplied by the pinned Flutter/Dart toolchain in CI;
  future toolchain changes may produce new mechanical diffs.

## Result

- Formatted the existing OSC 72 test without changing its assertions.
- `make format-check` passed across 376 Dart files with zero changes.
- The final `make verify` run passed, including the OSC 72 unit and real PTY
  coverage.

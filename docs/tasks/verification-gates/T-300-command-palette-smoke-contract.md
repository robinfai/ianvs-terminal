# T-300 Command Palette Smoke Contract

## Goal

Realign the macOS command-palette integration smoke with the current command
menu section and stable action key.

## Scope

- Replace the removed `Top actions` integration assertion with the current
  `Command palette` and `Quick actions` contract.
- Locate the Defaults action through its stable widget key before exercising
  the existing open/close flow.
- Re-run the focused macOS integration test and repository verification.

## Non-goals

- Do not change command-palette product UI or labels.
- Do not change keyboard routing or Defaults behavior.
- Do not weaken or skip the macOS integration gate.

## Files In Scope

- `example/integration_test/ianvs_terminal_smoke_test.dart`
- `docs/tasks/verification-gates/T-300-command-palette-smoke-contract.md`
- `docs/tasks/README.md`

## Functional Acceptance

- Command-Shift-P opens the current command palette.
- The `Quick actions` section and Defaults action are present.
- Opening and closing Defaults returns to a live terminal viewport.
- The integration test no longer relies on the removed `Top actions` label.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd example
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

```bash
make verify
```

## Manual QA

Not required for the test-only correction. The macOS integration test drives
the actual app target and verifies the complete flow.

## Done When

- The focused macOS smoke passes all four tests.
- Repository verification passes beyond this gate.
- No production code changes.

## Risks / Follow-ups

- User-visible section labels remain intentionally asserted as part of the
  integration contract; future deliberate copy changes must update this smoke
  in the same iteration.

## Result

- Updated the smoke to assert the current `Command palette` / `Quick actions`
  contract and select Defaults through `shell-command-defaults`.
- The focused macOS smoke passed all 4 tests.
- The final `make verify` run passed the same 4-test desktop smoke and all
  downstream build/XCTest gates.

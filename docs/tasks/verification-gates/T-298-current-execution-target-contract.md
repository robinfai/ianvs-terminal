# T-298 Current Execution Target Contract

## Goal

Calibrate the live execution direction against the current repository and make
that direction automatically verifiable.

## Scope

- Compare the roadmap and historical verification claims with current code,
  tests, CI, and known platform limits.
- Publish a human-readable current target and a machine-readable evidence
  manifest.
- Add automated checks for manifest evidence and authoritative documentation
  links.
- Update roadmap and documentation navigation wording to the calibrated state.

## Non-goals

- Do not add terminal, workspace, profile, OSC, or cross-platform features.
- Do not claim that historical verification output proves the current commit.
- Do not claim Linux or Windows desktop support from package-only CI tests.
- Do not execute GUI manual acceptance in this documentation-contract task.

## Files In Scope

- `docs/CURRENT_EXECUTION_TARGET.md`
- `docs/CURRENT_EXECUTION_TARGETS.json`
- `docs/ROADMAP.md`
- `docs/README.md`
- `docs/TESTING.md`
- `docs/tasks/README.md`
- `docs/tasks/verification-gates/T-298-current-execution-target-contract.md`
- `README.md`
- `test/docs_contract_test.dart`

## Functional Acceptance

- A contributor can identify one active execution target and its exit criteria.
- Historical, active, blocked, and deferred lanes are explicitly separated.
- The target cites actual implementation and test files rather than only plans.
- CI fails when a manifest evidence path/token or authoritative local Markdown
  link drifts.
- Cross-platform and deferred product scope cannot be mistaken for active work.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
dart format --output=none --set-exit-if-changed test/docs_contract_test.dart
dart analyze --fatal-infos test/docs_contract_test.dart
dart test test/docs_contract_test.dart
```

## Manual QA

Read `docs/CURRENT_EXECUTION_TARGET.md`, `docs/CURRENT_EXECUTION_TARGETS.json`,
and the first section of `docs/ROADMAP.md` together. Confirm that they name the
same active target and do not describe M1-M5 as the current unstarted sequence.

## Done When

- The calibrated direction is documented in both human- and machine-readable
  form.
- Automated contract tests pass and are already part of the repository verify
  script.
- Documentation navigation points to the current target.

## Risks / Follow-ups

- The active `local-workspace-stability` lane now has fresh full macOS
  verification. Remaining GUI-only behavior must still keep current manual
  evidence or an explicit blocker as the lane evolves.
- Current historical task records predate some July implementation work. New
  behavior changes should resume one-task/one-goal records instead of trying to
  retroactively rewrite all history.

## Result

- Published the human-readable target and machine-readable evidence manifest.
- Added evidence-token and authoritative local-link contracts; all 10 docs
  contract tests passed.
- `make format-check` passed across 376 Dart files.
- The final `make verify` run passed through native, Dart/Flutter, benchmark,
  real PTY, macOS smoke, desktop build, and Runner XCTest gates.

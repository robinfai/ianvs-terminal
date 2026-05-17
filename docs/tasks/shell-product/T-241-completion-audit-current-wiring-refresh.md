# T-241 Completion audit current wiring refresh

## Goal

Refresh the local terminal completion audit and real wiring backlog so they describe the current wired-but-unverified state instead of the older foundation-only state.

## Scope

- Update `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md`.
- Update `docs/LOCAL_TERMINAL_REAL_WIRING_BACKLOG_2026-05.md`.
- Add the completion audit checklist to the main docs navigation.
- Keep verification blockers explicit.

## Non-goals

- Superseded by final verification closure.
- Do not mark any gate verified without command or manual evidence.
- Do not run validation commands as part of this documentation refresh.

## Acceptance

- P1-P5 rows distinguish `Wired`, `Foundation/Wired`, and `Not closed`.
- The audit records that T-164 through T-168 are implemented but blocked by verification.
- The real wiring backlog records that T-169 remains the closure blocker.
- Docs navigation points to the audit checklist.

## Verification Commands

- Documentation review only.
- Final closure still requires `dart format`, `flutter analyze`, focused `flutter test` commands, broader tests, and manual/integration gates.

## Result

Updated the completion audit checklist, real wiring backlog, docs navigation, and task index to match the current wired-but-unverified implementation state.

## Verification

Not run. This task only refreshes status documentation and does not provide verification evidence.

## Remaining Risks

- The status remains based on code/task evidence, not executed validation.
- Any analyzer, test, runtime, or manual failure can reopen implementation tasks.

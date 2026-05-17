# T-240 Competitor coverage matrix status refresh

## Goal

Refresh the competitor-derived local terminal coverage matrix so it reflects the current implementation evidence instead of the older foundation-only state.

## Scope

- Update `docs/LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md`.
- Mark core P1-P5 capabilities as `Wired` or `Foundation/Wired` where current task and code evidence support that status.
- Keep verification gaps explicit and separate from wiring coverage.
- Add the matrix to the main docs navigation.

## Non-goals

- Do not claim the overall local terminal plan is complete.
- Do not mark any capability `Verified`.
- Do not add new competitor-derived scope beyond the existing P0-P5 plan.

## Acceptance

- The matrix answers whether the absorbable competitor feature surface is covered by plans/tasks/wiring.
- Remaining gaps focus on verification and advanced follow-up, not stale generic production-wiring gaps.
- Navigation points future readers to the matrix.

## Verification Commands

- Documentation review only.
- Full closure still requires `flutter analyze`, `flutter test`, and the local terminal manual matrix.

## Result

Updated the competitor coverage matrix to reflect broad core production wiring, kept verification and advanced capability gaps explicit, and linked the matrix from `docs/README.md`.

## Verification

Not run. This task records a documentation/status refresh only.

## Remaining Risks

- Matrix statuses are based on current task/code evidence and still need validation through analysis, tests, and manual checks.
- Advanced P5 capabilities remain planned/foundation-level until split into explicit UI/runtime tasks.

# T-264 Missing required backlog diagnostics

## Goal

Surface missing required real-wiring backlog task ids in summary and diagnostics UI models after the final completion evidence report started requiring T-164 through T-169.

## Scope

- Update `example/lib/features/shell/local_terminal_completion_summary.dart`.
- Update `example/lib/features/shell/local_terminal_completion_diagnostics_view_model.dart`.
- Update corresponding summary and diagnostics view model tests.

## Non-goals

- Do not mark any backlog task verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- Missing required backlog task ids appear in plain-text summaries.
- Missing required backlog task ids appear as blocker diagnostics sections.
- Partial backlog evidence cannot fail silently with no visible backlog reason.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_summary_test.dart example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart`

## Result

Added missing required backlog diagnostics to summary and diagnostics view model surfaces.

## Verification

Not run. The tests were updated but not executed in this session.

## Remaining Risks

- The updated tests may require formatting.
- Real closure still requires executed and recorded verification evidence.

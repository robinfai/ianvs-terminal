# T-271 Missing backlog diagnostics surfaces

## Goal

Keep missing required real-wiring backlog tasks visible through the final
diagnostics bundle, presentation model, and Flutter panel surfaces.

## Scope

- Add bundle-level regression coverage for missing required backlog tasks.
- Add presentation-level regression coverage for required backlog blocker
  counts when backlog tasks are absent from evidence.
- Add panel-level widget coverage for the visible missing backlog section.
- Update documentation indexes and verification target notes.

## Non-goals

- Do not change production runtime behavior.
- Do not mark missing backlog tasks verified.
- Do not run tests, static analysis, formatting, or manual verification.

## Acceptance

- Diagnostics bundle output includes missing required backlog tasks.
- Presentation blocked backlog count includes missing required backlog tasks.
- Panel rendering shows the missing backlog section and affected task ids.

## Verification Commands

- `flutter test example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart example/test/shell/local_terminal_completion_diagnostics_panel_test.dart`

## Result

Added focused regression coverage for missing required backlog propagation
through diagnostics bundle, presentation, and panel layers.

## Verification

Not run. The tests were updated but not executed in this session.

## Remaining Risks

- The new tests may require formatting.
- Final objective closure still requires the full T-169 verification command and
  manual/integration evidence set.

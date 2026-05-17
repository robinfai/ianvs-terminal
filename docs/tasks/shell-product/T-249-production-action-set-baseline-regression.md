# T-249 Production action set baseline regression

## Goal

Add regression coverage for the default production action set so the current P1 required baseline cannot silently drop wired actions or alias mappings.

## Scope

- Update `example/test/shell/shell_action_production_action_set_test.dart`.
- Assert `ShellActionProductionActionSet.defaults()` has no unknown required or optional names.
- Assert the default required names include the current T-230 P1 action baseline.
- Assert important alias names resolve to their real `TerminalActionId` values.

## Non-goals

- Do not mark P1 verified.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The default action set protects the current P1 production baseline from accidental removal.
- Alias coverage protects `closeTab`, `searchScrollback`, `toggleCommandPalette`, `toggleHotkeyWindow`, and resize-pane aliases.

## Verification Commands

- `flutter test example/test/shell/shell_action_production_action_set_test.dart`

## Result

Added a focused regression test for the default production action set baseline and key action-name aliases.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Runtime behavior still requires the full verification plan.

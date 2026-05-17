# T-158 Local terminal visual production callbacks

## Milestone

P5 - Visual and advanced local features

## Intent

Define the production callback contract that will let theme, layout template,
scrollback export, graphics policy, timestamps, command pane, and scrollback
editor behavior wire into the P5 foundation.

## Scope

- Add visual production operation ids for theme, layout, export, graphics, and
  advanced local UI behavior.
- Add a binding context and structured binding result.
- Add typed nullable callbacks for supported P5 operations.
- Add a wiring object that can run registered callbacks.
- Report missing required visual callbacks before P5 can close.

## Deliverables

- `example/lib/features/visual/local_terminal_visual_production_callbacks.dart`
- `example/test/visual/local_terminal_visual_production_callbacks_test.dart`

## Acceptance criteria

- Registered visual callbacks receive context and return structured results.
- Missing required operations are visible through the wiring object.
- Unsupported operations return a failed result instead of throwing.

## Status

Foundation implemented. Not verified in this session.

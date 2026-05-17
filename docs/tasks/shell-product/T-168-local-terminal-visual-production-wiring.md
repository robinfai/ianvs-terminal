# T-168 Local terminal visual production wiring

## Milestone

P5 - Visual and advanced local features

## Intent

Populate visual production callbacks from real theme, layout template, export,
graphics policy, and advanced visual UI behavior.

## Scope

- Wire theme picker, apply, import, and export callbacks.
- Wire layout template apply, save, and export callbacks.
- Wire scrollback and command-output export callbacks.
- Wire pane visual and split divider policy callbacks.
- Wire graphics storage, timestamps, command pane, and scrollback editor
  callbacks where in scope.
- Convert visual wiring into a P5 domain summary.

## Deliverables

- `LocalTerminalVisualProductionWiring` populated from real visual/export
  methods.
- P5 `LocalTerminalDomainWiringSummary`.
- Updated completion audit checklist evidence for P5.

## Acceptance criteria

- Required visual operations have registered callbacks.
- Advanced optional operations remain explicitly blocked or verified.
- Exports use real terminal data and configured destination policy.
- Required P5 tests and static analysis pass before closure.

## Status

Pending.

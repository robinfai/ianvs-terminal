# T-166 Shell productivity production wiring

## Milestone

P3 - Shell productivity

## Intent

Populate shell productivity production callbacks from real prompt navigation,
command output, recent directory, search, read-only, and scrollback behavior.

## Scope

- Wire prompt navigation callbacks.
- Wire command output select/copy/save callbacks.
- Wire recent directory opening.
- Wire scrollback search and match navigation.
- Wire read-only and clear scrollback behavior.
- Convert productivity wiring into a P3 domain summary.

## Deliverables

- `ShellProductivityProductionWiring` populated from real productivity methods.
- P3 `LocalTerminalDomainWiringSummary`.
- Updated completion audit checklist evidence for P3.

## Acceptance criteria

- Required productivity operations have registered callbacks.
- Shell integration disabled states produce visible unavailable behavior.
- Search/output actions preserve terminal focus, selection, and scrollback state.
- Required P3 tests and static analysis pass before closure.

## Status

Pending.

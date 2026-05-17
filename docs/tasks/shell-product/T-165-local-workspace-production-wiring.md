# T-165 Local workspace production wiring

## Milestone

P2 - Local workspace

## Intent

Populate local workspace production callbacks from real tab, pane, split, focus,
resize, swap, zoom, and layout behavior.

## Scope

- Wire tab lifecycle callbacks.
- Wire pane split, close, reopen, focus, resize, swap, and zoom callbacks.
- Wire same-cwd creation behavior.
- Wire local-only layout save/restore behavior.
- Convert workspace wiring into a P2 domain summary.

## Deliverables

- `LocalWorkspaceProductionWiring` populated from real shell workspace methods.
- P2 `LocalTerminalDomainWiringSummary`.
- Updated completion audit checklist evidence for P2.

## Acceptance criteria

- Required workspace operations have registered callbacks.
- Missing required workspace operations are empty.
- Layout restore does not introduce SSH, remote, serial, or SFTP state.
- Required P2 tests and static analysis pass before closure.

## Status

Pending.

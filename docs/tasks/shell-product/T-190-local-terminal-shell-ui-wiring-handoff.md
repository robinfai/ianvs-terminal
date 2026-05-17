# T-190 Local terminal Shell UI wiring handoff

## Milestone

P0-P5 production wiring integration

## Intent

Document the stable UI-facing entry points for the next `ShellScreen` production
wiring pass so future implementation uses the bundle/facade/snapshot surfaces
instead of depending on low-level manifest internals.

## Scope

- Identify preferred entry points for production wiring, diagnostics, command
  menu rendering, disabled reasons, closure evidence, and verification gates.
- Define the production wiring sequence.
- Capture rules for `ShellScreen` integration.
- Preserve the fact that real production callbacks and verification are still
  pending.

## Deliverables

- `docs/LOCAL_TERMINAL_SHELL_UI_WIRING_HANDOFF_2026-05.md`

## Acceptance criteria

- The handoff points future UI code to stable high-level surfaces.
- The handoff warns against fake action ids and boolean-only closure.
- The handoff explicitly states that real production wiring remains pending.

## Status

Created. The handoff documents the next implementation pass; it does not close
the work.

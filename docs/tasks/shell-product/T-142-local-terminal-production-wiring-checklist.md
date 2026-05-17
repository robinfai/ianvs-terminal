# T-142 Local terminal production wiring checklist

## Milestone

P1-P5 cross-milestone execution control

## Intent

Prevent foundation artifacts from being mistaken for finished product behavior
by defining the production wiring gates that must close before the local
terminal plan can be called complete.

## Scope

- Map P1-P5 foundation layers to their production targets.
- Identify the evidence required for `ShellScreen`, `SessionController`,
  terminal controller, policy, notification, visual, and workspace wiring.
- Capture the minimum verification gates needed before completion.

## Deliverables

- `docs/LOCAL_TERMINAL_PRODUCTION_WIRING_CHECKLIST_2026-05.md`

## Acceptance criteria

- The checklist distinguishes foundation, production wiring, and verification.
- Every P1-P5 domain has at least one concrete production target.
- The checklist explicitly preserves the local-only scope and verification
  requirements.

## Status

Created. The checklist documents remaining work; it does not close the work.

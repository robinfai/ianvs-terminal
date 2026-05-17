# T-151 Shell action production wiring report

## Milestone

P1 - Local terminal action foundation

## Intent

Expose production action wiring readiness and diagnostics as a stable report that
can be rendered in a developer surface or used by a completion audit.

## Scope

- Build a report from `ShellActionProductionWiringState`.
- Split blocking and advisory diagnostics.
- Preserve diagnostic kind, severity, title, description, action id, and action
  name.
- Export the report as JSON-compatible data.

## Deliverables

- `example/lib/features/shell/shell_action_production_wiring_report.dart`
- `example/test/shell/shell_action_production_wiring_report_test.dart`

## Acceptance criteria

- Ready wiring produces a clean report with no blocking items.
- Missing required callbacks appear as blocking report items.
- Report output is JSON-compatible for diagnostics or audit tooling.

## Status

Foundation implemented. Not verified in this session.

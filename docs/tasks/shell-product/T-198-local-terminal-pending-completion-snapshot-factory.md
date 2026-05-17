# T-198 Local terminal pending completion snapshot factory

## Milestone

P0-P5 cross-milestone execution control

## Intent

Build the default blocked shell UI wiring snapshot from the verification command
plan records so pending completion diagnostics preserve command/manual gate
metadata instead of using anonymous pending gates.

## Scope

- Add a pending completion snapshot factory.
- Initialize verification evidence from
  `LocalTerminalVerificationPlanRecords.defaultPending()`.
- Preserve optional P0 boundary and P0 verification inputs.
- Export the factory through the Shell UI wiring export surface.

## Deliverables

- `example/lib/features/shell/local_terminal_pending_completion_snapshot_factory.dart`
- `example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart`
- Update `local_terminal_shell_ui_wiring_exports.dart`.

## Acceptance criteria

- Default snapshot remains blocked.
- Verification evidence covers every required gate.
- Pending verification evidence preserves command-plan metadata.

## Status

Foundation implemented. Not verified in this session.

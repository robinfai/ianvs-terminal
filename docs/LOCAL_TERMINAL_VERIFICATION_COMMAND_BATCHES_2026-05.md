# Local Terminal Verification Command Batches

Date: 2026-05-16

Purpose: provide copy-ready command batches for the verification sequence that
must run before T-169 and the overall local terminal objective can close.

This document does not run commands and does not record passing evidence.
Results must be written into
`LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md`.
Failed batches should also be recorded in
`LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md`.
Use `LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md` for the full
execution order and stop conditions.

Optional local helper:

```sh
bash tools/local_terminal_verification_batches.sh list
bash tools/local_terminal_verification_batches.sh print all-automated
bash tools/local_terminal_verification_batches.sh print completion
bash tools/local_terminal_verification_batches.sh run completion
```

The helper still does not update the evidence ledger; record outputs manually.
Helper side effects are indexed in
`LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md`.
Machine-readable batch-to-gate metadata is available in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`.
Manifest maintenance rules are documented in
`LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md`.

Optional capture helper for future explicit runs:

```sh
bash tools/local_terminal_verification_capture.sh run completion
```

Captured logs are written under `build/local-terminal-verification/` and still
must be summarized in the evidence ledger. Future captured runs also create a
`ledger-entry.md` template beside `output.log`; review it before copying any
status into the canonical ledger.

## Batch 0: Formatting

```sh
dart format example/lib example/test
```

Record against:

- `LocalTerminalVerificationGate.formatting`

## Batch 1: Static Analysis

```sh
flutter analyze
```

Record against:

- `LocalTerminalVerificationGate.staticAnalysis`

## Batch 2: Completion Evidence And Diagnostics

```sh
flutter test \
  example/test/shell/local_terminal_current_completion_state_test.dart \
  example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart \
  example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart \
  example/test/shell/local_terminal_shell_ui_wiring_facade_test.dart \
  example/test/shell/local_terminal_shell_ui_wiring_snapshot_test.dart \
  example/test/shell/local_terminal_completion_evidence_report_test.dart \
  example/test/shell/local_terminal_completion_summary_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_view_model_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_actions_test.dart \
  example/test/shell/local_terminal_completion_menu_model_test.dart \
  example/test/shell/local_terminal_completion_command_menu_adapter_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_bundle_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_presentation_test.dart \
  example/test/shell/local_terminal_completion_diagnostics_panel_test.dart \
  example/test/shell/local_terminal_completion_shell_command_menu_diagnostics_test.dart
```

Record against:

- `LocalTerminalVerificationGate.unitTests`
- `LocalTerminalVerificationGate.widgetTests` for the diagnostics panel portion

If this batch is split, record each command separately in the evidence ledger
and aggregate only after all required files pass.

## Batch 3: P1 Action Wiring

```sh
flutter test \
  example/test/shell/shell_action_production_action_set_test.dart \
  example/test/shell/shell_action_production_callbacks_test.dart \
  example/test/shell/shell_action_production_wiring_state_test.dart \
  example/test/shell/shell_action_production_executor_test.dart \
  example/test/shell/shell_action_production_runtime_adapter_test.dart \
  example/test/shell/shell_action_production_wiring_report_test.dart \
  example/test/shell/shell_action_production_audit_snapshot_test.dart \
  example/test/shell/shell_action_production_closure_manifest_test.dart \
  example/test/shell/local_terminal_action_domain_router_test.dart \
  example/test/shell/local_terminal_domain_wiring_summary_test.dart
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 4: Cross-Milestone Production Wiring

```sh
flutter test \
  example/test/shell/local_terminal_production_wiring_bundle_test.dart \
  example/test/shell/local_terminal_production_wiring_manifest_builder_test.dart
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 5: P2 Workspace

```sh
flutter test example/test/workspace
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 6: P3 Productivity

```sh
flutter test example/test/productivity
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 7: P4 Policy

```sh
flutter test example/test/policies
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 8: P5 Visual

```sh
flutter test example/test/visual
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 9: Verification Evidence

```sh
flutter test example/test/shell/local_terminal_verification_*test.dart
```

Record against:

- `LocalTerminalVerificationGate.unitTests`

## Batch 10: Broader Test Scope

Use the stable broader project command after the focused batches above have
passed:

```sh
flutter test example/test
```

Record against:

- `LocalTerminalVerificationGate.unitTests`
- `LocalTerminalVerificationGate.widgetTests` if the broader suite includes
  widget tests

The repository root does not contain a top-level `test` directory, so do not run
bare `flutter test` from the workspace root for this gate.

If the full `example/test` suite is not stable, record the chosen broader scope,
the reason for the chosen boundary, and any remaining blocker in the evidence
ledger.

## Batch 11: Integration Or Smoke Test

Default command:

```sh
bash tools/local_terminal_verification_capture.sh run integration
```

The batch builds the debug native core, runs from the `example` package so
desktop plugins are registered, sets `IANVS_CORE_LIB`, and executes the app
smoke path plus the macOS real PTY acceptance path sequentially. Record the
exact command, exit status, and key local shell lifecycle output in the ledger.

Optional external-binary supplement, only when `vttest` is installed or
`IANVS_VTTEST_BIN` points to it:

```sh
IANVS_VTTEST_BIN=/path/to/vttest flutter test -d macos example/integration_test/vttest_gui_test.dart
```

Do not require the optional `vttest` supplement for default closure unless the
objective scope is expanded to VT conformance verification.

Record against:

- `LocalTerminalVerificationGate.integrationTests`

## Batch 12: Manual Gates

Use `LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`.

Record against:

- `LocalTerminalVerificationGate.manualLocalShellSmoke`
- `LocalTerminalVerificationGate.manualPasteFocusSafety`
- `LocalTerminalVerificationGate.manualMultipaneBehavior`
- `LocalTerminalVerificationGate.manualNotificationBehavior`
- `LocalTerminalVerificationGate.manualHotkeyWindowFailurePath`

## Recording Rule

For every batch:

1. Record the exact command or manual scenario.
2. Record date/time, working directory, platform, and exit status or observed
   result.
3. Record key output lines, failing test names, or manual blockers.
4. Convert the result into `LocalTerminalVerificationGateRecord` only after it
   satisfies the gate rule.
5. Do not aggregate a gate to `passed` if any required batch in that gate failed,
   was skipped, or was not attempted.
6. If a batch fails, stop and add a failure row to the triage log before fixing
   or continuing.

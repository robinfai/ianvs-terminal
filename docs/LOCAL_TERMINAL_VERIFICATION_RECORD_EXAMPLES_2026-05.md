# Local Terminal Verification Record Examples

Date: 2026-05-16

Purpose: show exactly how filled verification ledger rows should be converted
into `LocalTerminalVerificationGateRecord` values and then into final T-169
verification evidence.

Use `LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md` for the
copy-ready command groups that should produce the ledger rows.

These examples are illustrative only. Do not copy their `passed` statuses into
real evidence unless the matching command or manual gate has actually passed.

## Starting Point

Always start from the default pending gate set:

```dart
final recorder = LocalTerminalVerificationPlanRecords
    .defaultPending()
    .toRecorder();
```

This preserves every required gate as pending before real results are applied.

## Formatting Record Example

Use only after the expanded `dart format` gate exits successfully after the
final edits:

```dart
const formattingRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.formatting,
  command:
      'dart format example/lib example/test example/integration_test example/test_driver example/tool packages/ianvs_terminal/lib packages/ianvs_terminal/test packages/ianvs_pty/lib packages/ianvs_pty/test',
  output: [
    'Formatted app, integration/test-driver/tool, and local package Dart files.',
    'Exit status: 0',
  ],
);
```

If formatting fails:

```dart
const formattingRecord = LocalTerminalVerificationGateRecord.failed(
  gate: LocalTerminalVerificationGate.formatting,
  command:
      'dart format example/lib example/test example/integration_test example/test_driver example/tool packages/ianvs_terminal/lib packages/ianvs_terminal/test packages/ianvs_pty/lib packages/ianvs_pty/test',
  output: [
    'Formatter failed.',
    'Exit status: non-zero',
  ],
);
```

## Static Analysis Record Example

Use only after `flutter analyze` exits successfully with no blocking analyzer
issues:

```dart
const staticAnalysisRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.staticAnalysis,
  command: 'flutter analyze',
  output: [
    'No issues found.',
    'Exit status: 0',
  ],
);
```

## Focused Test Record Example

Use the `unitTests` gate for the focused completion, P1, P2-P5, verification,
terminal package, and broader unit-test scope after all required unit-oriented
commands pass:

```dart
const unitTestRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.unitTests,
  command: 'focused flutter test commands from LOCAL_TERMINAL_TEST_TARGETS_2026-05.md',
  output: [
    'Completion evidence tests passed.',
    'P1 action wiring tests passed.',
    'P2-P5 domain tests passed.',
    'Verification evidence tests passed.',
    'Terminal package tests passed.',
    'Broader unit scope passed.',
  ],
);
```

If any focused command fails, record `failed` with the failing command and test
names instead of aggregating to passed.

## Widget Test Record Example

Use only after the relevant diagnostics/widget scope passes:

```dart
const widgetTestRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.widgetTests,
  command: 'flutter test example/test/shell/local_terminal_completion_diagnostics_panel_test.dart ...',
  output: [
    'Completion diagnostics panel tests passed.',
    'Command-menu diagnostics tests passed.',
  ],
);
```

## Integration Test Record Example

Use only after the project has an executed local-terminal integration or smoke
target:

```dart
const integrationRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.integrationTests,
  command:
      'bash tools/local_terminal_verification_capture.sh run integration',
  output: [
    'App smoke and real PTY acceptance tests passed.',
  ],
  notes: [
    'Record the exact command, platform, and app build in the evidence ledger.',
  ],
);
```

If the integration command cannot be executed in the current environment, record
`skipped` or leave the gate pending. Either state remains a blocker.

## Manual Gate Record Examples

Manual gates should include observation notes from
`LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md`.

```dart
const localShellSmokeRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.manualLocalShellSmoke,
  notes: [
    'Platform: macOS.',
    'Shell: /bin/zsh.',
    'New tab, split, command output, and close/focus fallback observed.',
  ],
);
```

```dart
const pasteFocusRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.manualPasteFocusSafety,
  notes: [
    'Single-line paste worked through policy.',
    'Multiline or large paste confirmation behavior observed.',
    'Read-only blocked paste/send-text.',
    'Focus remained stable.',
  ],
);
```

```dart
const multipaneRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.manualMultipaneBehavior,
  notes: [
    'Split, focus, resize, swap, zoom, close, and empty-state behavior observed.',
  ],
);
```

```dart
const notificationRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.manualNotificationBehavior,
  notes: [
    'Bell, command-finished, activity, focus policy, and target policy observed.',
  ],
);
```

```dart
const hotkeyWindowRecord = LocalTerminalVerificationGateRecord.passed(
  gate: LocalTerminalVerificationGate.manualHotkeyWindowFailurePath,
  notes: [
    'Toggle path invoked.',
    'Success or visible platform/permission failure observed.',
    'No silent no-op observed.',
  ],
);
```

## Batch Recording Example

After real records are collected:

```dart
final finalRecorder = recorder.recordAll(const [
  formattingRecord,
  staticAnalysisRecord,
  unitTestRecord,
  widgetTestRecord,
  integrationRecord,
  localShellSmokeRecord,
  pasteFocusRecord,
  multipaneRecord,
  notificationRecord,
  hotkeyWindowRecord,
]);

final verificationEvidence = finalRecorder.evidence;
final t169BacklogEvidence = finalRecorder.toBacklogEvidence();
```

The objective can move toward closure only when:

```dart
verificationEvidence.canClose == true
```

and T-164 through T-168 have also been verified from real production wiring
evidence.

## Failed Or Skipped Gate Example

Failed and skipped gates must remain blockers:

```dart
const failedAnalysisRecord = LocalTerminalVerificationGateRecord.failed(
  gate: LocalTerminalVerificationGate.staticAnalysis,
  command: 'flutter analyze',
  output: [
    'Analyzer reported blocking issues.',
  ],
);

const skippedIntegrationRecord = LocalTerminalVerificationGateRecord(
  gate: LocalTerminalVerificationGate.integrationTests,
  status: LocalTerminalVerificationStatus.skipped,
  notes: [
    'The default integration command could not be executed in this environment.',
    'This remains a blocker unless scope changes.',
  ],
);
```

Do not remove required gates to force `canClose`.

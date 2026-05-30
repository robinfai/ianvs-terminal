import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';
import 'package:app/features/shell/local_terminal_verification_plan_records.dart';

void main() {
  test('default plan records cover every default required gate', () {
    final plan = LocalTerminalVerificationPlanRecords.defaultPending();

    expect(
      plan.records.map((record) => record.gate).toSet(),
      LocalTerminalVerificationEvidence.defaultRequiredGates.toSet(),
    );
    expect(plan.records.map((record) => record.status).toSet(), {
      LocalTerminalVerificationStatus.pending,
    });
  });

  test('default plan records create a blocked recorder', () {
    final recorder = LocalTerminalVerificationPlanRecords.defaultPending()
        .toRecorder();

    expect(recorder.evidence.canClose, isFalse);
    expect(
      recorder.evidence.blockingItems,
      hasLength(LocalTerminalVerificationEvidence.defaultRequiredGates.length),
    );
  });

  test('default plan records expose current verification commands', () {
    final plan = LocalTerminalVerificationPlanRecords.defaultPending();
    final commands = {
      for (final record in plan.records) record.gate: record.command,
    };

    expect(
      commands[LocalTerminalVerificationGate.formatting],
      contains('packages/ianvs_terminal/lib'),
    );
    expect(
      commands[LocalTerminalVerificationGate.unitTests],
      'bash tools/local_terminal_verification_capture.sh run all-automated',
    );
    expect(
      commands[LocalTerminalVerificationGate.widgetTests],
      'bash tools/local_terminal_verification_capture.sh run broader',
    );
    expect(
      commands[LocalTerminalVerificationGate.integrationTests],
      'bash tools/local_terminal_verification_capture.sh run integration',
    );
  });

  test('latest passed records close every required verification gate', () {
    final plan = LocalTerminalVerificationPlanRecords.latestPassed();
    final recorder = plan.toRecorder();

    expect(
      plan.records.map((record) => record.gate).toSet(),
      LocalTerminalVerificationEvidence.defaultRequiredGates.toSet(),
    );
    expect(plan.records.map((record) => record.status).toSet(), {
      LocalTerminalVerificationStatus.passed,
    });
    expect(recorder.evidence.canClose, isTrue);
    expect(recorder.evidence.blockingItems, isEmpty);
    expect(
      recorder.toBacklogEvidence().status,
      LocalTerminalCompletionBacklogStatus.verified,
    );
    expect(
      plan.records
          .singleWhere(
            (record) => record.gate == LocalTerminalVerificationGate.unitTests,
          )
          .output
          .join('\n'),
      contains('terminal package tests passed'),
    );
    expect(
      plan.records
          .singleWhere(
            (record) =>
                record.gate == LocalTerminalVerificationGate.integrationTests,
          )
          .output
          .join('\n'),
      contains('20260516T171644Z-integration'),
    );
  });
}

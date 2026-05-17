import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_real_wiring_backlog_evidence.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';
import 'package:app/features/shell/local_terminal_verification_evidence_recorder.dart';

void main() {
  test('starts with default required gates pending', () {
    final recorder = LocalTerminalVerificationEvidenceRecorder.pending(
      notes: const ['awaiting verification'],
    );

    expect(recorder.evidence.canClose, isFalse);
    expect(
      recorder.evidence.requiredItems,
      hasLength(LocalTerminalVerificationEvidence.defaultRequiredGates.length),
    );
  });

  test('records passed command evidence for an existing gate', () {
    final recorder = LocalTerminalVerificationEvidenceRecorder.pending()
        .recordPassed(
          gate: LocalTerminalVerificationGate.unitTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'all-automated',
          output: const ['All tests passed'],
        );

    final item = recorder.evidence.requiredItems.singleWhere(
      (entry) => entry.gate == LocalTerminalVerificationGate.unitTests,
    );

    expect(item.status, LocalTerminalVerificationStatus.passed);
    expect(
      item.command,
      'bash tools/local_terminal_verification_capture.sh run all-automated',
    );
    expect(item.evidence, ['All tests passed']);
  });

  test('failed required gate blocks T-169 backlog evidence', () {
    final recorder = LocalTerminalVerificationEvidenceRecorder.pending()
        .recordFailed(
          gate: LocalTerminalVerificationGate.staticAnalysis,
          command: 'flutter analyze',
          output: const ['1 issue found'],
        );

    final backlogEvidence = recorder.toBacklogEvidence();

    expect(
      backlogEvidence.task,
      LocalTerminalRealWiringTask.localTerminalVerificationAndClosure,
    );
    expect(
      backlogEvidence.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogEvidence.blockers,
      contains('Verification gate staticAnalysis is failed.'),
    );
  });

  test('records multiple gate results in a batch', () {
    final recorder = LocalTerminalVerificationEvidenceRecorder.pending()
        .recordAll(const [
          LocalTerminalVerificationGateRecord.passed(
            gate: LocalTerminalVerificationGate.unitTests,
            command:
                'bash tools/local_terminal_verification_capture.sh run '
                'all-automated',
            output: ['unit tests passed'],
          ),
          LocalTerminalVerificationGateRecord.failed(
            gate: LocalTerminalVerificationGate.widgetTests,
            command:
                'bash tools/local_terminal_verification_capture.sh run '
                'broader',
            output: ['widget failure'],
          ),
        ]);

    final unitTests = recorder.evidence.requiredItems.singleWhere(
      (entry) => entry.gate == LocalTerminalVerificationGate.unitTests,
    );
    final widgetTests = recorder.evidence.requiredItems.singleWhere(
      (entry) => entry.gate == LocalTerminalVerificationGate.widgetTests,
    );

    expect(unitTests.status, LocalTerminalVerificationStatus.passed);
    expect(widgetTests.status, LocalTerminalVerificationStatus.failed);
    expect(widgetTests.evidence, ['widget failure']);
  });
}

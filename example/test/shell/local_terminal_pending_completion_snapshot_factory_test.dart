import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_pending_completion_snapshot_factory.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('builds blocked snapshot from verification plan records', () {
    final snapshot = const LocalTerminalPendingCompletionSnapshotFactory()
        .build(capturedAt: DateTime.utc(2026, 5, 16));

    expect(snapshot.canCloseObjective, isFalse);
    expect(snapshot.blockedMilestoneCount, greaterThan(0));
    expect(snapshot.blockedBacklogItemCount, greaterThan(0));
    expect(
      snapshot.facade.verificationEvidence.requiredItems,
      hasLength(LocalTerminalVerificationEvidence.defaultRequiredGates.length),
    );
  });

  test('preserves verification command plan metadata in pending snapshot', () {
    final snapshot = const LocalTerminalPendingCompletionSnapshotFactory()
        .build(capturedAt: DateTime.utc(2026, 5, 16));
    final formattingGate = snapshot.facade.verificationEvidence.requiredItems
        .singleWhere(
          (item) => item.gate == LocalTerminalVerificationGate.formatting,
        );

    expect(formattingGate.status, LocalTerminalVerificationStatus.pending);
    expect(formattingGate.command, 'dart format example/lib example/test');
  });

  test('exposes implemented but unverified backlog evidence in snapshot', () {
    final snapshot = const LocalTerminalPendingCompletionSnapshotFactory()
        .build(capturedAt: DateTime.utc(2026, 5, 16));

    final backlogByTaskId = {
      for (final item in snapshot.facade.backlogEvidence.toBacklogItems())
        item.taskId: item,
    };

    expect(
      backlogByTaskId['T-164']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-164']!.evidence,
      contains(
        'ShellScreen command menu and shortcut dispatch use production action runtime for the current P1 action baseline.',
      ),
    );
    expect(
      backlogByTaskId['T-169']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(backlogByTaskId['T-169']!.blockers, isNotEmpty);
    expect(snapshot.canCloseObjective, isFalse);
  });
}

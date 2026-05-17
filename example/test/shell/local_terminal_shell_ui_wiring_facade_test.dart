import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_facade.dart';
import 'package:app/features/shell/local_terminal_verification_plan_records.dart';

void main() {
  test('exposes blocked completion diagnostics from wiring evidence', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final facade = LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: state.backlogEvidence,
      verificationEvidence: state.verificationEvidence,
    );

    expect(facade.canCloseObjective, isFalse);
    expect(facade.toPlainText(), contains('blocked'));
    expect(facade.diagnosticsViewModel.canCloseObjective, isFalse);
    expect(facade.completionMenuModel.hasBlockedEntries, isTrue);
  });

  test('combines report and verification evidence for closeability', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final facade = LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: state.backlogEvidence,
      verificationEvidence: state.verificationEvidence,
    );

    expect(
      facade.canCloseObjective,
      facade.report.canCloseObjective && facade.verificationEvidence.canClose,
    );
    expect(facade.toJson()['canCloseObjective'], isFalse);
    expect(
      facade.requiredBacklogBlockerCount,
      facade.report.requiredBacklogBlockerCount,
    );
    expect(
      facade.toJson()['requiredBacklogBlockerCount'],
      facade.report.requiredBacklogBlockerCount,
    );
  });

  test('preserves current backlog evidence in facade report', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final facade = LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: state.backlogEvidence,
      verificationEvidence: state.verificationEvidence,
    );

    final blockedByTaskId = {
      for (final item in facade.report.blockedBacklogItems) item.taskId: item,
    };

    expect(
      blockedByTaskId['T-164']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      blockedByTaskId['T-164']!.evidence,
      contains(
        'ShellScreen command menu and shortcut dispatch use production action runtime for the current P1 action baseline.',
      ),
    );
    expect(
      blockedByTaskId['T-169']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(blockedByTaskId['T-169']!.blockers, isNotEmpty);
  });

  test('exposes closed completion diagnostics from verified current state', () {
    final state = LocalTerminalCurrentCompletionState.verified(
      capturedAt: DateTime.utc(2026, 5, 16),
      verificationEvidence: LocalTerminalVerificationPlanRecords.latestPassed()
          .toRecorder()
          .evidence,
    );
    final facade = LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: state.backlogEvidence,
      verificationEvidence: state.verificationEvidence,
    );

    expect(facade.canCloseObjective, isTrue);
    expect(facade.requiredBacklogBlockerCount, 0);
    expect(facade.report.blockedBacklogItems, isEmpty);
    expect(facade.diagnosticsViewModel.canCloseObjective, isTrue);
    expect(facade.toJson()['canCloseObjective'], isTrue);
  });
}

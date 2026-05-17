import 'local_terminal_current_completion_state.dart';
import 'local_terminal_shell_ui_wiring_facade.dart';

class LocalTerminalShellUiWiringSnapshot {
  const LocalTerminalShellUiWiringSnapshot({
    required this.capturedAt,
    required this.facade,
  });

  factory LocalTerminalShellUiWiringSnapshot.pending({
    required DateTime capturedAt,
  }) {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: capturedAt,
    );
    return LocalTerminalShellUiWiringSnapshot(
      capturedAt: capturedAt,
      facade: LocalTerminalShellUiWiringFacade(
        bundle: state.bundle,
        backlogEvidence: state.backlogEvidence,
        verificationEvidence: state.verificationEvidence,
      ),
    );
  }

  final DateTime capturedAt;
  final LocalTerminalShellUiWiringFacade facade;

  bool get canCloseObjective => facade.canCloseObjective;

  int get blockedMilestoneCount =>
      facade.report.productionMilestoneBlockerCount;

  int get blockedBacklogItemCount {
    return facade.requiredBacklogBlockerCount;
  }

  int get blockedVerificationGateCount {
    return facade.verificationEvidence.verificationGateBlockerCount;
  }

  String get summaryText => facade.toPlainText();

  Map<String, Object?> toJson() {
    return {
      'capturedAt': capturedAt.toIso8601String(),
      'canCloseObjective': canCloseObjective,
      'blockedMilestoneCount': blockedMilestoneCount,
      'blockedBacklogItemCount': blockedBacklogItemCount,
      'blockedVerificationGateCount': blockedVerificationGateCount,
      'summaryText': summaryText,
      'facade': facade.toJson(),
    };
  }
}

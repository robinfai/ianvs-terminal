import 'local_terminal_shell_ui_wiring_snapshot.dart';

class LocalTerminalCompletionDiagnosticsPresentation {
  const LocalTerminalCompletionDiagnosticsPresentation({
    required this.mode,
    required this.visible,
    required this.title,
    required this.blockedMilestoneCount,
    required this.blockedBacklogItemCount,
    required this.blockedVerificationGateCount,
  });

  factory LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot({
    required LocalTerminalShellUiWiringSnapshot snapshot,
    LocalTerminalCompletionDiagnosticsPresentationMode mode =
        LocalTerminalCompletionDiagnosticsPresentationMode.inlinePanel,
  }) {
    return LocalTerminalCompletionDiagnosticsPresentation(
      mode: mode,
      visible: !snapshot.canCloseObjective,
      title: snapshot.canCloseObjective
          ? 'Local terminal objective is complete'
          : 'Local terminal objective is blocked',
      blockedMilestoneCount: snapshot.blockedMilestoneCount,
      blockedBacklogItemCount: snapshot.blockedBacklogItemCount,
      blockedVerificationGateCount: snapshot.blockedVerificationGateCount,
    );
  }

  final LocalTerminalCompletionDiagnosticsPresentationMode mode;
  final bool visible;
  final String title;
  final int blockedMilestoneCount;
  final int blockedBacklogItemCount;
  final int blockedVerificationGateCount;

  int get totalBlockedCount {
    return blockedMilestoneCount +
        blockedBacklogItemCount +
        blockedVerificationGateCount;
  }

  Map<String, Object?> toJson() {
    return {
      'mode': mode.name,
      'visible': visible,
      'title': title,
      'blockedMilestoneCount': blockedMilestoneCount,
      'blockedBacklogItemCount': blockedBacklogItemCount,
      'blockedVerificationGateCount': blockedVerificationGateCount,
      'totalBlockedCount': totalBlockedCount,
    };
  }
}

enum LocalTerminalCompletionDiagnosticsPresentationMode {
  inlinePanel,
  modalSheet,
  commandMenuSection,
  developerPanel,
}

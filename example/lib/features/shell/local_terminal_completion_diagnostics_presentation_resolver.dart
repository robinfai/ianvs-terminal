import 'local_terminal_completion_diagnostics_presentation.dart';
import 'local_terminal_shell_ui_wiring_snapshot.dart';

class LocalTerminalCompletionDiagnosticsPresentationResolver {
  const LocalTerminalCompletionDiagnosticsPresentationResolver({
    this.preferredMode =
        LocalTerminalCompletionDiagnosticsPresentationMode.inlinePanel,
    this.hideWhenComplete = true,
  });

  final LocalTerminalCompletionDiagnosticsPresentationMode preferredMode;
  final bool hideWhenComplete;

  LocalTerminalCompletionDiagnosticsPresentation resolve(
    LocalTerminalShellUiWiringSnapshot snapshot,
  ) {
    final presentation =
        LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot(
          snapshot: snapshot,
          mode: preferredMode,
        );

    if (!hideWhenComplete || !snapshot.canCloseObjective) {
      return presentation;
    }

    return LocalTerminalCompletionDiagnosticsPresentation(
      mode: preferredMode,
      visible: false,
      title: presentation.title,
      blockedMilestoneCount: presentation.blockedMilestoneCount,
      blockedBacklogItemCount: presentation.blockedBacklogItemCount,
      blockedVerificationGateCount: presentation.blockedVerificationGateCount,
    );
  }
}

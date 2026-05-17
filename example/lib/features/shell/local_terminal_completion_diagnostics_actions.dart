import 'local_terminal_completion_controller.dart';
import 'local_terminal_completion_diagnostics_view_model.dart';

class LocalTerminalCompletionDiagnosticsActionGroup {
  const LocalTerminalCompletionDiagnosticsActionGroup({
    required this.title,
    required this.status,
    required this.items,
  });

  factory LocalTerminalCompletionDiagnosticsActionGroup.fromController(
    LocalTerminalCompletionController controller,
  ) {
    final viewModel =
        LocalTerminalCompletionDiagnosticsViewModel.fromController(controller);

    return LocalTerminalCompletionDiagnosticsActionGroup.fromViewModel(
      viewModel,
    );
  }

  factory LocalTerminalCompletionDiagnosticsActionGroup.fromViewModel(
    LocalTerminalCompletionDiagnosticsViewModel viewModel,
  ) {
    return LocalTerminalCompletionDiagnosticsActionGroup(
      title: viewModel.title,
      status: viewModel.status,
      items: [
        for (final section in viewModel.sections)
          for (final item in section.items)
            LocalTerminalCompletionDiagnosticsActionItem(
              sectionTitle: section.title,
              title: item.label,
              description: item.description,
              severity: item.severity,
              enabled: false,
            ),
      ],
    );
  }

  final String title;
  final LocalTerminalCompletionDiagnosticsStatus status;
  final List<LocalTerminalCompletionDiagnosticsActionItem> items;

  bool get canCloseObjective {
    return status == LocalTerminalCompletionDiagnosticsStatus.closeable;
  }

  bool get hasBlockingItems {
    return items.any(
      (item) =>
          item.severity == LocalTerminalCompletionDiagnosticsSeverity.blocker,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'status': status.name,
      'canCloseObjective': canCloseObjective,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionDiagnosticsActionItem {
  const LocalTerminalCompletionDiagnosticsActionItem({
    required this.sectionTitle,
    required this.title,
    required this.description,
    required this.severity,
    required this.enabled,
  });

  final String sectionTitle;
  final String title;
  final String description;
  final LocalTerminalCompletionDiagnosticsSeverity severity;
  final bool enabled;

  Map<String, Object?> toJson() {
    return {
      'sectionTitle': sectionTitle,
      'title': title,
      'description': description,
      'severity': severity.name,
      'enabled': enabled,
    };
  }
}

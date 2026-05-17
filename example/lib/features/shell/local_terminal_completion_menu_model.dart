import 'local_terminal_completion_controller.dart';
import 'local_terminal_completion_diagnostics_actions.dart';
import 'local_terminal_completion_diagnostics_view_model.dart';

class LocalTerminalCompletionMenuModel {
  const LocalTerminalCompletionMenuModel({
    required this.title,
    required this.entries,
  });

  factory LocalTerminalCompletionMenuModel.fromController(
    LocalTerminalCompletionController controller,
  ) {
    return LocalTerminalCompletionMenuModel.fromActionGroup(
      LocalTerminalCompletionDiagnosticsActionGroup.fromController(controller),
    );
  }

  factory LocalTerminalCompletionMenuModel.fromActionGroup(
    LocalTerminalCompletionDiagnosticsActionGroup group,
  ) {
    return LocalTerminalCompletionMenuModel(
      title: group.title,
      entries: [
        for (final item in group.items)
          LocalTerminalCompletionMenuEntry(
            sectionTitle: item.sectionTitle,
            label: item.title,
            description: item.description,
            enabled: item.enabled,
            severity: item.severity,
          ),
      ],
    );
  }

  final String title;
  final List<LocalTerminalCompletionMenuEntry> entries;

  bool get hasBlockedEntries {
    return entries.any(
      (entry) =>
          entry.severity == LocalTerminalCompletionDiagnosticsSeverity.blocker,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'hasBlockedEntries': hasBlockedEntries,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionMenuEntry {
  const LocalTerminalCompletionMenuEntry({
    required this.sectionTitle,
    required this.label,
    required this.description,
    required this.enabled,
    required this.severity,
  });

  final String sectionTitle;
  final String label;
  final String description;
  final bool enabled;
  final LocalTerminalCompletionDiagnosticsSeverity severity;

  Map<String, Object?> toJson() {
    return {
      'sectionTitle': sectionTitle,
      'label': label,
      'description': description,
      'enabled': enabled,
      'severity': severity.name,
    };
  }
}

import 'local_terminal_completion_controller.dart';
import 'local_terminal_completion_diagnostics_view_model.dart';
import 'local_terminal_completion_menu_model.dart';

class LocalTerminalCompletionCommandMenuAdapter {
  const LocalTerminalCompletionCommandMenuAdapter({required this.model});

  factory LocalTerminalCompletionCommandMenuAdapter.fromController(
    LocalTerminalCompletionController controller,
  ) {
    return LocalTerminalCompletionCommandMenuAdapter(
      model: LocalTerminalCompletionMenuModel.fromController(controller),
    );
  }

  final LocalTerminalCompletionMenuModel model;

  List<LocalTerminalCompletionCommandMenuSection> buildSections() {
    final sectionsByTitle =
        <String, List<LocalTerminalCompletionCommandMenuItem>>{};

    for (final entry in model.entries) {
      sectionsByTitle
          .putIfAbsent(entry.sectionTitle, () => [])
          .add(
            LocalTerminalCompletionCommandMenuItem(
              title: entry.label,
              subtitle: entry.description,
              enabled: entry.enabled,
              severity: entry.severity,
            ),
          );
    }

    return [
      for (final entry in sectionsByTitle.entries)
        LocalTerminalCompletionCommandMenuSection(
          title: entry.key,
          items: List.unmodifiable(entry.value),
        ),
    ];
  }

  Map<String, Object?> toJson() {
    return {
      'title': model.title,
      'hasBlockedEntries': model.hasBlockedEntries,
      'sections': buildSections().map((section) => section.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionCommandMenuSection {
  const LocalTerminalCompletionCommandMenuSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<LocalTerminalCompletionCommandMenuItem> items;

  bool get hasBlockedItems {
    return items.any((item) => item.isBlocker);
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'hasBlockedItems': hasBlockedItems,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionCommandMenuItem {
  const LocalTerminalCompletionCommandMenuItem({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.severity,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final LocalTerminalCompletionDiagnosticsSeverity severity;

  bool get isBlocker {
    return severity == LocalTerminalCompletionDiagnosticsSeverity.blocker;
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      'enabled': enabled,
      'severity': severity.name,
      'isBlocker': isBlocker,
    };
  }
}

import 'local_terminal_completion_menu_model.dart';
import 'shell_command_menu_diagnostics.dart';

class LocalTerminalCompletionShellCommandMenuDiagnostics {
  const LocalTerminalCompletionShellCommandMenuDiagnostics({
    required this.entries,
  });

  factory LocalTerminalCompletionShellCommandMenuDiagnostics.fromMenuModel(
    LocalTerminalCompletionMenuModel model,
  ) {
    return LocalTerminalCompletionShellCommandMenuDiagnostics(
      entries: [
        for (final entry in model.entries)
          LocalTerminalCompletionShellCommandMenuDiagnosticEntry(
            sectionTitle: entry.sectionTitle,
            label: entry.label,
            enabled: entry.enabled,
            disabledReason: entry.enabled
                ? null
                : ShellCommandMenuDisabledReason(
                    title: entry.label,
                    description: entry.description,
                  ),
          ),
      ],
    );
  }

  final List<LocalTerminalCompletionShellCommandMenuDiagnosticEntry> entries;

  bool get hasDisabledEntries {
    return entries.any((entry) => !entry.enabled);
  }

  List<LocalTerminalCompletionShellCommandMenuDiagnosticEntry>
  get disabledEntries {
    return entries.where((entry) => !entry.enabled).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return {
      'hasDisabledEntries': hasDisabledEntries,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionShellCommandMenuDiagnosticEntry {
  const LocalTerminalCompletionShellCommandMenuDiagnosticEntry({
    required this.sectionTitle,
    required this.label,
    required this.enabled,
    required this.disabledReason,
  });

  final String sectionTitle;
  final String label;
  final bool enabled;
  final ShellCommandMenuDisabledReason? disabledReason;

  Map<String, Object?> toJson() {
    return {
      'sectionTitle': sectionTitle,
      'label': label,
      'enabled': enabled,
      'disabledReason': disabledReason == null
          ? null
          : {
              'title': disabledReason!.title,
              'description': disabledReason!.description,
            },
    };
  }
}

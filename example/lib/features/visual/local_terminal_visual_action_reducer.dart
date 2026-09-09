import '../shell/shell_action_registry.dart';
import 'local_terminal_scrollback_exporter.dart';
import 'local_terminal_visual_models.dart';

sealed class LocalTerminalVisualActionResult {
  const LocalTerminalVisualActionResult();
}

class LocalTerminalExportScrollbackResult
    extends LocalTerminalVisualActionResult {
  const LocalTerminalExportScrollbackResult(this.export);

  final LocalTerminalScrollbackExport export;
}

class LocalTerminalVisualNoopResult extends LocalTerminalVisualActionResult {
  const LocalTerminalVisualNoopResult();
}

class LocalTerminalVisualActionContext {
  const LocalTerminalVisualActionContext({
    this.scrollbackText = '',
    this.exportFormat = LocalTerminalExportFormat.plainText,
  });

  final String scrollbackText;
  final LocalTerminalExportFormat exportFormat;
}

class LocalTerminalVisualActionReducer {
  const LocalTerminalVisualActionReducer._();

  static LocalTerminalVisualActionResult reduce({
    required TerminalActionId actionId,
    required LocalTerminalVisualActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.exportScrollback => LocalTerminalExportScrollbackResult(
        LocalTerminalScrollbackExport(
          format: context.exportFormat,
          content: context.scrollbackText,
        ),
      ),
      _ => const LocalTerminalVisualNoopResult(),
    };
  }
}

import '../shell/shell_action_registry.dart';
import 'local_terminal_scrollback_exporter.dart';
import 'local_terminal_visual_models.dart';

sealed class LocalTerminalVisualActionResult {
  const LocalTerminalVisualActionResult();
}

class LocalTerminalOpenThemePickerResult
    extends LocalTerminalVisualActionResult {
  const LocalTerminalOpenThemePickerResult();
}

class LocalTerminalExportScrollbackResult
    extends LocalTerminalVisualActionResult {
  const LocalTerminalExportScrollbackResult(this.export);

  final LocalTerminalScrollbackExport export;
}

class LocalTerminalApplyLayoutTemplateResult
    extends LocalTerminalVisualActionResult {
  const LocalTerminalApplyLayoutTemplateResult(this.template);

  final LocalTerminalLayoutTemplate? template;
}

class LocalTerminalVisualNoopResult extends LocalTerminalVisualActionResult {
  const LocalTerminalVisualNoopResult();
}

class LocalTerminalVisualActionContext {
  const LocalTerminalVisualActionContext({
    this.scrollbackText = '',
    this.exportFormat = LocalTerminalExportFormat.plainText,
    this.layoutTemplate,
  });

  final String scrollbackText;
  final LocalTerminalExportFormat exportFormat;
  final LocalTerminalLayoutTemplate? layoutTemplate;
}

class LocalTerminalVisualActionReducer {
  const LocalTerminalVisualActionReducer._();

  static LocalTerminalVisualActionResult reduce({
    required TerminalActionId actionId,
    required LocalTerminalVisualActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.openThemePicker =>
        const LocalTerminalOpenThemePickerResult(),
      TerminalActionId.exportScrollback => LocalTerminalExportScrollbackResult(
        LocalTerminalScrollbackExport(
          format: context.exportFormat,
          content: context.scrollbackText,
        ),
      ),
      TerminalActionId.applyLayoutTemplate =>
        LocalTerminalApplyLayoutTemplateResult(context.layoutTemplate),
      _ => const LocalTerminalVisualNoopResult(),
    };
  }
}

import 'local_terminal_completion_command_menu_adapter.dart';
import 'local_terminal_completion_controller.dart';
import 'local_terminal_completion_menu_model.dart';
import 'local_terminal_completion_summary.dart';

class LocalTerminalCompletionDiagnosticsBundle {
  LocalTerminalCompletionDiagnosticsBundle({required this.controller})
    : summary = controller.summary,
      menuModel = LocalTerminalCompletionMenuModel.fromController(controller),
      commandMenuAdapter =
          LocalTerminalCompletionCommandMenuAdapter.fromController(controller);

  final LocalTerminalCompletionController controller;
  final LocalTerminalCompletionSummary summary;
  final LocalTerminalCompletionMenuModel menuModel;
  final LocalTerminalCompletionCommandMenuAdapter commandMenuAdapter;

  bool get canCloseObjective => controller.canCloseObjective;

  bool get hasBlockedMenuEntries => menuModel.hasBlockedEntries;

  String toPlainText() {
    return summary.toPlainText();
  }

  Map<String, Object?> toJson() {
    return {
      'canCloseObjective': canCloseObjective,
      'summary': summary.toJson(),
      'menuModel': menuModel.toJson(),
      'commandMenu': commandMenuAdapter.toJson(),
    };
  }
}

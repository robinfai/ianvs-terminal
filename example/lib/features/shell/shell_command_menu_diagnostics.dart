import 'shell_action_error_diagnostics.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_controller.dart';
import 'shell_action_view_models.dart';

class ShellCommandMenuDiagnosticsState {
  const ShellCommandMenuDiagnosticsState({
    required this.items,
    required this.runtimeError,
  });

  factory ShellCommandMenuDiagnosticsState.fromMenuItems({
    required Iterable<ShellActionMenuItemViewModel> menuItems,
    Object? lastExternalExecutorError,
  }) {
    return ShellCommandMenuDiagnosticsState(
      items: menuItems
          .map(ShellCommandMenuDiagnosticItem.fromMenuItem)
          .toList(growable: false),
      runtimeError: ShellActionErrorDiagnostics.fromExternalExecutorError(
        lastExternalExecutorError,
      ),
    );
  }

  factory ShellCommandMenuDiagnosticsState.fromRuntimeState({
    required Iterable<ShellActionMenuItemViewModel> menuItems,
    required ShellActionRuntimeState runtimeState,
  }) {
    return ShellCommandMenuDiagnosticsState.fromMenuItems(
      menuItems: menuItems,
      lastExternalExecutorError: runtimeState.lastExternalExecutorError,
    );
  }

  final List<ShellCommandMenuDiagnosticItem> items;
  final ShellActionErrorDiagnostic? runtimeError;

  bool get hasRuntimeError => runtimeError != null;

  bool get hasDisabledItems => items.any((item) => item.isDisabled);

  List<ShellCommandMenuDiagnosticItem> get disabledItems {
    return items.where((item) => item.isDisabled).toList(growable: false);
  }

  ShellCommandMenuDiagnosticItem? itemFor(TerminalActionId actionId) {
    for (final item in items) {
      if (item.actionId == actionId) {
        return item;
      }
    }
    return null;
  }
}

class ShellCommandMenuDiagnosticItem {
  const ShellCommandMenuDiagnosticItem({
    required this.actionId,
    required this.label,
    required this.enabled,
    required this.shortcutHint,
    required this.disabledReason,
  });

  factory ShellCommandMenuDiagnosticItem.fromMenuItem(
    ShellActionMenuItemViewModel item,
  ) {
    return ShellCommandMenuDiagnosticItem(
      actionId: item.actionId,
      label: item.label,
      enabled: item.enabled,
      shortcutHint: item.shortcutHint,
      disabledReason: item.enabled
          ? null
          : ShellCommandMenuDisabledReason(
              title: item.disabledTitle ?? 'Action unavailable',
              description: item.disabledDescription,
            ),
    );
  }

  final TerminalActionId actionId;
  final String label;
  final bool enabled;
  final String? shortcutHint;
  final ShellCommandMenuDisabledReason? disabledReason;

  bool get isDisabled => !enabled;
}

class ShellCommandMenuDisabledReason {
  const ShellCommandMenuDisabledReason({
    required this.title,
    required this.description,
  });

  final String title;
  final String? description;
}

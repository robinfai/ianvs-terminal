import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_view_models.dart';
import 'package:app/features/shell/shell_command_menu_diagnostics.dart';

void main() {
  test('summarizes disabled command menu items', () {
    const menuItem = ShellActionMenuItemViewModel(
      actionId: TerminalActionId.closePane,
      label: 'Close Pane',
      enabled: false,
      shortcutHint: 'Command+W',
      disabledTitle: 'No pane to close',
      disabledDescription: 'The active tab only has one pane.',
    );

    final diagnostics = ShellCommandMenuDiagnosticsState.fromMenuItems(
      menuItems: const [menuItem],
    );

    expect(diagnostics.hasDisabledItems, isTrue);
    expect(diagnostics.disabledItems, hasLength(1));
    expect(
      diagnostics.itemFor(TerminalActionId.closePane)?.disabledReason?.title,
      'No pane to close',
    );
  });

  test('maps external executor errors into runtime diagnostics', () {
    final diagnostics = ShellCommandMenuDiagnosticsState.fromMenuItems(
      menuItems: const [],
      lastExternalExecutorError: StateError('executor unavailable'),
    );

    expect(diagnostics.hasRuntimeError, isTrue);
    expect(diagnostics.runtimeError?.description, contains('executor'));
  });
}

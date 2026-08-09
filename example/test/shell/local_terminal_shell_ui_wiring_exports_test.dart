import 'package:app/features/shell/local_terminal_shell_ui_wiring_exports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports shell UI wiring diagnostics entry points', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final menuModel = LocalTerminalCompletionMenuModel.fromController(
      controller,
    );

    expect(snapshot.canCloseObjective, isFalse);
    expect(menuModel.hasBlockedEntries, isTrue);
  });
}

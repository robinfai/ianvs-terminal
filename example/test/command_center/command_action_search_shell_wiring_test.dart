import 'package:app/features/command_center/command_action_search_controller.dart';
import 'package:app/features/command_center/command_action_search_index.dart';
import 'package:app/features/command_center/command_action_search_shell_wiring.dart';
import 'package:app/features/command_center/command_search_intents.dart';
import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandActionSearchShellWiring', () {
    const wiring = CommandActionSearchShellWiring();
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    test('builds a controller from app actions and saved commands', () {
      final controller = wiring.controllerFor(
        actions: const [
          CommandActionSearchItem.appAction(
            id: 'toggle-read-only',
            title: 'Toggle read only',
          ),
        ],
        savedCommands: SavedCommandDocument(
          entries: [
            _savedCommand(
              id: 'release-build',
              title: 'Build release',
              command: 'flutter build macos --release',
              updatedAt: baseTime,
            ),
          ],
        ),
      )..handleIntent(CommandActionSearchIntent.openSearch);

      expect(controller.state.results.map((result) => result.item.id), [
        'toggle-read-only',
        'release-build',
      ]);
    });

    test('resolves saved command output through terminal safety policy', () {
      final output = CommandActionSearchOutput.insertSavedCommand(
        CommandActionSearchItem.savedCommand(
          _savedCommand(
            id: 'status',
            title: 'Status',
            command: 'git status',
            updatedAt: baseTime,
          ),
        ),
      );

      final intent = wiring.terminalIntentFor(output, readOnly: false);
      final readOnly = wiring.terminalIntentFor(output, readOnly: true);

      expect(intent.kind, CommandSearchTerminalIntentKind.insertText);
      expect(intent.text, 'git status');
      expect(intent.writesToShell, isTrue);
      expect(readOnly.kind, CommandSearchTerminalIntentKind.disabled);
      expect(readOnly.reason, CommandSearchTerminalIntentReason.readOnly);
    });

    test('routes multiline saved commands to paste policy', () {
      final output = CommandActionSearchOutput.insertSavedCommand(
        CommandActionSearchItem.savedCommand(
          _savedCommand(
            id: 'multiline',
            title: 'Multiline',
            command: 'echo one\necho two',
            updatedAt: baseTime,
          ),
        ),
      );

      final intent = wiring.terminalIntentFor(output, readOnly: false);

      expect(intent.kind, CommandSearchTerminalIntentKind.requiresPastePolicy);
      expect(intent.text, 'echo one\necho two');
      expect(
        intent.reason,
        CommandSearchTerminalIntentReason.multilineRequiresPastePolicy,
      );
    });

    test('does not map app action output into terminal writes', () {
      const action = CommandActionSearchItem.appAction(
        id: 'toggle-read-only',
        title: 'Toggle read only',
      );

      final intent = wiring.terminalIntentFor(
        const CommandActionSearchOutput.openAction(action),
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.none);
      expect(intent.writesToShell, isFalse);
    });
  });
}

SavedCommandEntry _savedCommand({
  required String id,
  required String title,
  required String command,
  required DateTime updatedAt,
}) {
  return SavedCommandEntry(
    id: id,
    title: title,
    command: command,
    createdAt: updatedAt.subtract(const Duration(days: 1)),
    updatedAt: updatedAt,
  );
}

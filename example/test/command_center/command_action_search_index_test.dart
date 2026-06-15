import 'package:app/features/command_center/command_action_search_index.dart';
import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandActionSearchIndex', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    test('matches app actions by title and keywords', () {
      final index = CommandActionSearchIndex(
        actions: const [
          CommandActionSearchItem.appAction(
            id: 'toggle-read-only',
            title: 'Toggle read-only',
            subtitle: 'Protect terminal input',
            keywords: ['input lock', 'safe mode'],
          ),
          CommandActionSearchItem.appAction(
            id: 'clear-terminal',
            title: 'Clear terminal',
            subtitle: 'Reset visible scrollback',
          ),
        ],
        savedCommands: [
          _savedCommand(
            id: 'release-build',
            title: 'Build release',
            command: 'flutter build macos --release',
            updatedAt: baseTime,
          ),
        ],
      );

      final byTitle = index.search('read');
      final byKeyword = index.search('safe mode');

      expect(byTitle.first.item.id, 'toggle-read-only');
      expect(byTitle.first.item.kind, CommandActionSearchItemKind.appAction);
      expect(byTitle.first.item.selection, CommandActionSelection.openAction);
      expect(byKeyword.first.item.id, 'toggle-read-only');
    });

    test('matches saved commands by title, tag, and command text', () {
      final index = CommandActionSearchIndex(
        actions: const [
          CommandActionSearchItem.appAction(
            id: 'toggle-read-only',
            title: 'Toggle read-only',
            keywords: ['safe mode'],
          ),
        ],
        savedCommands: [
          _savedCommand(
            id: 'release-build',
            title: 'Build release',
            command: 'flutter build macos --release',
            tags: const ['shipping', 'macos'],
            updatedAt: baseTime,
          ),
        ],
      );

      final byTitle = index.search('build');
      final byTag = index.search('shipping');
      final byCommand = index.search('--release');

      expect(byTitle.first.item.id, 'release-build');
      expect(byTag.first.item.id, 'release-build');
      expect(byCommand.first.item.command, 'flutter build macos --release');
      expect(
        byCommand.first.item.kind,
        CommandActionSearchItemKind.savedCommand,
      );
      expect(
        byCommand.first.item.selection,
        CommandActionSelection.insertSavedCommand,
      );
      expect(byCommand.first.item.writesToTerminalOnSelect, isFalse);
    });

    test('orders empty query by action first, then saved command use', () {
      final index = CommandActionSearchIndex(
        actions: const [
          CommandActionSearchItem.appAction(
            id: 'open-history',
            title: 'Open history search',
          ),
        ],
        savedCommands: [
          _savedCommand(
            id: 'rare-command',
            title: 'Rare command',
            command: 'echo rare',
            useCount: 1,
            updatedAt: baseTime.add(const Duration(minutes: 1)),
          ),
          _savedCommand(
            id: 'hot-command',
            title: 'Hot command',
            command: 'echo hot',
            useCount: 8,
            updatedAt: baseTime,
          ),
        ],
      );

      final results = index.search('', limit: 2);

      expect(results.map((result) => result.item.id), [
        'open-history',
        'hot-command',
      ]);
    });
  });
}

SavedCommandEntry _savedCommand({
  required String id,
  required String title,
  required String command,
  required DateTime updatedAt,
  List<String> tags = const <String>[],
  int useCount = 0,
}) {
  return SavedCommandEntry(
    id: id,
    title: title,
    command: command,
    tags: tags,
    createdAt: updatedAt.subtract(const Duration(days: 1)),
    updatedAt: updatedAt,
    useCount: useCount,
  );
}

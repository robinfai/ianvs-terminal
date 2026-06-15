import 'package:app/features/command_center/command_action_search_controller.dart';
import 'package:app/features/command_center/command_action_search_index.dart';
import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandActionSearchController', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    test('opens action search from an explicit intent', () {
      final controller = _controller(baseTime);

      final output = controller.handleIntent(
        CommandActionSearchIntent.openSearch,
      );

      expect(output.kind, CommandActionSearchOutputKind.none);
      expect(controller.state.isOpen, isTrue);
      expect(controller.state.query, '');
      expect(controller.state.results, isNotEmpty);
      expect(controller.state.selectedIndex, 0);
    });

    test('closes search and clears temporary query state', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandActionSearchIntent.openSearch)
        ..updateQuery('build');

      controller.handleIntent(CommandActionSearchIntent.closeSearch);

      expect(controller.state.isOpen, isFalse);
      expect(controller.state.query, '');
      expect(controller.state.results, isEmpty);
      expect(controller.state.selectedIndex, -1);
    });

    test('updates query and moves selection with bounded indexes', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandActionSearchIntent.openSearch)
        ..updateQuery('search');

      expect(controller.state.results.map((result) => result.item.id), [
        'open-history',
        'open-review',
      ]);

      controller.handleIntent(CommandActionSearchIntent.moveNext);
      expect(controller.state.selectedIndex, 1);

      controller.handleIntent(CommandActionSearchIntent.moveNext);
      expect(controller.state.selectedIndex, 1);

      controller.handleIntent(CommandActionSearchIntent.movePrevious);
      expect(controller.state.selectedIndex, 0);
    });

    test('accepting an app action emits open action output', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandActionSearchIntent.openSearch)
        ..updateQuery('read only');

      final output = controller.handleIntent(
        CommandActionSearchIntent.acceptSelection,
      );

      expect(output.kind, CommandActionSearchOutputKind.openAction);
      expect(output.item?.id, 'toggle-read-only');
      expect(output.actionId, 'toggle-read-only');
      expect(output.command, isNull);
    });

    test('accepting a saved command emits insert-only output', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandActionSearchIntent.openSearch)
        ..updateQuery('release');

      final output = controller.handleIntent(
        CommandActionSearchIntent.acceptSelection,
      );

      expect(output.kind, CommandActionSearchOutputKind.insertSavedCommand);
      expect(output.item?.id, 'release-build');
      expect(output.command, 'flutter build macos --release');
      expect(output.item?.writesToTerminalOnSelect, isFalse);
    });

    test('returns no output when accepting an empty result set', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandActionSearchIntent.openSearch)
        ..updateQuery('zzzz-not-found');

      final output = controller.handleIntent(
        CommandActionSearchIntent.acceptSelection,
      );

      expect(controller.state.empty, isTrue);
      expect(controller.state.selectedResult, isNull);
      expect(output.kind, CommandActionSearchOutputKind.none);
    });
  });
}

CommandActionSearchController _controller(DateTime baseTime) {
  return CommandActionSearchController(
    index: CommandActionSearchIndex(
      actions: const [
        CommandActionSearchItem.appAction(
          id: 'open-history',
          title: 'Open history search',
          keywords: ['search commands'],
        ),
        CommandActionSearchItem.appAction(
          id: 'open-review',
          title: 'Open review search',
          keywords: ['search output'],
        ),
        CommandActionSearchItem.appAction(
          id: 'toggle-read-only',
          title: 'Toggle read only',
          keywords: ['read only'],
        ),
      ],
      savedCommands: [
        SavedCommandEntry(
          id: 'release-build',
          title: 'Build release',
          command: 'flutter build macos --release',
          tags: const ['release'],
          createdAt: baseTime.subtract(const Duration(days: 1)),
          updatedAt: baseTime,
        ),
      ],
    ),
  );
}

import 'package:app/features/command_center/command_search_index.dart';
import 'package:app/features/command_center/command_search_overlay_controller.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchOverlayController', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);

    test('opens search from Ctrl-R intent', () {
      final controller = _controller(baseTime);

      final output = controller.handleIntent(
        CommandSearchOverlayKeyIntent.openSearch,
      );

      expect(output.kind, CommandSearchOverlayOutputKind.none);
      expect(controller.state.isOpen, isTrue);
      expect(controller.state.query, '');
      expect(controller.state.results, isNotEmpty);
      expect(controller.state.selectedIndex, 0);
    });

    test('closes search from Esc and clears temporary query state', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('flutter');

      controller.handleIntent(CommandSearchOverlayKeyIntent.closeSearch);

      expect(controller.state.isOpen, isFalse);
      expect(controller.state.query, '');
      expect(controller.state.results, isEmpty);
      expect(controller.state.selectedIndex, -1);
    });

    test('updates query and moves selection with arrow intents', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('test');

      expect(controller.state.results.map((result) => result.entry.command), [
        'flutter test',
      ]);

      controller.handleIntent(CommandSearchOverlayKeyIntent.moveNext);
      expect(controller.state.selectedIndex, 0);

      controller.handleIntent(CommandSearchOverlayKeyIntent.movePrevious);
      expect(controller.state.selectedIndex, 0);
    });

    test('enter produces insert intent for the selected command', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('flutter');

      final output = controller.handleIntent(
        CommandSearchOverlayKeyIntent.insertSelection,
      );

      expect(output.kind, CommandSearchOverlayOutputKind.insert);
      expect(output.command, 'flutter test');
    });

    test('modified enter produces explicit execute intent', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('flutter');

      final output = controller.handleIntent(
        CommandSearchOverlayKeyIntent.executeSelection,
      );

      expect(output.kind, CommandSearchOverlayOutputKind.explicitExecute);
      expect(output.command, 'flutter test');
    });

    test('can switch between current session and global scopes', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('test');

      expect(controller.state.results.map((result) => result.entry.command), [
        'flutter test',
      ]);

      controller.updateScope(CommandSearchHistoryScope.global);

      expect(controller.state.scope, CommandSearchHistoryScope.global);
      expect(controller.state.results.map((result) => result.entry.command), [
        'flutter test',
        'npm test',
      ]);
    });

    test('keeps updated scope when reopening from a closed state', () {
      final controller = _controller(baseTime)
        ..updateScope(CommandSearchHistoryScope.global)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch);

      expect(controller.state.scope, CommandSearchHistoryScope.global);
      expect(controller.state.results.map((result) => result.entry.command), [
        'flutter test',
        'npm test',
        'git status',
      ]);
    });

    test('viewSelectedBlock returns the selected invocation id', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('flutter');

      final output = controller.viewSelectedBlock();

      expect(output.kind, CommandSearchOverlayOutputKind.viewBlock);
      expect(output.invocationId, 'inv-1');
      expect(output.command, isNull);
    });

    test('keeps a stable empty state when no results match', () {
      final controller = _controller(baseTime)
        ..handleIntent(CommandSearchOverlayKeyIntent.openSearch)
        ..updateQuery('zzzz-not-found');

      expect(controller.state.isOpen, isTrue);
      expect(controller.state.empty, isTrue);
      expect(controller.state.selectedIndex, -1);
      expect(controller.state.selectedResult, isNull);
      expect(
        controller
            .handleIntent(CommandSearchOverlayKeyIntent.insertSelection)
            .kind,
        CommandSearchOverlayOutputKind.none,
      );
    });
  });
}

CommandSearchOverlayController _controller(DateTime baseTime) {
  return CommandSearchOverlayController(
    index: CommandSearchIndex([
      GlobalCommandHistoryEntry(
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 0,
        finishedAt: baseTime.add(const Duration(seconds: 2)),
        invocationId: 'inv-1',
        sessionId: 'session-a',
      ),
      GlobalCommandHistoryEntry(
        command: 'npm test',
        cwd: '/repo',
        exitCode: 0,
        finishedAt: baseTime.add(const Duration(seconds: 1)),
        invocationId: 'inv-2',
        sessionId: 'session-b',
      ),
      GlobalCommandHistoryEntry(
        command: 'git status',
        cwd: '/repo',
        exitCode: 0,
        finishedAt: baseTime,
        invocationId: 'inv-3',
      ),
    ]),
    currentCwd: '/repo',
    currentSessionId: 'session-a',
  );
}

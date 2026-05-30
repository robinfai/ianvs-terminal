import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell productivity model', () {
    test('prompt navigation finds nearest previous and next marks', () {
      const state = ShellProductivityState(
        promptMarks: [
          ShellPromptMark(id: 'p1', row: 2),
          ShellPromptMark(id: 'p2', row: 8),
          ShellPromptMark(id: 'p3', row: 13),
        ],
      );

      expect(state.previousPrompt(10)!.id, 'p2');
      expect(state.nextPrompt(10)!.id, 'p3');
    });

    test('disabled shell integration gates prompt navigation', () {
      const state = ShellProductivityState(
        features: ShellIntegrationFeatureSet.disabled(),
        promptMarks: [ShellPromptMark(id: 'p1', row: 2)],
      );

      expect(state.canNavigatePrompts, isFalse);
      expect(state.previousPrompt(10), isNull);
    });

    test('last command output skips invalid ranges', () {
      const state = ShellProductivityState(
        commandOutputRanges: [
          ShellCommandOutputRange(commandId: 'bad', startRow: 9, endRow: 3),
          ShellCommandOutputRange(commandId: 'ok', startRow: 4, endRow: 7),
        ],
      );

      expect(state.canSelectCommandOutput, isTrue);
      expect(state.lastCommandOutputRange()!.commandId, 'ok');
    });

    test('read only mode blocks text send and paste', () {
      const state = ShellProductivityState(readOnly: true);

      expect(state.canSendText, isFalse);
      expect(state.canPaste, isFalse);
      expect(state.toggleReadOnly().canPaste, isTrue);
    });

    test('recent directories are gated by feature availability', () {
      const enabled = ShellProductivityState(recentDirectories: ['/tmp']);
      const disabled = ShellProductivityState(
        features: ShellIntegrationFeatureSet.disabled(),
        recentDirectories: ['/tmp'],
      );

      expect(enabled.canOpenRecentDirectory, isTrue);
      expect(disabled.canOpenRecentDirectory, isFalse);
    });

    test('search state cycles next and previous matches', () {
      const state = ShellSearchState(
        query: 'build',
        matches: [
          ShellSearchMatch(row: 1, column: 0, length: 5),
          ShellSearchMatch(row: 3, column: 2, length: 5),
        ],
        activeMatchIndex: 0,
      );

      expect(state.nextMatch().activeMatch!.row, 3);
      expect(state.previousMatch().activeMatch!.row, 3);
      expect(state.clear().isActive, isFalse);
    });

    test('search state can scope matches to a command block', () {
      const state = ShellSearchState(
        query: 'test',
        matches: [
          ShellSearchMatch(row: 2, column: 0, length: 4, blockId: 'b1'),
          ShellSearchMatch(row: 8, column: 0, length: 4, blockId: 'b2'),
        ],
      );

      final scoped = state.scopedToBlock('b2');

      expect(scoped.scopedBlockId, 'b2');
      expect(scoped.matches, hasLength(1));
      expect(scoped.activeMatch!.row, 8);
    });

    test('command block checks row containment', () {
      const block = ShellCommandBlock(
        id: 'b1',
        command: 'flutter test',
        startRow: 4,
        endRow: 9,
      );

      expect(block.containsRow(6), isTrue);
      expect(block.containsRow(10), isFalse);
    });

    test('recent commands and directories keep newest unique entries', () {
      final state = const ShellRecentItemsState(limit: 2)
          .addCommand(
            const ShellRecentCommandEntry(
              command: 'flutter test',
              cwd: '/repo',
              exitCode: 0,
            ),
          )
          .addCommand(
            const ShellRecentCommandEntry(
              command: 'dart analyze',
              cwd: '/repo',
              exitCode: 1,
            ),
          )
          .addCommand(
            const ShellRecentCommandEntry(
              command: 'flutter test',
              cwd: '/repo',
              exitCode: 0,
            ),
          )
          .addDirectory(const ShellRecentDirectoryEntry(path: '/repo'))
          .addDirectory(const ShellRecentDirectoryEntry(path: '/tmp'))
          .addDirectory(const ShellRecentDirectoryEntry(path: '/repo'));

      expect(state.commands, hasLength(2));
      expect(state.commands.first.command, 'flutter test');
      expect(state.commands.first.succeeded, isTrue);
      expect(state.directories, hasLength(2));
      expect(state.directories.first.path, '/repo');
    });

    test('recent items default invalid limits', () {
      final state = ShellRecentItemsState.fromJson({
        'limit': 0,
        'commands': [
          {'command': 'flutter test', 'cwd': '/repo', 'exitCode': 0},
        ],
        'directories': [
          {'path': '/repo'},
        ],
      });

      expect(state.limit, 50);
      expect(state.commands.single.command, 'flutter test');
      expect(state.directories.single.path, '/repo');
      expect(
        ShellRecentItemsState.fromJson({'limit': double.infinity}).limit,
        50,
      );
      expect(const ShellRecentItemsState(limit: -1).trimmed().limit, 50);
    });
  });
}

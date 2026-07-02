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

    test('prompt navigation skips invalid marks', () {
      const state = ShellProductivityState(
        promptMarks: [
          ShellPromptMark(id: '', row: 4),
          ShellPromptMark(id: 'negative', row: -1),
          ShellPromptMark(id: 'ok', row: 8),
        ],
      );
      const invalidOnly = ShellProductivityState(
        promptMarks: [ShellPromptMark(id: '', row: -1)],
      );

      expect(state.canNavigatePrompts, isTrue);
      expect(state.previousPrompt(10)!.id, 'ok');
      expect(state.nextPrompt(1)!.id, 'ok');
      expect(invalidOnly.canNavigatePrompts, isFalse);
      expect(invalidOnly.previousPrompt(10), isNull);
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

    test('command output ranges reject negative rows', () {
      const state = ShellProductivityState(
        commandOutputRanges: [
          ShellCommandOutputRange(
            commandId: 'negative',
            startRow: -4,
            endRow: -1,
          ),
        ],
      );

      expect(state.canSelectCommandOutput, isFalse);
      expect(state.lastCommandOutputRange(), isNull);
    });

    test('command output ranges require a command id', () {
      const state = ShellProductivityState(
        commandOutputRanges: [
          ShellCommandOutputRange(commandId: '   ', startRow: 1, endRow: 2),
          ShellCommandOutputRange(commandId: 'cmd', startRow: 3, endRow: 4),
        ],
      );

      expect(state.canSelectCommandOutput, isTrue);
      expect(state.lastCommandOutputRange()!.commandId, 'cmd');
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

    test('recent directories skip blank entries', () {
      const state = ShellProductivityState(
        recentDirectories: ['', '   ', ' /repo '],
      );
      const blankOnly = ShellProductivityState(recentDirectories: ['', '  ']);

      expect(state.canOpenRecentDirectory, isTrue);
      expect(state.firstRecentDirectory, '/repo');
      expect(blankOnly.canOpenRecentDirectory, isFalse);
      expect(blankOnly.firstRecentDirectory, isNull);
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

    test('search state skips invalid matches', () {
      const state = ShellSearchState(
        query: 'build',
        matches: [
          ShellSearchMatch(row: -1, column: 0, length: 5),
          ShellSearchMatch(row: 3, column: -1, length: 5),
          ShellSearchMatch(row: 5, column: 2, length: 0),
          ShellSearchMatch(row: 8, column: 1, length: 5),
        ],
        activeMatchIndex: 0,
      );
      const invalidOnly = ShellSearchState(
        query: 'build',
        matches: [ShellSearchMatch(row: -1, column: 0, length: 5)],
      );

      expect(state.hasMatches, isTrue);
      expect(state.activeMatch, isNull);
      expect(state.nextMatch().activeMatch!.row, 8);
      expect(state.previousMatch().activeMatch!.row, 8);
      expect(invalidOnly.hasMatches, isFalse);
      expect(invalidOnly.nextMatch().activeMatch, isNull);
    });

    test('search state can scope matches to a command block', () {
      const state = ShellSearchState(
        query: 'test',
        matches: [
          ShellSearchMatch(row: -1, column: 0, length: 4, blockId: 'b2'),
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
      const invalid = ShellCommandBlock(
        id: 'bad',
        command: 'flutter test',
        startRow: -4,
        endRow: -1,
      );

      expect(block.containsRow(6), isTrue);
      expect(block.containsRow(10), isFalse);
      expect(invalid.isValid, isFalse);
      expect(invalid.containsRow(-2), isFalse);
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

    test('recent items trim text and skip blank entries', () {
      final state = const ShellRecentItemsState()
          .addCommand(
            const ShellRecentCommandEntry(
              command: '   ',
              cwd: '/ignored',
              exitCode: 0,
            ),
          )
          .addCommand(
            const ShellRecentCommandEntry(
              command: '  flutter test  ',
              cwd: '  /repo  ',
              exitCode: 0,
            ),
          )
          .addDirectory(const ShellRecentDirectoryEntry(path: '   '))
          .addDirectory(
            const ShellRecentDirectoryEntry(
              path: '  /repo  ',
              label: '  Repo  ',
            ),
          );

      expect(state.commands, hasLength(1));
      expect(state.commands.single.command, 'flutter test');
      expect(state.commands.single.cwd, '/repo');
      expect(state.directories, hasLength(1));
      expect(state.directories.single.path, '/repo');
      expect(state.directories.single.label, 'Repo');
    });

    test('recent items json skips whitespace-only entries', () {
      final state = ShellRecentItemsState.fromJson({
        'commands': [
          {'command': '   ', 'cwd': '/ignored', 'exitCode': 0},
          {'command': '  dart analyze  ', 'cwd': '  /repo  ', 'exitCode': 0},
        ],
        'directories': [
          {'path': '   ', 'label': 'Blank'},
          {'path': '  /repo  ', 'label': '  Repo  '},
        ],
      });

      expect(state.commands, hasLength(1));
      expect(state.commands.single.command, 'dart analyze');
      expect(state.commands.single.cwd, '/repo');
      expect(state.directories, hasLength(1));
      expect(state.directories.single.path, '/repo');
      expect(state.directories.single.label, 'Repo');
    });

    test('recent items trim and deduplicate restored entries', () {
      final state = ShellRecentItemsState.fromJson({
        'limit': 3,
        'commands': [
          {'command': '  flutter test  ', 'cwd': ' /repo ', 'exitCode': 0},
          {'command': 'flutter test', 'cwd': '/repo', 'exitCode': 1},
          {'command': 'dart analyze', 'cwd': '/repo', 'exitCode': 0},
          {'command': 'dart format', 'cwd': '/repo', 'exitCode': 0},
          {'command': 'flutter test', 'cwd': '/other', 'exitCode': 0},
        ],
        'directories': [
          {'path': ' /repo ', 'label': ' Repo '},
          {'path': '/repo', 'label': 'Duplicate Repo'},
          {'path': '/tmp'},
          {'path': '/var'},
          {'path': '/opt'},
        ],
      });

      expect(
        state.commands.map((entry) => entry.command).toList(growable: false),
        const ['flutter test', 'dart analyze', 'dart format'],
      );
      expect(state.commands.first.cwd, '/repo');
      expect(state.commands.first.exitCode, 0);
      expect(
        state.directories.map((entry) => entry.path).toList(growable: false),
        const ['/repo', '/tmp', '/var'],
      );
      expect(state.directories.first.label, 'Repo');
    });

    test('recent command json rejects fractional exit codes', () {
      final state = ShellRecentItemsState.fromJson({
        'commands': [
          {'command': 'flutter test', 'cwd': '/repo', 'exitCode': 0.0},
          {'command': 'dart analyze', 'cwd': '/repo', 'exitCode': 7.5},
        ],
      });

      expect(state.commands, hasLength(2));
      expect(state.commands.first.exitCode, 0);
      expect(state.commands.last.exitCode, isNull);
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
      expect(ShellRecentItemsState.fromJson({'limit': 2.5}).limit, 50);
      expect(
        ShellRecentItemsState.fromJson({
          'limit': maxShellRecentItems + 1,
        }).limit,
        maxShellRecentItems,
      );
      expect(const ShellRecentItemsState(limit: -1).trimmed().limit, 50);
      expect(
        const ShellRecentItemsState(
          limit: maxShellRecentItems + 1,
        ).trimmed().limit,
        maxShellRecentItems,
      );
    });
  });
}

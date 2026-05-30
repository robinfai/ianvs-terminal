import 'package:app/features/productivity/shell_productivity_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell productivity reducer', () {
    test('records prompt marks and current cwd', () {
      final snapshot = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellPromptMarkEvent(id: 'p1', row: 4, cwd: '/repo'),
      );

      expect(snapshot.state.promptMarks.single.id, 'p1');
      expect(snapshot.currentCwd, '/repo');
      expect(snapshot.recentItems.directories.single.path, '/repo');
    });

    test('ignores invalid prompt mark events', () {
      final blankId = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellPromptMarkEvent(id: '   ', row: 4, cwd: '/repo'),
      );
      final negativeRow = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellPromptMarkEvent(id: 'p1', row: -1, cwd: '/repo'),
      );

      expect(blankId.state.promptMarks, isEmpty);
      expect(blankId.currentCwd, isNull);
      expect(blankId.recentItems.directories, isEmpty);
      expect(negativeRow.state.promptMarks, isEmpty);
      expect(negativeRow.currentCwd, isNull);
      expect(negativeRow.recentItems.directories, isEmpty);
    });

    test('records command finished events as recent commands', () {
      final withCwd = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellCwdChangedEvent('/repo'),
      );
      final snapshot = ShellProductivityReducer.reduce(
        withCwd,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: null,
          exitCode: 0,
        ),
      );

      expect(snapshot.recentItems.commands.single.command, 'flutter test');
      expect(snapshot.recentItems.commands.single.cwd, '/repo');
      expect(snapshot.recentItems.commands.single.succeeded, isTrue);
    });

    test('normalizes blank command and cwd values', () {
      final withoutBlankCwd = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellCwdChangedEvent('   '),
      );
      final withCommand = ShellProductivityReducer.reduce(
        withoutBlankCwd,
        const ShellCommandFinishedEvent(
          command: '  flutter test  ',
          cwd: '  /repo  ',
          exitCode: 0,
        ),
      );
      final afterBlankCommand = ShellProductivityReducer.reduce(
        withCommand,
        const ShellCommandFinishedEvent(
          command: '   ',
          cwd: '  /tmp  ',
          exitCode: 0,
        ),
      );

      expect(withoutBlankCwd.currentCwd, isNull);
      expect(withoutBlankCwd.recentItems.directories, isEmpty);
      expect(withCommand.currentCwd, '/repo');
      expect(withCommand.recentItems.commands.single.command, 'flutter test');
      expect(withCommand.recentItems.commands.single.cwd, '/repo');
      expect(afterBlankCommand.currentCwd, '/tmp');
      expect(afterBlankCommand.recentItems.commands, hasLength(1));
    });

    test('records command output ranges for command output actions', () {
      final snapshot = ShellProductivityReducer.reduce(
        const ShellProductivitySnapshot(),
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 3,
          endRow: 8,
        ),
      );

      expect(snapshot.state.canSelectCommandOutput, isTrue);
      expect(snapshot.state.lastCommandOutputRange()!.commandId, 'cmd-1');
    });
  });
}

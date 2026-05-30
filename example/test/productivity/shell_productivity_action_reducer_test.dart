import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell productivity action reducer', () {
    test('toggle read-only returns updated productivity state', () {
      final result = ShellProductivityActionReducer.reduce(
        state: const ShellProductivityState(),
        actionId: TerminalActionId.toggleReadOnly,
        context: const ShellProductivityActionContext(),
      );

      expect(result, isA<ShellProductivityStateResult>());
      expect((result as ShellProductivityStateResult).state.readOnly, isTrue);
    });

    test('prompt actions return nearest prompt mark', () {
      final result = ShellProductivityActionReducer.reduce(
        state: const ShellProductivityState(
          promptMarks: [
            ShellPromptMark(id: 'p1', row: 2),
            ShellPromptMark(id: 'p2', row: 8),
          ],
        ),
        actionId: TerminalActionId.previousPrompt,
        context: const ShellProductivityActionContext(currentRow: 5),
      );

      expect(result, isA<ShellProductivityPromptResult>());
      expect((result as ShellProductivityPromptResult).prompt!.id, 'p1');
    });

    test('command output action returns last valid output range', () {
      final result = ShellProductivityActionReducer.reduce(
        state: const ShellProductivityState(
          commandOutputRanges: [
            ShellCommandOutputRange(commandId: 'cmd', startRow: 1, endRow: 3),
          ],
        ),
        actionId: TerminalActionId.copyCommandOutput,
        context: const ShellProductivityActionContext(),
      );

      expect(result, isA<ShellProductivityCommandOutputResult>());
      expect(
        (result as ShellProductivityCommandOutputResult).range!.commandId,
        'cmd',
      );
    });

    test('recent directory action returns the first available directory', () {
      final result = ShellProductivityActionReducer.reduce(
        state: const ShellProductivityState(recentDirectories: ['/repo']),
        actionId: TerminalActionId.openRecentDirectory,
        context: const ShellProductivityActionContext(),
      );

      expect(result, isA<ShellProductivityRecentDirectoryResult>());
      expect(
        (result as ShellProductivityRecentDirectoryResult).directory,
        '/repo',
      );
    });

    test('recent directory action skips blank entries', () {
      final result = ShellProductivityActionReducer.reduce(
        state: const ShellProductivityState(
          recentDirectories: ['', '  ', ' /repo '],
        ),
        actionId: TerminalActionId.openRecentDirectory,
        context: const ShellProductivityActionContext(),
      );

      expect(result, isA<ShellProductivityRecentDirectoryResult>());
      expect(
        (result as ShellProductivityRecentDirectoryResult).directory,
        '/repo',
      );
    });
  });
}

import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_block_navigation.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _startedAt = DateTime.utc(2026, 6, 15, 10);
const _scope = CommandBlockScope('session-a', paneId: 'pane-a');

void main() {
  group('CommandBlockNavigationController', () {
    test('moves to previous and next blocks from the selected block', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = _rangeState([
        _running('cmd-1', row: 4),
        _running('cmd-2', row: 8),
        _running('cmd-3', row: 12),
      ]);
      const state = CommandBlockNavigationState(
        scope: _scope,
        selectedBlockId: 'cmd-2',
      );

      final previous = controller.navigate(
        rangeState,
        state: state,
        target: CommandBlockNavigationTarget.previous,
      );
      final next = controller.navigate(
        rangeState,
        state: state,
        target: CommandBlockNavigationTarget.next,
      );

      expect(previous.enabled, isTrue);
      expect(previous.state.selectedBlockId, 'cmd-1');
      expect(previous.intent.blockId, 'cmd-1');
      expect(previous.intent.row, 4);
      expect(next.enabled, isTrue);
      expect(next.state.selectedBlockId, 'cmd-3');
      expect(next.intent.blockId, 'cmd-3');
      expect(next.intent.row, 12);
    });

    test('reports boundary disabled reasons when there is no target', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = _rangeState([
        _running('cmd-1', row: 4),
        _running('cmd-2', row: 8),
      ]);

      final beforeFirst = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(
          scope: _scope,
          selectedBlockId: 'cmd-1',
        ),
        target: CommandBlockNavigationTarget.previous,
      );
      final afterLast = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(
          scope: _scope,
          selectedBlockId: 'cmd-2',
        ),
        target: CommandBlockNavigationTarget.next,
      );

      expect(beforeFirst.enabled, isFalse);
      expect(
        beforeFirst.disabledReason,
        CommandBlockNavigationDisabledReason.noPreviousBlock,
      );
      expect(afterLast.enabled, isFalse);
      expect(
        afterLast.disabledReason,
        CommandBlockNavigationDisabledReason.noNextBlock,
      );
    });

    test('selects the latest failed block in scope', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = _rangeState([
        _completed('cmd-1', row: 4, exitCode: 1),
        _completed('cmd-2', row: 8, exitCode: 0),
        _completed('cmd-3', row: 12, exitCode: 2),
      ]);

      final result = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(scope: _scope),
        target: CommandBlockNavigationTarget.lastFailed,
      );

      expect(result.enabled, isTrue);
      expect(result.state.selectedBlockId, 'cmd-3');
      expect(result.intent.row, 12);
    });

    test('keeps navigation isolated by session and pane', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = CommandBlockRangeState.fromInvocations(
        [
          _invocation('cmd-a', sessionId: 'session-a', paneId: 'pane-a'),
          _invocation('cmd-b', sessionId: 'session-a', paneId: 'pane-b'),
          _invocation('cmd-c', sessionId: 'session-b', paneId: 'pane-a'),
        ],
        rangesByInvocationId: {
          'cmd-a': _ranges(1),
          'cmd-b': _ranges(1),
          'cmd-c': _ranges(1),
        },
      );

      final result = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(
          scope: CommandBlockScope('session-a', paneId: 'pane-b'),
        ),
        target: CommandBlockNavigationTarget.next,
      );

      expect(result.enabled, isTrue);
      expect(result.state.selectedBlockId, 'cmd-b');
      expect(
        result.intent.scope,
        const CommandBlockScope('session-a', paneId: 'pane-b'),
      );
    });

    test('disables navigation when target blocks have no input range', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = CommandBlockRangeState.fromInvocations(
        [_invocation('cmd-1')],
        rangesByInvocationId: {
          'cmd-1': const CommandBlockTerminalRanges(
            outputRange: CommandBlockRowRange(startRow: 5, endRowExclusive: 7),
          ),
        },
      );

      final result = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(scope: _scope),
        target: CommandBlockNavigationTarget.next,
      );

      expect(result.enabled, isFalse);
      expect(
        result.disabledReason,
        CommandBlockNavigationDisabledReason.missingInputRange,
      );
    });

    test('disables navigation when shell integration is unavailable', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = _rangeState([
        _running('cmd-1', row: 4),
      ], shellIntegrationEnabled: false);

      final result = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(scope: _scope),
        target: CommandBlockNavigationTarget.next,
      );

      expect(result.enabled, isFalse);
      expect(
        result.disabledReason,
        CommandBlockNavigationDisabledReason.shellIntegrationDisabled,
      );
    });

    test('read only mode can navigate without terminal writes', () {
      final controller = const CommandBlockNavigationController();
      final rangeState = _rangeState([_running('cmd-1', row: 4)]);

      final result = controller.navigate(
        rangeState,
        state: const CommandBlockNavigationState(scope: _scope),
        target: CommandBlockNavigationTarget.next,
        readOnly: true,
      );

      expect(result.enabled, isTrue);
      expect(
        result.intent.kind,
        CommandBlockNavigationIntentKind.scrollToBlock,
      );
      expect(result.intent.writesToTerminal, isFalse);
    });
  });
}

CommandInvocation _invocation(
  String id, {
  String sessionId = 'session-a',
  String paneId = 'pane-a',
  CommandInvocationStatus status = CommandInvocationStatus.running,
}) {
  return CommandInvocation(
    id: id,
    sessionId: sessionId,
    paneId: paneId,
    command: id,
    startedAt: _startedAt,
    status: status,
  );
}

CommandInvocation _running(String id, {required int row}) {
  return CommandInvocation.running(
    id: id,
    sessionId: 'session-a',
    paneId: 'pane-a',
    command: id,
    startedAt: _startedAt.add(Duration(seconds: row)),
  );
}

CommandInvocation _completed(
  String id, {
  required int row,
  required int exitCode,
}) {
  return CommandInvocation.completed(
    id: id,
    sessionId: 'session-a',
    paneId: 'pane-a',
    command: id,
    startedAt: _startedAt.add(Duration(seconds: row)),
    finishedAt: _startedAt.add(Duration(seconds: row + 1)),
    exitCode: exitCode,
  );
}

CommandBlockRangeState _rangeState(
  List<CommandInvocation> invocations, {
  bool shellIntegrationEnabled = true,
}) {
  return CommandBlockRangeState.fromInvocations(
    invocations,
    rangesByInvocationId: {
      for (final invocation in invocations)
        invocation.id: _ranges(
          invocation.startedAt.difference(_startedAt).inSeconds,
        ),
    },
    shellIntegrationEnabled: shellIntegrationEnabled,
  );
}

CommandBlockTerminalRanges _ranges(int row) {
  return CommandBlockTerminalRanges(
    inputRange: CommandBlockRowRange(startRow: row, endRowExclusive: row + 1),
    outputRange: CommandBlockRowRange(
      startRow: row + 1,
      endRowExclusive: row + 2,
    ),
  );
}

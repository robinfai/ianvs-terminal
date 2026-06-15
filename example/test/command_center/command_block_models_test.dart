import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_lifecycle_degraded_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBlockRangeState', () {
    final startedAt = DateTime.utc(2026, 6, 15, 10);
    final finishedAt = DateTime.utc(2026, 6, 15, 10, 0, 2);

    test('aligns block lifecycle with command invocations', () {
      final state = CommandBlockRangeState.fromInvocations(
        [
          CommandInvocation.completed(
            id: 'cmd-1',
            sessionId: 'session-a',
            paneId: 'pane-a',
            command: 'flutter test',
            cwd: '/repo',
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: 0,
          ),
        ],
        rangesByInvocationId: {
          'cmd-1': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 4, endRowExclusive: 5),
            outputRange: CommandBlockRowRange(startRow: 5, endRowExclusive: 9),
          ),
        },
      );

      final block = state.blockByInvocationId('cmd-1')!;

      expect(block.id, 'cmd-1');
      expect(
        block.scope,
        const CommandBlockScope('session-a', paneId: 'pane-a'),
      );
      expect(block.command, 'flutter test');
      expect(block.cwd, '/repo');
      expect(block.status, CommandInvocationStatus.succeeded);
      expect(block.startedAt, startedAt);
      expect(block.finishedAt, finishedAt);
      expect(block.inputRange!.startRow, 4);
      expect(block.outputRange!.endRowExclusive, 9);
      expect(block.hasCompleteRanges, isTrue);
    });

    test('clips output range before the next command in the same pane', () {
      final state = CommandBlockRangeState.fromInvocations(
        [
          CommandInvocation.completed(
            id: 'cmd-1',
            sessionId: 'session-a',
            paneId: 'pane-a',
            command: 'build',
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: 0,
          ),
          CommandInvocation.running(
            id: 'cmd-2',
            sessionId: 'session-a',
            paneId: 'pane-a',
            command: 'test',
            startedAt: startedAt.add(const Duration(seconds: 3)),
          ),
        ],
        rangesByInvocationId: {
          'cmd-1': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 10, endRowExclusive: 11),
            outputRange: CommandBlockRowRange(
              startRow: 11,
              endRowExclusive: 20,
            ),
          ),
          'cmd-2': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 14, endRowExclusive: 15),
            outputRange: CommandBlockRowRange(
              startRow: 15,
              endRowExclusive: 18,
            ),
          ),
        },
      );

      expect(
        state.blockByInvocationId('cmd-1')!.outputRange,
        const CommandBlockRowRange(startRow: 11, endRowExclusive: 14),
      );
      expect(
        state.blockByInvocationId('cmd-2')!.inputRange,
        const CommandBlockRowRange(startRow: 14, endRowExclusive: 15),
      );
    });

    test('keeps command blocks isolated by session and pane', () {
      final state = CommandBlockRangeState.fromInvocations(
        [
          CommandInvocation.running(
            id: 'cmd-a',
            sessionId: 'session-a',
            paneId: 'pane-a',
            command: 'pwd',
            startedAt: startedAt,
          ),
          CommandInvocation.running(
            id: 'cmd-b',
            sessionId: 'session-a',
            paneId: 'pane-b',
            command: 'ls',
            startedAt: startedAt,
          ),
          CommandInvocation.running(
            id: 'cmd-c',
            sessionId: 'session-b',
            paneId: 'pane-a',
            command: 'git status',
            startedAt: startedAt,
          ),
        ],
        rangesByInvocationId: {
          'cmd-a': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 1, endRowExclusive: 2),
            outputRange: CommandBlockRowRange(startRow: 2, endRowExclusive: 3),
          ),
          'cmd-b': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 1, endRowExclusive: 2),
            outputRange: CommandBlockRowRange(startRow: 2, endRowExclusive: 3),
          ),
          'cmd-c': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 1, endRowExclusive: 2),
            outputRange: CommandBlockRowRange(startRow: 2, endRowExclusive: 3),
          ),
        },
      );

      expect(
        state
            .blocksForScope(
              const CommandBlockScope('session-a', paneId: 'pane-a'),
            )
            .map((block) => block.id),
        ['cmd-a'],
      );
      expect(
        state
            .blocksForScope(
              const CommandBlockScope('session-a', paneId: 'pane-b'),
            )
            .map((block) => block.id),
        ['cmd-b'],
      );
      expect(
        state
            .blocksForScope(
              const CommandBlockScope('session-b', paneId: 'pane-a'),
            )
            .map((block) => block.id),
        ['cmd-c'],
      );
    });

    test('disables output-dependent actions when output range is missing', () {
      final state = CommandBlockRangeState.fromInvocations(
        [
          CommandInvocation.completed(
            id: 'cmd-1',
            sessionId: 'session-a',
            command: 'false',
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: 1,
          ),
        ],
        rangesByInvocationId: {
          'cmd-1': const CommandBlockTerminalRanges(
            inputRange: CommandBlockRowRange(startRow: 4, endRowExclusive: 5),
          ),
        },
      );

      final block = state.blockByInvocationId('cmd-1')!;
      final outputAvailability = block.outputRangeAvailability();
      final degradedState = state.degradedStateForScope(
        const CommandBlockScope('session-a'),
      );

      expect(block.hasOutputRange, isFalse);
      expect(outputAvailability.enabled, isFalse);
      expect(
        outputAvailability.disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
      expect(
        degradedState.action(CommandCenterAction.copyOutput).disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
    });

    test('degrades command block capability when shell integration is off', () {
      final state = CommandBlockRangeState.fromInvocations(
        [
          CommandInvocation.running(
            id: 'cmd-1',
            sessionId: 'session-a',
            command: 'pwd',
            startedAt: startedAt,
          ),
        ],
        rangesByInvocationId: const {},
        shellIntegrationEnabled: false,
      );

      final degradedState = state.degradedStateForScope(
        const CommandBlockScope('session-a'),
      );

      expect(
        degradedState
            .action(CommandCenterAction.showCommandBlocks)
            .disabledReason,
        CommandCenterDisabledActionReason.shellIntegrationDisabled,
      );
    });
  });
}

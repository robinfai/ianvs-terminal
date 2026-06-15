import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_review_entrypoints.dart';
import 'package:app/features/shell/instant_replay_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('CommandReviewEntrypointResolver', () {
    test('replay from here locates a replay frame and target row', () {
      final store = InstantReplayStore();
      store.record(
        'session-a',
        _frameWithRows({
          40: 'earlier output',
          50: 'target failure line',
          51: 'stack trace',
        }),
      );
      final resolver = CommandReviewEntrypointResolver(store: store);

      final result = resolver.resolve(
        CommandReviewEntrypointAction.replayFromHere,
        _block(
          id: 'failed',
          command: 'dart test',
          outputRange: const CommandBlockRowRange(
            startRow: 50,
            endRowExclusive: 60,
          ),
          exitCode: 1,
        ),
      );

      expect(result.enabled, isTrue);
      expect(result.intent.kind, CommandReviewEntrypointIntentKind.replay);
      expect(result.intent.targetRow, 50);
      expect(result.intent.targetFrame?.text, contains('target failure line'));
      expect(result.intent.replayFrames, hasLength(1));
      expect(result.intent.writesToTerminal, isFalse);
      expect(result.intent.pausesLiveTerminal, isFalse);
    });

    test('open in review creates a read-only source', () {
      final store = InstantReplayStore();
      store.record('session-a', _frameWithRows({10: 'review this output'}));
      final resolver = CommandReviewEntrypointResolver(store: store);

      final result = resolver.resolve(
        CommandReviewEntrypointAction.openInReview,
        _block(
          id: 'review',
          command: 'npm test',
          outputRange: const CommandBlockRowRange(
            startRow: 10,
            endRowExclusive: 12,
          ),
        ),
      );

      expect(result.enabled, isTrue);
      expect(result.intent.kind, CommandReviewEntrypointIntentKind.review);
      expect(result.intent.source.readOnly, isTrue);
      expect(result.intent.usesWritableInputController, isFalse);
      expect(result.intent.pausesLiveTerminal, isFalse);
      expect(result.intent.writesToTerminal, isFalse);
    });

    test(
      'failure source metadata points to command details and output range',
      () {
        final store = InstantReplayStore();
        store.record('session-a', _frameWithRows({20: 'failure output'}));
        final resolver = CommandReviewEntrypointResolver(store: store);
        final block = _block(
          id: 'failed',
          command: 'flutter test',
          cwd: '/repo',
          outputRange: const CommandBlockRowRange(
            startRow: 20,
            endRowExclusive: 40,
          ),
          exitCode: 2,
          duration: const Duration(seconds: 4),
        );

        final result = resolver.resolve(
          CommandReviewEntrypointAction.openInReview,
          block,
        );

        final source = result.intent.source;
        expect(source.blockId, 'failed');
        expect(source.command, 'flutter test');
        expect(source.cwd, '/repo');
        expect(source.exitCode, 2);
        expect(source.duration, const Duration(seconds: 4));
        expect(source.outputRange, block.outputRange);
        expect(source.isFailure, isTrue);
      },
    );

    test('disables review when output range or replay frame is missing', () {
      final store = InstantReplayStore();
      final resolver = CommandReviewEntrypointResolver(store: store);

      final missingRange = resolver.resolve(
        CommandReviewEntrypointAction.openInReview,
        _block(id: 'no-output', command: 'date'),
      );
      final missingFrame = resolver.resolve(
        CommandReviewEntrypointAction.replayFromHere,
        _block(
          id: 'no-frame',
          command: 'date',
          outputRange: const CommandBlockRowRange(
            startRow: 10,
            endRowExclusive: 12,
          ),
        ),
      );

      expect(missingRange.enabled, isFalse);
      expect(
        missingRange.disabledReason,
        CommandReviewEntrypointDisabledReason.missingOutputRange,
      );
      expect(missingFrame.enabled, isFalse);
      expect(
        missingFrame.disabledReason,
        CommandReviewEntrypointDisabledReason.missingReplayFrame,
      );
    });

    test('diff entrypoint is explicit but disabled when unavailable', () {
      final store = InstantReplayStore();
      store.record('session-a', _frameWithRows({10: 'output'}));
      final resolver = CommandReviewEntrypointResolver(store: store);

      final disabled = resolver.resolve(
        CommandReviewEntrypointAction.openDiff,
        _block(
          id: 'diff',
          command: 'git diff',
          outputRange: const CommandBlockRowRange(
            startRow: 10,
            endRowExclusive: 11,
          ),
        ),
      );
      final enabled = resolver.resolve(
        CommandReviewEntrypointAction.openDiff,
        _block(
          id: 'diff',
          command: 'git diff',
          outputRange: const CommandBlockRowRange(
            startRow: 10,
            endRowExclusive: 11,
          ),
        ),
        diffAvailable: true,
      );

      expect(disabled.enabled, isFalse);
      expect(
        disabled.disabledReason,
        CommandReviewEntrypointDisabledReason.diffUnavailable,
      );
      expect(enabled.intent.kind, CommandReviewEntrypointIntentKind.diff);
    });
  });
}

CommandBlock _block({
  required String id,
  required String command,
  CommandBlockRowRange? outputRange,
  String? cwd,
  int? exitCode = 0,
  Duration duration = const Duration(seconds: 1),
}) {
  final startedAt = DateTime.utc(2026, 6, 15, 10);
  final finishedAt = startedAt.add(duration);
  return CommandBlock(
    id: id,
    sessionId: 'session-a',
    command: command,
    cwd: cwd,
    startedAt: startedAt,
    finishedAt: finishedAt,
    exitCode: exitCode,
    status: exitCode == 0
        ? CommandInvocationStatus.succeeded
        : CommandInvocationStatus.failed,
    inputRange: const CommandBlockRowRange(startRow: 8, endRowExclusive: 9),
    outputRange: outputRange,
  );
}

TerminalFrameDiff _frameWithRows(Map<int, String> rows) {
  return TerminalFrameDiff(
    frameKind: TerminalFrameKind.snapshot,
    rows: [
      for (final entry in rows.entries)
        TerminalRow(index: entry.key, text: entry.value),
    ],
    cursor: const TerminalCursor(row: 0, col: 0, visible: true),
    viewportRows: 120,
    viewportCols: 80,
    dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

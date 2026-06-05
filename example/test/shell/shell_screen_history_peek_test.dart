import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellHistoryPeekSheet', () {
    testWidgets('history peek lists failed and marked commands', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ShellHistoryPeekSheet(
            blocks: [
              _block(
                id: 'failed',
                command: 'flutter test',
                cwd: '/repo',
                exitCode: 1,
                status: ShellCommandBlockStatus.failed,
              ),
              _block(
                id: 'marked',
                command: 'dart analyze',
                cwd: '/repo/packages/app',
                status: ShellCommandBlockStatus.succeeded,
                markers: const [
                  ShellHistoryMarker(
                    id: 'manual-marker',
                    row: 12,
                    kind: ShellHistoryMarkerKind.manual,
                    label: 'Needs review',
                  ),
                ],
              ),
              _block(
                id: 'plain',
                command: 'echo ok',
                status: ShellCommandBlockStatus.succeeded,
              ),
            ],
          ),
        ),
      );

      expect(find.text('History Peek'), findsOneWidget);
      expect(find.text('flutter test'), findsOneWidget);
      expect(find.text('dart analyze'), findsOneWidget);
      expect(find.text('echo ok'), findsNothing);
      expect(find.text('/repo'), findsOneWidget);
      expect(find.text('/repo/packages/app'), findsOneWidget);
      expect(find.text('exit 1'), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
    });

    testWidgets('empty blocks render an empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(const ShellHistoryPeekSheet(blocks: <ShellCommandBlock>[])),
      );

      expect(find.text('History Peek'), findsOneWidget);
      expect(find.text('No failed or marked commands yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('close button calls onClose', (tester) async {
      var closeCount = 0;

      await tester.pumpWidget(
        _wrap(
          ShellHistoryPeekSheet(
            blocks: [
              _block(id: 'failed', status: ShellCommandBlockStatus.failed),
            ],
            onClose: () => closeCount += 1,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Close History Peek'));
      await tester.pump();

      expect(closeCount, 1);
    });

    testWidgets('theme tokens fallback when extension is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: ShellHistoryPeekSheet(
              blocks: [
                _block(
                  id: 'failed',
                  command: 'npm test',
                  status: ShellCommandBlockStatus.failed,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('History Peek'), findsOneWidget);
      expect(find.text('npm test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ShellCommandBlockShellHookReducer', () {
    test(
      'creates block without prompt offset from visible viewport end row',
      () {
        const scrollbackMaxOffset = 4;
        final viewportEndRow = shellCommandBlockVisibleViewportEndRow(
          viewportStartRow: 40,
          viewportRows: 8,
        );

        expect(viewportEndRow, 47);
        expect(viewportEndRow, isNot(scrollbackMaxOffset));

        var snapshot = const ShellCommandBlockSnapshot();

        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'precmd.pwd',
          cwd: '/repo',
        );
        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'preexec',
          command: 'flutter test',
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
          ],
        );
        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'command_finished',
          command: 'flutter test',
          exitCode: 1,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
          ],
          viewportEndRow: viewportEndRow,
        );

        expect(snapshot.blocks, hasLength(1));
        final block = snapshot.blocks.single;
        expect(block.command, 'flutter test');
        expect(block.cwd, '/repo');
        expect(block.status, ShellCommandBlockStatus.failed);
        expect(block.outputRange.commandRow, 40);
        expect(block.outputRange.outputStartRow, 41);
        expect(block.outputRange.outputEndRow, 47);
      },
    );

    test('visible viewport end row is absent for an empty viewport', () {
      expect(
        shellCommandBlockVisibleViewportEndRow(
          viewportStartRow: 40,
          viewportRows: 0,
        ),
        isNull,
      );
    });

    test(
      'does not create block from old prompt marks without a command start',
      () {
        final snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: const ShellCommandBlockSnapshot(),
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'command_finished',
          command: 'flutter test',
          exitCode: 1,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 10, cwd: '/old'),
            TerminalShellPromptMark(scrollbackOffset: 20, cwd: '/old'),
          ],
          viewportEndRow: 47,
        );

        expect(snapshot.blocks, isEmpty);
      },
    );

    test('does not append duplicate block for repeated finish events', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'flutter test',
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
        ],
      );

      for (var index = 0; index < 2; index += 1) {
        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'command_finished',
          command: 'flutter test',
          exitCode: 1,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
          ],
          viewportEndRow: 47,
        );
      }

      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.blocks.single.id, 'session-1:command:40:47');
    });

    test('returns empty snapshot when flags are off', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: [
          _block(id: 'existing', status: ShellCommandBlockStatus.failed),
        ],
      );

      final next = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: CommandBlocksHistoryFeatureFlags.disabled,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'flutter test',
        exitCode: 1,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
        ],
        viewportEndRow: 47,
      );

      expect(next.blocks, isEmpty);
    });
  });

  group('InstantReplayCommandBlockSource', () {
    test('action resolver uses the latest current session command block', () {
      final source = resolveInstantReplayCommandBlockActionSource(
        actionId: TerminalActionId.replayFromCommandBlock,
        flags: _commandBlocksFlags,
        currentSessionId: 'session-1',
        commandBlocks: [
          _block(id: 'older', command: 'dart analyze'),
          _block(
            id: 'latest',
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 1,
            status: ShellCommandBlockStatus.failed,
          ),
        ],
      );

      expect(source, isNotNull);
      expect(source!.commandBlockId, 'latest');
      expect(source.command, 'flutter test');
      expect(source.cwd, '/repo');
      expect(source.statusLabel, 'exit 1');
      expect(source.replayHeaderLabel, 'Replay from: flutter test');
    });

    test('action resolver ignores non replay command block actions', () {
      final source = resolveInstantReplayCommandBlockActionSource(
        actionId: TerminalActionId.instantReplay,
        flags: _commandBlocksFlags,
        currentSessionId: 'session-1',
        commandBlocks: [_block(id: 'latest')],
      );

      expect(source, isNull);
    });

    test(
      'action resolver returns null when review entrypoints are disabled',
      () {
        final source = resolveInstantReplayCommandBlockActionSource(
          actionId: TerminalActionId.replayFromCommandBlock,
          flags: _commandBlocksWithoutReviewFlags,
          currentSessionId: 'session-1',
          commandBlocks: [_block(id: 'latest')],
        );

        expect(source, isNull);
      },
    );

    test('builds replay header label from command block', () {
      final source = InstantReplayCommandBlockSource.fromBlock(
        _block(
          id: 'failed',
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
          status: ShellCommandBlockStatus.failed,
        ),
      );

      expect(source.commandBlockId, 'failed');
      expect(source.command, 'flutter test');
      expect(source.cwd, '/repo');
      expect(source.statusLabel, 'exit 1');
      expect(source.replayHeaderLabel, 'Replay from: flutter test');
    });
  });
}

const _commandBlocksFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  historyPeek: true,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: true,
  outputDiff: true,
);

const _commandBlocksWithoutReviewFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  historyPeek: true,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: false,
  outputDiff: true,
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildIanvsTerminalTheme(Brightness.light),
    home: Scaffold(body: child),
  );
}

ShellCommandBlock _block({
  required String id,
  String command = 'flutter test',
  String? cwd,
  int? exitCode,
  ShellCommandBlockStatus status = ShellCommandBlockStatus.succeeded,
  List<ShellHistoryMarker> markers = const <ShellHistoryMarker>[],
}) {
  return ShellCommandBlock.withMarkers(
    id: id,
    command: command,
    cwd: cwd,
    exitCode: exitCode,
    status: status,
    outputRange: const ShellCommandBlockRange(
      commandRow: 10,
      outputStartRow: 11,
      outputEndRow: 14,
    ),
    markers: markers,
  );
}

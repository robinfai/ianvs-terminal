import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  group('ShellHistoryPeekSheet', () {
    testWidgets('history peek lists captured commands by default', (
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
      expect(find.text('echo ok'), findsOneWidget);
      expect(find.text('/repo'), findsOneWidget);
      expect(find.text('/repo/packages/app'), findsOneWidget);
      expect(find.text('exit 1'), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
    });

    testWidgets('filters and searches command history', (tester) async {
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

      await tester.tap(
        find.byKey(const Key('shell-history-peek-filter-Failed')),
      );
      await tester.pump();

      expect(find.text('flutter test'), findsOneWidget);
      expect(find.text('dart analyze'), findsNothing);
      expect(find.text('echo ok'), findsNothing);

      await tester.tap(find.byKey(const Key('shell-history-peek-filter-All')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('shell-history-peek-search')),
        'analyze',
      );
      await tester.pump();

      expect(find.text('flutter test'), findsNothing);
      expect(find.text('dart analyze'), findsOneWidget);
      expect(find.text('echo ok'), findsNothing);
    });

    testWidgets('empty blocks render an empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(const ShellHistoryPeekSheet(blocks: <ShellCommandBlock>[])),
      );

      expect(find.text('History Peek'), findsOneWidget);
      expect(find.text('No commands captured yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('visible block predicate only accepts failed or marked blocks', () {
      expect(
        shellHistoryPeekHasVisibleBlocks([
          _block(id: 'plain', status: ShellCommandBlockStatus.succeeded),
        ]),
        isFalse,
      );
      expect(
        shellHistoryPeekHasVisibleBlocks([
          _block(id: 'failed', status: ShellCommandBlockStatus.failed),
        ]),
        isTrue,
      );
      expect(
        shellHistoryPeekHasVisibleBlocks([
          _block(
            id: 'marked',
            status: ShellCommandBlockStatus.succeeded,
            markers: const [
              ShellHistoryMarker(
                id: 'manual-marker',
                row: 12,
                kind: ShellHistoryMarkerKind.manual,
              ),
            ],
          ),
        ]),
        isTrue,
      );
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

    testWidgets('narrow constraints keep sheet within available width', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SizedBox(
              width: 180,
              height: 360,
              child: ShellHistoryPeekSheet(
                maxWidth: shellHistoryPeekWidthForAvailableWidth(180),
                blocks: [
                  _block(
                    id: 'failed',
                    command: 'flutter test --very-long-filter-name',
                    cwd: '/repo/packages/example',
                    exitCode: 1,
                    status: ShellCommandBlockStatus.failed,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final sheetSize = tester.getSize(
        find.byKey(const Key('shell-history-peek-sheet')),
      );
      expect(sheetSize.width, lessThanOrEqualTo(180));
      expect(tester.takeException(), isNull);
    });

    test('side pane width keeps terminal space on narrow layouts', () {
      expect(shellHistoryPeekSidePaneWidthForAvailableWidth(700), 320);
      expect(shellHistoryPeekSidePaneWidthForAvailableWidth(500), 220);
      expect(shellHistoryPeekSidePaneWidthForAvailableWidth(400), 0);
      expect(shellHistoryPeekSidePaneWidthForAvailableWidth(260), 0);
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
          commandStartRow: 40,
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
      'preexec fallback uses absolute viewport row instead of prompt mark offset',
      () {
        const frame = terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(index: 0, text: ''),
            terminal.TerminalRow(index: 1, text: 'old output'),
            terminal.TerminalRow(index: 2, text: ''),
            terminal.TerminalRow(index: 3, text: r'$ flutter test'),
          ],
          cursor: terminal.TerminalCursor(row: 3, col: 2, visible: true),
          dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 4)],
          viewportRows: 8,
          viewportCols: 80,
          viewportStartRow: 100,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 4,
        );
        final commandStartRow = shellCommandBlockCommandStartRowForFrame(frame);

        expect(commandStartRow, 103);
        expect(commandStartRow, isNot(1));

        var snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: const ShellCommandBlockSnapshot(),
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'preexec',
          command: 'flutter test',
          commandStartRow: commandStartRow,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 1, cwd: '/repo'),
          ],
        );
        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'command_finished',
          command: 'flutter test',
          exitCode: 0,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 1, cwd: '/repo'),
          ],
          viewportEndRow: 107,
        );

        expect(snapshot.blocks, hasLength(1));
        expect(snapshot.blocks.single.outputRange.commandRow, 103);
        expect(snapshot.blocks.single.outputRange.outputStartRow, 104);
        expect(snapshot.blocks.single.outputRange.outputEndRow, 107);
      },
    );

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

    test('does not use fallback prompt mark as explicit-end start', () {
      final snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'flutter test',
        exitCode: 1,
        promptScrollbackOffset: 48,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 1, cwd: '/old'),
        ],
        viewportEndRow: 55,
      );

      expect(snapshot.blocks, isEmpty);
    });

    test(
      'does not append duplicate block when explicit end finish repeats',
      () {
        var snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: const ShellCommandBlockSnapshot(),
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'preexec',
          command: 'flutter test',
          commandStartRow: 40,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
          ],
        );

        for (var i = 0; i < 2; i += 1) {
          snapshot = ShellCommandBlockShellHookReducer.reduce(
            snapshot: snapshot,
            flags: _commandBlocksFlags,
            sessionId: 'session-1',
            hook: 'command_finished',
            command: 'flutter test',
            exitCode: 0,
            promptScrollbackOffset: 48,
            promptMarks: const [
              TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
            ],
            viewportEndRow: 55,
          );
        }

        expect(snapshot.blocks, hasLength(1));
        expect(snapshot.blocks.single.outputRange.commandRow, 40);
        expect(snapshot.blocks.single.outputRange.outputEndRow, 47);
      },
    );

    test(
      'does not append duplicate block when repeated finish sees new viewport end',
      () {
        var snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: const ShellCommandBlockSnapshot(),
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'preexec',
          command: 'flutter test',
          commandStartRow: 40,
          promptMarks: const [
            TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
          ],
        );

        for (final viewportEndRow in const [47, 55]) {
          snapshot = ShellCommandBlockShellHookReducer.reduce(
            snapshot: snapshot,
            flags: _commandBlocksFlags,
            sessionId: 'session-1',
            hook: 'command_finished',
            command: viewportEndRow == 47
                ? 'flutter test'
                : 'flutter test --rerun',
            exitCode: 1,
            promptMarks: const [
              TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
            ],
            viewportEndRow: viewportEndRow,
          );
        }

        expect(snapshot.blocks, hasLength(1));
        expect(snapshot.blocks.single.id, 'session-1:command:40:47');
      },
    );

    test('clears pending prompt after finish without end prompt', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'flutter test',
        commandStartRow: 40,
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
        viewportEndRow: 47,
      );

      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.lastPrompt, isNull);
    });

    test(
      'cleared snapshot allows same start and command to generate again',
      () {
        ShellCommandBlockSnapshot runOnce() {
          var snapshot = ShellCommandBlockShellHookReducer.reduce(
            snapshot: const ShellCommandBlockSnapshot(),
            flags: _commandBlocksFlags,
            sessionId: 'session-1',
            hook: 'preexec',
            command: 'flutter test',
            commandStartRow: 40,
            promptMarks: const [
              TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
            ],
          );
          return ShellCommandBlockShellHookReducer.reduce(
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

        final first = runOnce();
        final cleared = shellCommandBlockSnapshotAfterScrollbackClear(first);
        final second = runOnce();

        expect(first.blocks, hasLength(1));
        expect(cleared.blocks, isEmpty);
        expect(second.blocks, hasLength(1));
        expect(second.blocks.single.id, first.blocks.single.id);
      },
    );

    test('cwd event with unchanged cwd returns the same snapshot', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        currentCwd: '/repo',
      );

      final next = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'cwd',
        cwd: '/repo',
      );

      expect(next, same(snapshot));
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
    test(
      'action execution opens replay for the latest command block',
      () async {
        var openCount = 0;
        InstantReplayCommandBlockSource? openedSource;

        final executed = await executeInstantReplayCommandBlockAction(
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
          openReplay: (source) async {
            openCount += 1;
            openedSource = source;
          },
        );

        expect(executed, isTrue);
        expect(openCount, 1);
        expect(openedSource, isNotNull);
        expect(openedSource!.commandBlockId, 'latest');
        expect(openedSource!.command, 'flutter test');
        expect(openedSource!.cwd, '/repo');
        expect(openedSource!.statusLabel, 'exit 1');
        expect(openedSource!.replayHeaderLabel, 'Replay from: flutter test');
      },
    );

    test('action execution ignores non replay command block actions', () async {
      var openCount = 0;

      final executed = await executeInstantReplayCommandBlockAction(
        actionId: TerminalActionId.instantReplay,
        flags: _commandBlocksFlags,
        currentSessionId: 'session-1',
        commandBlocks: [_block(id: 'latest')],
        openReplay: (_) async {
          openCount += 1;
        },
      );

      expect(executed, isFalse);
      expect(openCount, 0);
    });

    test('action execution ignores disabled review entrypoints', () async {
      var openCount = 0;

      final executed = await executeInstantReplayCommandBlockAction(
        actionId: TerminalActionId.replayFromCommandBlock,
        flags: _commandBlocksWithoutReviewFlags,
        currentSessionId: 'session-1',
        commandBlocks: [_block(id: 'latest')],
        openReplay: (_) async {
          openCount += 1;
        },
      );

      expect(executed, isFalse);
      expect(openCount, 0);
    });

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

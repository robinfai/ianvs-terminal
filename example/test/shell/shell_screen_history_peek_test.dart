import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
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
    test('command end row tracks cursor instead of viewport bottom', () {
      const frame = terminal.TerminalFrameDiff(
        rows: [
          terminal.TerminalRow(index: 5, text: '/Users/dev'),
          terminal.TerminalRow(index: 6, text: ''),
        ],
        cursor: terminal.TerminalCursor(row: 6, col: 0, visible: true),
        dirtyRanges: [terminal.TerminalDirtyRange(start: 5, end: 7)],
        viewportRows: 40,
        viewportCols: 80,
        viewportStartRow: 10,
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      );

      expect(shellCommandBlockCommandEndRowForFrame(frame), 15);
      expect(
        shellCommandBlockCommandEndRowForFrame(
          const terminal.TerminalFrameDiff(
            rows: [terminal.TerminalRow(index: 6, text: 'partial')],
            cursor: terminal.TerminalCursor(row: 6, col: 7, visible: true),
            dirtyRanges: [terminal.TerminalDirtyRange(start: 6, end: 7)],
            viewportRows: 40,
            viewportCols: 80,
            viewportStartRow: 10,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        ),
        16,
      );
    });

    test('command start row prefers the submitted command line', () {
      const frame = terminal.TerminalFrameDiff(
        rows: [
          terminal.TerminalRow(index: 0, text: '~ > pwd'),
          terminal.TerminalRow(index: 1, text: '/Users/robinfai'),
          terminal.TerminalRow(index: 2, text: '~ > echo 123'),
          terminal.TerminalRow(index: 3, text: '123'),
          terminal.TerminalRow(index: 4, text: '~ >'),
          terminal.TerminalRow(index: 5, text: ''),
        ],
        cursor: terminal.TerminalCursor(row: 5, col: 0, visible: true),
        dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 6)],
        viewportRows: 20,
        viewportCols: 93,
        viewportStartRow: 40,
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      );

      expect(
        shellCommandBlockCommandStartRowForFrame(frame, command: 'echo 123'),
        42,
      );
      expect(shellCommandBlockCommandStartRowForFrame(frame), 44);
    });

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

    test('creates a minimal block when finish arrives before output frame', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'echo done',
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
        command: 'echo done',
        exitCode: 0,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
        ],
        viewportEndRow: 40,
      );

      expect(snapshot.blocks, hasLength(1));
      final block = snapshot.blocks.single;
      expect(block.outputRange.commandRow, 40);
      expect(block.outputRange.outputStartRow, 41);
      expect(block.outputRange.outputEndRow, 41);
    });

    test('accepts Warp-style shell hook names', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'Preexec',
        command: 'ls-al',
        commandStartRow: 40,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'CommandFinished',
        command: 'ls-al',
        exitCode: 127,
        viewportEndRow: 41,
      );

      expect(snapshot.blocks, hasLength(1));
      final block = snapshot.blocks.single;
      expect(block.command, 'ls-al');
      expect(block.status, ShellCommandBlockStatus.failed);
      expect(block.outputRange.commandRow, 40);
      expect(block.outputRange.outputStartRow, 41);
      expect(block.outputRange.outputEndRow, 41);
    });

    test('next preexec expands previous minimal fallback block', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'ls -la',
        commandStartRow: 40,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'ls -la',
        exitCode: 0,
        viewportEndRow: 40,
      );

      expect(snapshot.blocks.single.outputRange.outputEndRow, 41);

      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'pwd',
        commandStartRow: 50,
      );

      expect(snapshot.blocks, hasLength(2));
      final previous = snapshot.blocks.first;
      final running = snapshot.blocks.last;
      expect(previous.command, 'ls -la');
      expect(previous.outputRange.commandRow, 40);
      expect(previous.outputRange.outputStartRow, 41);
      expect(previous.outputRange.outputEndRow, 49);
      expect(running.command, 'pwd');
      expect(running.status, ShellCommandBlockStatus.running);
      expect(running.outputRange.commandRow, 50);
      expect(snapshot.lastPrompt?.row, 50);
    });

    test(
      'precmd prompt offset expands previous minimal fallback block and seeds prompt',
      () {
        var snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: const ShellCommandBlockSnapshot(),
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'preexec',
          command: 'ls -la',
          commandStartRow: 40,
        );
        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'command_finished',
          command: 'ls -la',
          exitCode: 0,
          viewportEndRow: 40,
        );

        expect(snapshot.blocks.single.outputRange.outputEndRow, 41);
        expect(snapshot.lastPrompt, isNull);

        snapshot = ShellCommandBlockShellHookReducer.reduce(
          snapshot: snapshot,
          flags: _commandBlocksFlags,
          sessionId: 'session-1',
          hook: 'precmd',
          cwd: '/repo',
          promptScrollbackOffset: 50,
        );

        expect(snapshot.blocks.single.outputRange.commandRow, 40);
        expect(snapshot.blocks.single.outputRange.outputEndRow, 49);
        expect(snapshot.lastPrompt?.row, 50);
        expect(snapshot.lastPrompt?.cwd, '/repo');
      },
    );

    test('precmd prompt row fallback uses the cursor row from the frame', () {
      const frame = terminal.TerminalFrameDiff(
        rows: [
          terminal.TerminalRow(index: 0, text: 'total 7600'),
          terminal.TerminalRow(index: 1, text: ''),
        ],
        cursor: terminal.TerminalCursor(row: 1, col: 0, visible: true),
        dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 2)],
        viewportRows: 20,
        viewportCols: 93,
        viewportStartRow: 49,
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      );
      final promptRow = shellCommandBlockPromptRowForFrame(frame);

      expect(promptRow, 50);
      expect(
        promptRow,
        isNot(
          shellCommandBlockVisibleViewportEndRow(
            viewportStartRow: 49,
            viewportRows: 20,
          ),
        ),
      );

      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'll',
        commandStartRow: 40,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'll',
        exitCode: 0,
        viewportEndRow: 40,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'precmd',
        promptScrollbackOffset: promptRow,
      );

      expect(snapshot.blocks.single.outputRange.outputEndRow, 49);
      expect(snapshot.lastPrompt?.row, 50);
    });

    test('command finish expands previous minimal fallback block', () {
      final snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: ShellCommandBlockSnapshot.withBlocks(
          blocks: const [
            ShellCommandBlock(
              id: 'session-1:command:40:41',
              command: 'ls -la',
              outputRange: ShellCommandBlockRange(
                commandRow: 40,
                outputStartRow: 41,
                outputEndRow: 41,
              ),
              status: ShellCommandBlockStatus.succeeded,
            ),
          ],
          lastPrompt: ShellPromptMark(id: 'session-1:prompt:50', row: 50),
        ),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'pwd',
        exitCode: 0,
        viewportEndRow: 51,
      );

      expect(snapshot.blocks, hasLength(2));
      expect(snapshot.blocks.first.command, 'ls -la');
      expect(snapshot.blocks.first.outputRange.outputEndRow, 49);
      expect(snapshot.blocks.last.command, 'pwd');
    });

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
        expect(snapshot.blocks.single.id, 'session-1:command:40');
      },
    );

    test('keeps block id stable when next command resizes previous output', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'ls',
        commandStartRow: 3,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 3, cwd: '/repo'),
        ],
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'ls',
        exitCode: 0,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 3, cwd: '/repo'),
        ],
        viewportEndRow: 9,
      );

      final firstId = snapshot.blocks.single.id;

      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'll',
        commandStartRow: 40,
        promptMarks: const [
          TerminalShellPromptMark(scrollbackOffset: 40, cwd: '/repo'),
        ],
      );

      expect(snapshot.blocks.first.id, firstId);
      expect(snapshot.blocks.first.outputRange.outputEndRow, 39);
    });

    test('ignores prompt-prefixed command hook duplicates', () {
      var snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: const ShellCommandBlockSnapshot(),
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: 'll',
        commandStartRow: 42,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: 'll',
        exitCode: 0,
        viewportEndRow: 43,
      );

      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'preexec',
        command: '?? robinfai? ~ ???? ? 10:39 ?? ll',
        commandStartRow: 44,
      );
      snapshot = ShellCommandBlockShellHookReducer.reduce(
        snapshot: snapshot,
        flags: _commandBlocksFlags,
        sessionId: 'session-1',
        hook: 'command_finished',
        command: '?? robinfai? ~ ???? ? 10:39 ?? ll',
        exitCode: 0,
        viewportEndRow: 73,
      );

      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.blocks.single.command, 'll');
    });

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

  group('ShellCommandBlockViewModelBuilder', () {
    test('finished preview capture remains open until prompt boundary', () {
      final block = _block(id: 'll', command: 'll', cwd: '/Users/robinfai');

      final partial = shellCommandBlockFinishedPreviewCaptureForRows(
        block: block,
        rows: const [terminal.TerminalRow(index: 0, text: 'total 7600')],
        isLatestBlock: true,
      );

      expect(partial.rows.map((row) => row.text), ['total 7600']);
      expect(partial.removeTarget, isFalse);

      final complete = shellCommandBlockFinishedPreviewCaptureForRows(
        block: block,
        rows: const [
          terminal.TerminalRow(index: 0, text: 'total 7600'),
          terminal.TerminalRow(index: 1, text: 'drwxr-xr-x alpha.txt'),
          terminal.TerminalRow(index: 2, text: 'robinfai ~ 10:39 ❯ ll'),
        ],
        isLatestBlock: true,
      );

      expect(complete.rows.map((row) => row.text), [
        'total 7600',
        'drwxr-xr-x alpha.txt',
      ]);
      expect(complete.removeTarget, isTrue);

      final stale = shellCommandBlockFinishedPreviewCaptureForRows(
        block: block,
        rows: const [terminal.TerminalRow(index: 0, text: 'late output')],
        isLatestBlock: false,
      );

      expect(stale.rows, isEmpty);
      expect(stale.removeTarget, isTrue);
    });

    test(
      'captures finished output from the current frame for long commands',
      () {
        const block = ShellCommandBlock(
          id: 'session-1:command:40',
          command: 'ls -lhF',
          cwd: '/Users/robinfai',
          status: ShellCommandBlockStatus.succeeded,
          outputRange: ShellCommandBlockRange(
            commandRow: 40,
            outputStartRow: 41,
            outputEndRow: 41,
          ),
        );
        final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

        final captured = shellCommandBlockFinishedPreviewRowsForCurrentFrame(
          snapshot: snapshot,
          frame: const terminal.TerminalFrameDiff(
            rows: [
              terminal.TerminalRow(
                index: 0,
                text: 'drwx------@ 26 robinfai  staff   832B Documents/',
              ),
              terminal.TerminalRow(
                index: 1,
                text: '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
              ),
              terminal.TerminalRow(
                index: 2,
                text: '?? robinfai? ~ ???? ? 12:46 ??',
              ),
            ],
            cursor: terminal.TerminalCursor(row: 2, col: 0, visible: true),
            dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 3)],
            viewportRows: 20,
            viewportCols: 93,
            viewportStartRow: 70,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

        expect(captured[block.id]?.map((row) => row.text), [
          'drwx------@ 26 robinfai  staff   832B Documents/',
          '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
        ]);
      },
    );

    test(
      'finished preview stops at prompt row boundary without prompt text',
      () {
        const block = ShellCommandBlock(
          id: 'session-1:command:40',
          command: 'll',
          cwd: '/Users/robinfai',
          status: ShellCommandBlockStatus.succeeded,
          outputRange: ShellCommandBlockRange(
            commandRow: 40,
            outputStartRow: 41,
            outputEndRow: 49,
          ),
        );
        final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

        final captured = shellCommandBlockFinishedPreviewRowsForCurrentFrame(
          snapshot: snapshot,
          endPromptRow: 50,
          frame: const terminal.TerminalFrameDiff(
            rows: [
              terminal.TerminalRow(index: 0, text: 'total 7600'),
              terminal.TerminalRow(
                index: 8,
                text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
              ),
              terminal.TerminalRow(index: 9, text: 'not a recognizable prompt'),
              terminal.TerminalRow(index: 10, text: 'next command output'),
            ],
            cursor: terminal.TerminalCursor(row: 9, col: 0, visible: true),
            dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 11)],
            viewportRows: 20,
            viewportCols: 93,
            viewportStartRow: 41,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

        expect(captured[block.id]?.map((row) => row.text), [
          'total 7600',
          'drwxr-xr-x  10 robinfai  staff   320B work/',
        ]);
      },
    );

    test('finished preview target closes when frame reaches prompt row', () {
      const beforePrompt = terminal.TerminalFrameDiff(
        rows: [
          terminal.TerminalRow(index: 0, text: 'total 7600'),
          terminal.TerminalRow(index: 8, text: 'work'),
        ],
        cursor: terminal.TerminalCursor(row: 8, col: 4, visible: true),
        dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 9)],
        viewportRows: 20,
        viewportCols: 93,
        viewportStartRow: 41,
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      );
      const atPrompt = terminal.TerminalFrameDiff(
        rows: [
          terminal.TerminalRow(index: 9, text: 'not a recognizable prompt'),
        ],
        cursor: terminal.TerminalCursor(row: 9, col: 0, visible: true),
        dirtyRanges: [terminal.TerminalDirtyRange(start: 9, end: 10)],
        viewportRows: 20,
        viewportCols: 93,
        viewportStartRow: 41,
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      );

      expect(
        shellCommandBlockFrameReachedPromptBoundary(
          frame: beforePrompt,
          endPromptRow: 50,
        ),
        isFalse,
      );
      expect(
        shellCommandBlockFrameReachedPromptBoundary(
          frame: atPrompt,
          endPromptRow: 50,
        ),
        isTrue,
      );
    });

    test('keeps long listing rows for ll output', () {
      const block = ShellCommandBlock(
        id: 'session-1:command:0',
        command: 'll',
        cwd: '/Users/robinfai',
        status: ShellCommandBlockStatus.succeeded,
        outputRange: ShellCommandBlockRange(
          commandRow: 0,
          outputStartRow: 1,
          outputEndRow: 30,
        ),
      );
      final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

      final captured = shellCommandBlockFinishedPreviewRowsForCurrentFrame(
        snapshot: snapshot,
        frame: const terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text:
                  'drwx------+  4 robinfai  staff   128B Mar 16 15:42 Pictures/',
            ),
            terminal.TerminalRow(
              index: 1,
              text:
                  'drwxr-xr-x@  4 robinfai  staff   128B Apr  1 14:39 PyCharmMiscProject/',
            ),
            terminal.TerminalRow(
              index: 2,
              text: '󰀵 robinfai ~   13:01  ❯',
            ),
          ],
          cursor: terminal.TerminalCursor(row: 2, col: 0, visible: true),
          dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 3)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 11,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(captured[block.id]?.map((row) => row.text), [
        'drwx------+  4 robinfai  staff   128B Mar 16 15:42 Pictures/',
        'drwxr-xr-x@  4 robinfai  staff   128B Apr  1 14:39 PyCharmMiscProject/',
      ]);
    });

    test(
      'falls back to recently modified rows when output scrolls above command row',
      () {
        final submittedAt = DateTime(2026, 6, 10, 13);
        final oldOutputAt = submittedAt.subtract(const Duration(seconds: 1));
        final commandOutputAt = submittedAt.add(
          const Duration(milliseconds: 1),
        );
        const block = ShellCommandBlock(
          id: 'session-1:command:10',
          command: 'll',
          cwd: '/Users/robinfai',
          status: ShellCommandBlockStatus.succeeded,
          outputRange: ShellCommandBlockRange(
            commandRow: 10,
            outputStartRow: 11,
            outputEndRow: 12,
          ),
        );

        final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
          command: 'll',
          commandRow: 10,
          submittedAt: submittedAt,
          frame: terminal.TerminalFrameDiff(
            rows: [
              terminal.TerminalRow(
                index: 0,
                text: 'stale previous output',
                modifiedAt: oldOutputAt,
              ),
              terminal.TerminalRow(
                index: 1,
                text: 'total 7600',
                modifiedAt: commandOutputAt,
              ),
              terminal.TerminalRow(
                index: 2,
                text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
                modifiedAt: commandOutputAt,
              ),
              const terminal.TerminalRow(index: 18, text: ''),
              terminal.TerminalRow(
                index: 19,
                text: '󰀵 robinfai ~   13:05  ❯',
                modifiedAt: commandOutputAt,
              ),
            ],
            cursor: const terminal.TerminalCursor(
              row: 19,
              col: 32,
              visible: true,
            ),
            dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 20)],
            viewportRows: 20,
            viewportCols: 93,
            viewportStartRow: 13,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

        expect(
          shellCommandBlockOutputRowsFrom(block, rows).map((row) => row.text),
          ['total 7600', 'drwxr-xr-x  10 robinfai  staff   320B work/'],
        );
      },
    );

    test('ignores refreshed rows before the submitted command row', () {
      final submittedAt = DateTime(2026, 6, 10, 13, 15);
      final refreshedAt = submittedAt.add(const Duration(milliseconds: 1));

      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: 'echo 123',
        commandRow: 43,
        submittedAt: submittedAt,
        frame: terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text:
                  'drwxr-xr-x@  5 robinfai  staff   160B Mar 30 22:38 background_agent_cli/',
              modifiedAt: refreshedAt,
            ),
            terminal.TerminalRow(
              index: 1,
              text: 'drwxr-xr-x@  3 robinfai  staff    96B Mar 16 17:12 bin/',
              modifiedAt: refreshedAt,
            ),
            terminal.TerminalRow(
              index: 18,
              text: '123',
              modifiedAt: refreshedAt,
            ),
          ],
          cursor: const terminal.TerminalCursor(row: 19, col: 0, visible: true),
          dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 20)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 26,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(rows.map((row) => row.text), ['123']);
    });

    test('keeps visible output when row timestamps lag submitted time', () {
      final submittedAt = DateTime(2026, 6, 10, 13, 30);
      final outputAt = submittedAt.subtract(const Duration(milliseconds: 1));
      const block = ShellCommandBlock(
        id: 'session-1:command:9',
        command: 'll',
        cwd: '/Users/robinfai',
        status: ShellCommandBlockStatus.succeeded,
        outputRange: ShellCommandBlockRange(
          commandRow: 9,
          outputStartRow: 10,
          outputEndRow: 39,
        ),
      );
      final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

      final captured = shellCommandBlockFinishedPreviewRowsForCurrentFrame(
        snapshot: snapshot,
        submittedAt: submittedAt,
        frame: terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text: 'drwx------+  4 robinfai  staff   128B Pictures/',
              modifiedAt: outputAt,
            ),
            terminal.TerminalRow(
              index: 1,
              text: 'drwxr-xr-x+  4 robinfai  staff   128B Public/',
              modifiedAt: outputAt,
            ),
          ],
          cursor: const terminal.TerminalCursor(row: 1, col: 0, visible: true),
          dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 2)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 20,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(captured[block.id]?.map((row) => row.text), [
        'drwx------+  4 robinfai  staff   128B Pictures/',
        'drwxr-xr-x+  4 robinfai  staff   128B Public/',
      ]);
    });

    test('ignores stale pending rows after an old command row', () {
      final submittedAt = DateTime(2026, 6, 10, 13, 10);
      final oldOutputAt = submittedAt.subtract(const Duration(seconds: 1));
      final commandOutputAt = submittedAt.add(const Duration(milliseconds: 1));

      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: 'pwd',
        commandRow: 10,
        submittedAt: submittedAt,
        frame: terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text: 'Applications   Documents   Library',
              modifiedAt: oldOutputAt,
            ),
            terminal.TerminalRow(
              index: 1,
              text: 'Downloads      Movies      Music',
              modifiedAt: oldOutputAt,
            ),
            terminal.TerminalRow(
              index: 2,
              text: '/Users/robinfai',
              modifiedAt: commandOutputAt,
            ),
          ],
          cursor: const terminal.TerminalCursor(row: 2, col: 16, visible: true),
          dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 3)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 11,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(rows.map((row) => row.text), ['/Users/robinfai']);
    });

    test('drops wrapped submitted command fragments from fallback rows', () {
      final submittedAt = DateTime(2026, 6, 10, 13, 20);
      final commandOutputAt = submittedAt.add(const Duration(milliseconds: 1));

      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: 'ls -la',
        commandRow: 69,
        submittedAt: submittedAt,
        frame: terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text: '/tmp/ianvs-cwd ls',
              modifiedAt: commandOutputAt,
            ),
            terminal.TerminalRow(
              index: 1,
              text: ' -la',
              modifiedAt: commandOutputAt,
            ),
            terminal.TerminalRow(
              index: 2,
              text: 'total 16',
              modifiedAt: commandOutputAt,
            ),
            terminal.TerminalRow(
              index: 3,
              text: 'alpha.txt',
              modifiedAt: commandOutputAt,
            ),
          ],
          cursor: const terminal.TerminalCursor(row: 3, col: 9, visible: true),
          dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 4)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 70,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(rows.map((row) => row.text), ['total 16', 'alpha.txt']);
    });

    test('keeps single-line output that matches a command argument', () {
      final submittedAt = DateTime(2026, 6, 10, 13, 21);
      final commandOutputAt = submittedAt.add(const Duration(milliseconds: 1));

      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: 'echo hello',
        commandRow: 69,
        submittedAt: submittedAt,
        frame: terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(
              index: 0,
              text: 'hello',
              modifiedAt: commandOutputAt,
            ),
          ],
          cursor: const terminal.TerminalCursor(row: 0, col: 5, visible: true),
          dirtyRanges: const [terminal.TerminalDirtyRange(start: 0, end: 1)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 70,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(rows.map((row) => row.text), ['hello']);
    });

    test(
      'does not capture current viewport rows for an offscreen old block',
      () {
        const block = ShellCommandBlock(
          id: 'session-1:command:20',
          command: 'ls',
          cwd: '/Users/robinfai',
          status: ShellCommandBlockStatus.succeeded,
          outputRange: ShellCommandBlockRange(
            commandRow: 20,
            outputStartRow: 21,
            outputEndRow: 40,
          ),
        );
        final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

        final captured = shellCommandBlockPreviewRowsForFrame(
          snapshot: snapshot,
          frame: const terminal.TerminalFrameDiff(
            rows: [
              terminal.TerminalRow(index: 0, text: 'new-command-output'),
              terminal.TerminalRow(index: 1, text: 'logs.json'),
            ],
            cursor: terminal.TerminalCursor(row: 1, col: 9, visible: true),
            dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 2)],
            viewportRows: 20,
            viewportCols: 93,
            viewportStartRow: 100,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

        expect(captured, isEmpty);
      },
    );

    test(
      'does not capture command block preview rows from alternate screen',
      () {
        const block = ShellCommandBlock(
          id: 'session-1:command:20',
          command: 'vi public.key',
          cwd: '/Users/dev',
          status: ShellCommandBlockStatus.running,
          outputRange: ShellCommandBlockRange(
            commandRow: 20,
            outputStartRow: 21,
            outputEndRow: 40,
          ),
        );
        final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);

        final captured = shellCommandBlockPreviewRowsForFrame(
          snapshot: snapshot,
          frame: const terminal.TerminalFrameDiff(
            rows: [
              terminal.TerminalRow(index: 0, text: '~'),
              terminal.TerminalRow(index: 1, text: ':q!'),
            ],
            cursor: terminal.TerminalCursor(row: 1, col: 3, visible: true),
            dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 2)],
            viewportRows: 20,
            viewportCols: 93,
            viewportStartRow: 21,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: terminal.TerminalFrameModes(alternateScreen: true),
          ),
        );

        expect(captured, isEmpty);
      },
    );

    test('does not capture submitted preview rows from alternate screen', () {
      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: 'vi public.key',
        commandRow: 20,
        submittedAt: DateTime(2026, 6, 13),
        frame: const terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(index: 0, text: '~'),
            terminal.TerminalRow(index: 1, text: ':q!'),
          ],
          cursor: terminal.TerminalCursor(row: 1, col: 3, visible: true),
          dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 2)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 21,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: terminal.TerminalFrameModes(alternateScreen: true),
        ),
      );

      expect(rows, isEmpty);
    });

    test('does not capture finished preview rows from alternate screen', () {
      const block = ShellCommandBlock(
        id: 'session-1:command:20',
        command: 'vi public.key',
        cwd: '/Users/dev',
        status: ShellCommandBlockStatus.succeeded,
        outputRange: ShellCommandBlockRange(
          commandRow: 20,
          outputStartRow: 21,
          outputEndRow: 40,
        ),
      );

      final captured = shellCommandBlockFinishedPreviewRowsForCurrentFrame(
        snapshot: ShellCommandBlockSnapshot.withBlocks(blocks: [block]),
        frame: const terminal.TerminalFrameDiff(
          rows: [
            terminal.TerminalRow(index: 0, text: '~'),
            terminal.TerminalRow(index: 1, text: ':q!'),
          ],
          cursor: terminal.TerminalCursor(row: 1, col: 3, visible: true),
          dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 2)],
          viewportRows: 20,
          viewportCols: 93,
          viewportStartRow: 21,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: terminal.TerminalFrameModes(alternateScreen: true),
        ),
      );

      expect(captured, isEmpty);
    });

    test('replaces captured output when same length rows change content', () {
      expect(
        shellCommandBlockShouldReplacePreviewRows(
          existingRows: const [
            terminal.TerminalRow(index: 0, text: 'capturing output...'),
          ],
          nextRows: const [
            terminal.TerminalRow(
              index: 0,
              text: 'zsh: command not found: ls-al',
            ),
          ],
        ),
        isTrue,
      );
    });

    test('appends later finished output slices for the same command block', () {
      final firstCapturedAt = DateTime(2026, 6, 10, 14);
      final laterCapturedAt = firstCapturedAt.add(
        const Duration(milliseconds: 50),
      );

      final rows = shellCommandBlockMergedPreviewRows(
        existingRows: [
          terminal.TerminalRow(
            index: 0,
            text: 'total 7600',
            modifiedAt: firstCapturedAt,
          ),
        ],
        nextRows: [
          terminal.TerminalRow(
            index: 0,
            text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
            modifiedAt: laterCapturedAt,
          ),
          terminal.TerminalRow(
            index: 1,
            text: '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
            modifiedAt: laterCapturedAt,
          ),
        ],
      );

      expect(rows.map((row) => row.text), [
        'total 7600',
        'drwxr-xr-x  10 robinfai  staff   320B work/',
        '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
      ]);
      expect(rows.map((row) => row.index), [0, 1, 2]);
    });

    test('merges overlapping finished output slices without duplicates', () {
      final firstCapturedAt = DateTime(2026, 6, 10, 14, 1);
      final laterCapturedAt = firstCapturedAt.add(
        const Duration(milliseconds: 50),
      );

      final rows = shellCommandBlockMergedPreviewRows(
        existingRows: [
          terminal.TerminalRow(
            index: 0,
            text: 'total 7600',
            modifiedAt: firstCapturedAt,
          ),
          terminal.TerminalRow(
            index: 1,
            text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
            modifiedAt: firstCapturedAt,
          ),
        ],
        nextRows: [
          terminal.TerminalRow(
            index: 0,
            text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
            modifiedAt: firstCapturedAt,
          ),
          terminal.TerminalRow(
            index: 1,
            text: '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
            modifiedAt: laterCapturedAt,
          ),
        ],
      );

      expect(rows.map((row) => row.text), [
        'total 7600',
        'drwxr-xr-x  10 robinfai  staff   320B work/',
        '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
      ]);
      expect(rows.map((row) => row.index), [0, 1, 2]);
    });

    test('detects later shorter preview slices as output updates', () {
      final firstCapturedAt = DateTime(2026, 6, 10, 14, 2);
      final laterCapturedAt = firstCapturedAt.add(
        const Duration(milliseconds: 50),
      );

      expect(
        shellCommandBlockPreviewRowsWouldChange(
          existingRows: [
            terminal.TerminalRow(
              index: 0,
              text: 'total 7600',
              modifiedAt: firstCapturedAt,
            ),
            terminal.TerminalRow(
              index: 1,
              text: 'drwxr-xr-x  10 robinfai  staff   320B work/',
              modifiedAt: firstCapturedAt,
            ),
            terminal.TerminalRow(
              index: 2,
              text: '-rw-r--r--   1 robinfai  staff   2.4K logs.json',
              modifiedAt: firstCapturedAt,
            ),
          ],
          nextRows: [
            terminal.TerminalRow(
              index: 0,
              text: 'drwx------@ 26 robinfai  staff   832B Documents/',
              modifiedAt: laterCapturedAt,
            ),
          ],
        ),
        isTrue,
      );
    });

    test('filters prompt and readline rows from captured output', () {
      const block = ShellCommandBlock(
        id: 'session-1:command:40:41',
        command: 'ls-al',
        cwd: '/Users/robinfai',
        exitCode: 127,
        status: ShellCommandBlockStatus.failed,
        outputRange: ShellCommandBlockRange(
          commandRow: 40,
          outputStartRow: 41,
          outputEndRow: 43,
        ),
      );

      final rows = shellCommandBlockOutputRowsFrom(block, const [
        terminal.TerminalRow(
          index: 0,
          text: '?? robinfai? ~ ???? ? 20:18 ? ? ls-al',
        ),
        terminal.TerminalRow(index: 1, text: 'zsh: command not found: ls-al'),
        terminal.TerminalRow(index: 2, text: '?? robinfai? ~ ???? ? 20:18 ? ?'),
      ]);

      expect(rows.map((row) => row.text), ['zsh: command not found: ls-al']);
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

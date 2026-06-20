import 'package:app/features/agent_center/agent_center.dart';
import 'package:app/features/command_center/command_block_navigation.dart';
import 'package:app/features/command_center/fig_completion_service.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/shell/universal_input.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlocksOverlay', () {
    testWidgets('renders active failed block info in a popover', (
      tester,
    ) async {
      final item = ShellCommandBlockOverlayItem(
        id: 'cmd-1',
        command: 'flutter test',
        rowOffset: 1,
        rowSpan: 3,
        status: ShellCommandBlockStatus.failed,
        statusLabel: 'exit 1',
        active: true,
        showFailureSnapshotAction: true,
        showReplayAction: true,
        showDiffAction: false,
      );
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([item]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.text('flutter test'), findsOneWidget);
      expect(find.text('exit 1'), findsNothing);
      expect(find.text('Output captured'), findsNothing);
      expect(find.text('Replay context'), findsNothing);
      expect(find.text('Failure snapshot'), findsNothing);
      expect(find.text('Previous run'), findsNothing);
      expect(find.text('Copy output'), findsNothing);
      expect(find.text('Replay from here'), findsNothing);

      await tester.tap(find.byKey(const Key('shell-command-block-info-cmd-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-command-block-info-popover-cmd-1')),
        findsOneWidget,
      );
      expect(find.text('Block info'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('exit 1'), findsOneWidget);
      expect(find.text('Output'), findsOneWidget);
      expect(find.text('Output captured'), findsOneWidget);
      expect(find.text('Replay context'), findsOneWidget);
      expect(find.text('Failure snapshot'), findsOneWidget);
      expect(find.text('Previous run'), findsNothing);
    });

    testWidgets('renders nothing for empty view model', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: const Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: ShellCommandBlocksOverlay(
                viewModel: ShellCommandBlocksOverlayViewModel(),
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Output captured'), findsNothing);
    });

    testWidgets('vertical drag scrolls command block stack', (tester) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        for (var index = 0; index < 12; index += 1)
          _overlayItem(
            id: 'cmd-scroll-$index',
            command: 'command $index',
            active: index == 11,
          ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      final scrollableFinder = find.byKey(
        const Key('shell-command-blocks-scroll-view'),
      );
      final scrollableState = tester.state<ScrollableState>(
        _scrollableDescendant(scrollableFinder, AxisDirection.up),
      );

      expect(scrollableState.position.pixels, 0);

      await tester.drag(scrollableFinder, const Offset(0, 90));
      await tester.pumpAndSettle();

      expect(scrollableState.position.pixels, greaterThan(0));
    });

    testWidgets('exposes block info as one button', (tester) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(id: 'cmd-semantics', active: true, rowSpan: 3),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Output captured'), findsNothing);
      expect(find.byTooltip('Block info'), findsOneWidget);

      final infoButton = find.byKey(
        const Key('shell-command-block-info-cmd-semantics'),
      );
      expect(find.bySemanticsLabel('Block info'), findsOneWidget);
      final infoButtonSize = tester.getSize(infoButton);
      expect(infoButtonSize.width, greaterThanOrEqualTo(44));
      expect(infoButtonSize.height, greaterThanOrEqualTo(44));
    });

    testWidgets('shows a visible block actions button when actions exist', (
      tester,
    ) async {
      final openedBlockIds = <String>[];
      final openedAnchorRects = <Rect>[];
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(id: 'cmd-actions', active: true, rowSpan: 3),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 160,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                onOpenBlockActions: (block, anchorRect) {
                  openedBlockIds.add(block.id);
                  openedAnchorRects.add(anchorRect);
                },
              ),
            ),
          ),
        ),
      );

      final actionButton = find.byKey(
        const Key('shell-command-block-actions-cmd-actions'),
      );
      expect(actionButton, findsOneWidget);
      expect(find.byTooltip('Block actions'), findsOneWidget);
      expect(find.bySemanticsLabel('Block actions'), findsOneWidget);

      await tester.tap(actionButton);
      await tester.pump();

      expect(openedBlockIds, ['cmd-actions']);
      expect(openedAnchorRects.single, tester.getRect(actionButton));
    });

    testWidgets('tapping a block selects it for command center context', (
      tester,
    ) async {
      final selectedBlockIds = <String>[];
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'cmd-select',
          command: 'flutter test --watch',
          active: false,
          rowSpan: 3,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 180,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                onSelectBlock: (block) => selectedBlockIds.add(block.id),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-block-cmd-select')));
      await tester.pump();

      expect(selectedBlockIds, ['cmd-select']);
    });

    testWidgets('keeps narrow single-row blocks compact', (tester) async {
      final item = _overlayItem(
        id: 'cmd-narrow',
        command:
            'flutter test test/shell/shell_screen_command_blocks_test.dart '
            '--plain-name very-long-command-name',
        rowSpan: 1,
        active: true,
        showDiffAction: true,
      );
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([item]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 148,
              height: 32,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(item.command), findsOneWidget);
      expect(find.text('exit 1'), findsNothing);
      expect(find.text('Output captured'), findsNothing);
      expect(find.text('Replay context'), findsNothing);
      expect(find.text('Failure snapshot'), findsNothing);
      expect(find.text('Previous run'), findsNothing);
      expect(find.byTooltip('Block info'), findsOneWidget);
    });

    testWidgets('aligns command blocks to terminal content padding', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(id: 'cmd-padding', rowOffset: 2),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                contentPadding: const EdgeInsets.fromLTRB(24, 12, 36, 8),
              ),
            ),
          ),
        ),
      );

      final blockFinder = find.byKey(
        const Key('shell-command-block-cmd-padding'),
      );

      expect(tester.getTopLeft(blockFinder).dx, 24);
      expect(tester.getSize(blockFinder).width, 300);
    });

    testWidgets('lays command cards from bottom upward with opaque surfaces', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'latest',
          command: 'ls -al',
          rowOffset: 99,
          rowSpan: 4,
          active: true,
        ),
        _overlayItem(
          id: 'older',
          command: 'pwd',
          rowOffset: 0,
          rowSpan: 1,
          active: false,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 280,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      final latestTop = tester
          .getTopLeft(find.byKey(const Key('shell-command-block-latest')))
          .dy;
      final olderTop = tester
          .getTopLeft(find.byKey(const Key('shell-command-block-older')))
          .dy;
      final card = tester.widget<DecoratedBox>(
        find.byKey(const Key('shell-command-block-card-latest')),
      );
      final decoration = card.decoration as BoxDecoration;
      final background = decoration.color;

      expect(latestTop, greaterThan(olderTop));
      expect(background, isNotNull);
      expect((background!.toARGB32() >> 24) & 0xff, 0xff);
    });

    testWidgets('renders command metadata and terminal output surface', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'metadata',
          command: 'flutter test',
          active: true,
          cwd: '/repo',
          durationLabel: '842ms',
          outputRangeLabel: 'rows 12-18',
          terminalRows: const [
            terminal.TerminalRow(index: 0, text: '00:01 +3: all tests passed'),
          ],
          terminalViewportCols: 80,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 220,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.text('/repo · 842ms · rows 12-18'), findsOneWidget);
      final metadataRight = tester
          .getTopRight(find.text('/repo · 842ms · rows 12-18'))
          .dx;
      final metadataCenterY = tester
          .getCenter(find.text('/repo · 842ms · rows 12-18'))
          .dy;
      final commandCenterY = tester.getCenter(find.text('flutter test')).dy;
      final infoCenterY = tester
          .getCenter(find.byKey(const Key('shell-command-block-info-metadata')))
          .dy;
      final infoLeft = tester
          .getTopLeft(
            find.byKey(const Key('shell-command-block-info-metadata')),
          )
          .dx;
      expect(metadataRight, lessThanOrEqualTo(infoLeft));
      expect(commandCenterY, closeTo(infoCenterY, 0.5));
      expect(metadataCenterY, closeTo(infoCenterY, 0.5));
      expect(
        find.byKey(const Key('shell-command-block-terminal-output-metadata')),
        findsOneWidget,
      );
      expect(find.byType(terminal.TerminalFramePreview), findsOneWidget);
    });

    testWidgets('running command block keeps output in live terminal mode', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'running-output',
          command: 'python manage.py shell',
          active: true,
          status: ShellCommandBlockStatus.running,
          statusLabel: 'running',
          terminalRows: const [terminal.TerminalRow(index: 0, text: '>>> ')],
          terminalViewportCols: 80,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 220,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                liveTerminalRows: 12,
                liveTerminalBuilder: _fakeLiveTerminalBuilder,
              ),
            ),
          ),
        ),
      );

      expect(find.text('python manage.py shell'), findsOneWidget);
      expect(find.text('running'), findsNothing);
      expect(find.text('Live terminal'), findsNothing);
      await tester.tap(
        find.byKey(const Key('shell-command-block-info-running-output')),
      );
      await tester.pumpAndSettle();
      expect(find.text('running'), findsOneWidget);
      expect(find.text('Live terminal'), findsOneWidget);
      expect(
        find.byKey(
          const Key('shell-command-block-terminal-output-running-output'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const Key('shell-command-block-live-terminal-output-running-output'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake-live-terminal-running-output')),
        findsOneWidget,
      );
      expect(find.byType(terminal.TerminalFramePreview), findsNothing);

      final accent = buildIanvsTerminalTheme(
        Brightness.dark,
      ).extension<AppThemeTokens>()!.accent;
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-command-block-card-running-output')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox &&
                widget.color.toARGB32() == accent.toARGB32(),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sizes running live terminal rows with padding', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'short-live',
          command: 'python',
          active: true,
          status: ShellCommandBlockStatus.running,
          statusLabel: 'running',
          liveTerminalRows: 4,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 280,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                liveTerminalRows: 4,
                liveTerminalBuilder: _fakeLiveTerminalBuilder,
              ),
            ),
          ),
        ),
      );

      final liveOutputFinder = find.byKey(
        const Key('shell-command-block-live-terminal-output-short-live'),
      );
      expect(tester.getSize(liveOutputFinder).height, 18 * 7);
    });

    testWidgets('caps running live terminal height at sixty rows', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'tall-live',
          command: 'top',
          active: true,
          status: ShellCommandBlockStatus.running,
          statusLabel: 'running',
          liveTerminalRows: 80,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 360,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 4,
                liveTerminalRows: 80,
                liveTerminalBuilder: _fakeLiveTerminalBuilder,
              ),
            ),
          ),
        ),
      );

      final liveOutputFinder = find.byKey(
        const Key('shell-command-block-live-terminal-output-tall-live'),
      );
      expect(tester.getSize(liveOutputFinder).height, 4 * 60);
    });

    testWidgets('clips running live terminal to the block output rows', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'offset-live',
          command: 'python',
          active: true,
          status: ShellCommandBlockStatus.running,
          statusLabel: 'running',
          liveTerminalViewportRowOffset: 4,
          liveTerminalRows: 2,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 320,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 10,
                liveTerminalRows: 12,
                liveTerminalBuilder: _fakeRowedLiveTerminalBuilder,
              ),
            ),
          ),
        ),
      );

      final liveOutputFinder = find.byKey(
        const Key('shell-command-block-live-terminal-output-offset-live'),
      );
      final liveTop = tester.getTopLeft(liveOutputFinder).dy;

      expect(tester.getSize(liveOutputFinder).height, 10 * 5);
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('fake-live-terminal-row-offset-live-4')),
            )
            .dy,
        liveTop,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('fake-live-terminal-row-offset-live-3')),
            )
            .dy,
        liveTop - 10,
      );
    });

    testWidgets('caps preview terminal height and scrolls its rows', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'tall-output',
          command: 'seq 20',
          active: true,
          terminalRows: [
            for (var index = 0; index < 20; index += 1)
              terminal.TerminalRow(index: index, text: 'line $index'),
          ],
          terminalViewportCols: 80,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 320,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      final outputFinder = find.byKey(
        const Key('shell-command-block-terminal-output-tall-output'),
      );
      expect(tester.getSize(outputFinder).height, 18 * 8);

      final scrollableFinder = find.byKey(
        const Key('shell-command-block-terminal-output-scroll-tall-output'),
      );
      final scrollableState = tester.state<ScrollableState>(
        _scrollableDescendant(scrollableFinder, AxisDirection.down),
      );
      expect(scrollableState.position.pixels, 0);

      await tester.drag(scrollableFinder, const Offset(0, -90));
      await tester.pumpAndSettle();

      expect(scrollableState.position.pixels, greaterThan(0));
    });

    testWidgets('keeps inactive tall block labels anchored near command row', (
      tester,
    ) async {
      const command = 'ls';
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'cmd-inactive-tall',
          command: command,
          active: false,
          rowSpan: 8,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 220,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      final blockTop = tester
          .getTopLeft(
            find.byKey(const Key('shell-command-block-cmd-inactive-tall')),
          )
          .dy;
      final commandTop = tester.getTopLeft(find.text(command)).dy;
      final commandCenterY = tester.getCenter(find.text(command)).dy;
      final infoCenterY = tester
          .getCenter(
            find.byKey(const Key('shell-command-block-info-cmd-inactive-tall')),
          )
          .dy;

      expect(commandTop - blockTop, lessThan(32));
      expect(commandCenterY, closeTo(infoCenterY, 0.5));
    });

    testWidgets('shows bookmark control and toggles the selected block', (
      tester,
    ) async {
      final toggled = <String>[];
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(id: 'cmd-bookmark', active: true, bookmarked: true),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 180,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
                onToggleBlockBookmark: (block) => toggled.add(block.id),
              ),
            ),
          ),
        ),
      );

      final bookmarkFinder = find.byKey(
        const Key('shell-command-block-bookmark-cmd-bookmark'),
      );
      expect(bookmarkFinder, findsOneWidget);
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);

      await tester.tap(bookmarkFinder);
      await tester.pump();

      expect(toggled, ['cmd-bookmark']);
    });

    testWidgets('filters captured block output rows from the block toolbar', (
      tester,
    ) async {
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(
          id: 'cmd-filter',
          command: 'cat log.txt',
          active: true,
          terminalRows: const [
            terminal.TerminalRow(index: 0, text: 'INFO booted'),
            terminal.TerminalRow(index: 1, text: 'ERROR failed'),
            terminal.TerminalRow(index: 2, text: 'TRACE ignored'),
          ],
          terminalViewportCols: 80,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 240,
              child: ShellCommandBlocksOverlay(
                viewModel: viewModel,
                rowHeight: 18,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('shell-command-block-filter-cmd-filter')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('shell-command-block-filter-editor-cmd-filter')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-block-filter-query-cmd-filter')),
        'ERROR',
      );
      await tester.pump();

      final preview = tester.widget<terminal.TerminalFramePreview>(
        find.byType(terminal.TerminalFramePreview),
      );
      expect(preview.frame.rows.map((row) => row.text), ['ERROR failed']);
    });
  });

  group('shellCommandBlocksStickyHeaderResolution', () {
    test(
      'resolves the sticky header from the shell command block snapshot',
      () {
        final snapshot = ShellCommandBlockSnapshot.withBlocks(
          blocks: const [
            ShellCommandBlock(
              id: 'cmd-long-output',
              command: 'seq 1 1000',
              cwd: '/repo',
              status: ShellCommandBlockStatus.succeeded,
              outputRange: ShellCommandBlockRange(
                commandRow: 10,
                outputStartRow: 11,
                outputEndRow: 120,
              ),
            ),
          ],
        );

        final result = shellCommandBlocksStickyHeaderResolution(
          snapshot: snapshot,
          sessionId: 'session-a',
          viewportStartRow: 60,
          viewportRows: 24,
          modes: terminal.TerminalFrameModes.empty,
          shellIntegrationEnabled: true,
        );

        expect(result.visible, isTrue);
        expect(result.header?.blockId, 'cmd-long-output');
        expect(result.header?.command, 'seq 1 1000');
        expect(result.header?.cwdLabel, '/repo');
        expect(result.header?.blockEndRowExclusive, 121);
      },
    );

    test('hides the sticky header in the alternate screen buffer', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'cmd-vim',
            command: 'vim README.md',
            status: ShellCommandBlockStatus.running,
            outputRange: ShellCommandBlockRange(
              commandRow: 0,
              outputStartRow: 1,
              outputEndRow: 80,
            ),
          ),
        ],
      );

      final result = shellCommandBlocksStickyHeaderResolution(
        snapshot: snapshot,
        sessionId: 'session-a',
        viewportStartRow: 20,
        viewportRows: 24,
        modes: const terminal.TerminalFrameModes(alternateScreen: true),
        shellIntegrationEnabled: true,
      );

      expect(result.visible, isFalse);
      expect(result.header, isNull);
    });
  });

  group('shellCommandBlocksNavigationResult', () {
    test('navigates command block snapshots by selected block', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'cmd-one',
            command: 'echo one',
            status: ShellCommandBlockStatus.succeeded,
            outputRange: ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 12,
            ),
          ),
          ShellCommandBlock(
            id: 'cmd-two',
            command: 'echo two',
            status: ShellCommandBlockStatus.succeeded,
            outputRange: ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 22,
            ),
          ),
        ],
      );

      final next = shellCommandBlocksNavigationResult(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'cmd-one',
        target: CommandBlockNavigationTarget.next,
        shellIntegrationEnabled: true,
      );
      final previous = shellCommandBlocksNavigationResult(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'cmd-two',
        target: CommandBlockNavigationTarget.previous,
        shellIntegrationEnabled: true,
      );

      expect(next.enabled, isTrue);
      expect(next.intent.blockId, 'cmd-two');
      expect(next.intent.row, 20);
      expect(previous.enabled, isTrue);
      expect(previous.intent.blockId, 'cmd-one');
      expect(previous.intent.row, 10);
    });

    test('reports a disabled reason when no command blocks exist', () {
      final result = shellCommandBlocksNavigationResult(
        snapshot: const ShellCommandBlockSnapshot(),
        sessionId: 'session-a',
        selectedBlockId: null,
        target: CommandBlockNavigationTarget.next,
        shellIntegrationEnabled: true,
      );

      expect(result.enabled, isFalse);
      expect(
        result.disabledReason,
        CommandBlockNavigationDisabledReason.noCommandBlocks,
      );
      expect(
        shellCommandBlocksNavigationMessage(result.disabledReason),
        'No command blocks are available to navigate.',
      );
    });
  });

  group('ShellCommandInputBar', () {
    testWidgets('submits standalone input and clears the field', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'ls -al',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submitted, ['ls -al']);
      expect(controller.text, isEmpty);
      expect(find.text('/repo'), findsNothing);
    });

    testWidgets('renders universal input controls in the command bar', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.auto,
              contextChips: const ['cwd app'],
              contextOptions: const [
                UniversalInputToolOption(
                  id: 'cwd',
                  label: '@cwd',
                  value: '@cwd app',
                  icon: Icons.folder_rounded,
                  detail: 'app',
                ),
              ],
              modelLabel: 'Agent draft',
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('shell-command-input-mode-terminal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-mode-auto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-mode-agent')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-detection-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-context')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-slash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-model')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-model-label')),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('shell-command-input-field')),
      );
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.maxLines, isNull);
      expect(find.bySemanticsLabel('Command input'), findsOneWidget);
      expect(find.text('cwd app'), findsOneWidget);
      expect(find.text('Agent draft'), findsOneWidget);
      expect(
        find.byKey(const Key('shell-command-agent-conversation-pane')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('shell-command-input-model')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Env: DEEPSEEK_API_KEY; secret value stays outside Agent requests.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides Agent controls when rollout excludes Agent mode', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final requestedModes = <UniversalInputMode>[];
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.auto,
              availableModes: const <UniversalInputMode>{
                UniversalInputMode.auto,
                UniversalInputMode.terminal,
              },
              modelOptions: const <UniversalInputToolOption>[
                UniversalInputToolOption(
                  id: 'local',
                  label: 'Local heuristic',
                  value: 'Local heuristic',
                  icon: Icons.memory_rounded,
                  detail: 'Local only; no provider secret required.',
                ),
                UniversalInputToolOption(
                  id: 'shell',
                  label: 'Shell strict',
                  value: 'Shell strict',
                  icon: Icons.terminal_rounded,
                  detail: 'Command-first routing; no provider secret required.',
                ),
              ],
              onModeChanged: requestedModes.add,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('shell-command-input-mode-terminal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-mode-auto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-mode-agent')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('shell-command-input-model')));
      await tester.pumpAndSettle();

      expect(find.text('Local heuristic'), findsWidgets);
      expect(find.text('Shell strict'), findsWidgets);
      expect(find.text('Agent draft'), findsNothing);

      await tester.tap(find.text('Shell strict').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        '* explain this session',
      );
      await tester.pump();

      expect(requestedModes, isEmpty);
      expect(controller.text, '* explain this session');
    });

    testWidgets('renders an Agent conversation pane in agent mode', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('shell-command-agent-conversation-pane')),
        findsOneWidget,
      );
      expect(find.text('Agent conversation'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.bySemanticsLabel('Agent message composer'), findsOneWidget);
      expect(find.bySemanticsLabel('Command input'), findsNothing);
    });

    testWidgets('redacts manual Agent context chip text', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              contextChips: const <String>[
                'cwd ianvs-password=demo-not-real-secret',
              ],
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      expect(find.text('cwd ianvs-password=[REDACTED]'), findsNWidgets(2));
      expect(find.textContaining('demo-not-real-secret'), findsNothing);
    });

    testWidgets('sends an Agent message and renders streamed reply', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: MockAgentRuntimeAdapter(
                steps: <MockAgentResponseStep>[
                  MockAgentResponseStep.text('Use '),
                  MockAgentResponseStep.text('pwd to inspect the directory.'),
                ],
              ),
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Explain my working directory',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(controller.text, isEmpty);
      expect(find.text('Explain my working directory'), findsOneWidget);
      expect(find.text('Use pwd to inspect the directory.'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('sends Agent provider config without provider secret values', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final adapter = _RecordingAgentRuntimeAdapter();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              modelLabel: 'Agent draft',
              agentRuntimeAdapter: adapter,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Explain the current session',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pumpAndSettle();

      expect(adapter.requests, hasLength(1));
      final modelConfig = adapter.requests.single.modelConfig;
      expect(modelConfig?.providerId, 'agent');
      expect(modelConfig?.providerLabel, 'Agent draft');
      expect(modelConfig?.model, 'deepseek-command-draft');
      expect(
        modelConfig?.secretBoundary,
        'Env: DEEPSEEK_API_KEY; secret value stays outside Agent requests.',
      );
      expect(modelConfig?.secretBoundary, isNot(contains('sk-test-secret')));
      expect(modelConfig?.secretBoundary, isNot(contains('actual-secret')));
    });

    testWidgets('sends an external Agent prompt action with context', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final adapter = _RecordingAgentRuntimeAdapter();
      final contextSnapshot = const AgentContextBuilder().build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo',
          shell: '/bin/zsh',
          readOnly: false,
          shellHookAvailable: true,
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-search-result',
            command: 'npm test',
            exitCode: 1,
            outputExcerpt: '1 failing test',
          ),
        ),
      );
      ShellAgentPromptAction? promptAction;
      late StateSetter setHostState;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.agent,
                  agentRuntimeAdapter: adapter,
                  agentContextSnapshot: contextSnapshot,
                  agentPromptAction: promptAction,
                  onSubmitted: (command) async {
                    submitted.add(command);
                    return true;
                  },
                );
              },
            ),
          ),
        ),
      );

      setHostState(() {
        promptAction = const ShellAgentPromptAction(
          id: 1,
          prompt:
              'Debug command from search history (exit 1) in /repo: npm test',
        );
      });
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.messages
            .lastWhere((message) => message.role == AgentMessageRole.user)
            .plainText,
        'Debug command from search history (exit 1) in /repo: npm test',
      );
      expect(
        adapter.requests.single.context.snapshot?.selectedBlock?.id,
        'block-search-result',
      );
      expect(find.text('Context received.'), findsOneWidget);
      expect(controller.text, isEmpty);
    });

    testWidgets('Remember session sends summary as Agent memory bridge', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final adapter = _RecordingAgentRuntimeAdapter();
      final contextSnapshot = const AgentContextBuilder().build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo',
          shell: '/bin/zsh',
          profileName: 'Local Shell',
          readOnly: false,
          shellHookAvailable: true,
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-selected',
            command: 'flutter test',
            exitCode: 0,
          ),
          lastFailedBlock: AgentCommandBlockSnapshot(
            id: 'block-failed',
            command: 'dart analyze',
            exitCode: 1,
          ),
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'flutter test',
              status: AgentRecentCommandStatus.succeeded,
              exitCode: 0,
            ),
            AgentRecentCommandSnapshot(
              command: 'dart analyze',
              status: AgentRecentCommandStatus.failed,
              exitCode: 1,
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: adapter,
              agentContextSnapshot: contextSnapshot,
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Summary'), findsOneWidget);
      expect(
        find.byKey(const Key('agent-remember-session-summary')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('agent-remember-session-summary')));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(
        request.messages
            .lastWhere((message) => message.role == AgentMessageRole.user)
            .plainText,
        allOf(
          startsWith(
            'Remember this terminal session summary for this Agent conversation:',
          ),
          contains('Terminal session: terminal-1'),
          contains('Recent commands: 2 (1 failed)'),
          contains('Last failed: dart analyze (exit 1)'),
        ),
      );
      expect(request.context.snapshot?.sessionSummary, isNotNull);
      expect(
        request.context.snapshot?.attachments.map(
          (attachment) => attachment.kind,
        ),
        contains(AgentContextAttachmentKind.sessionSummary),
      );
      expect(controller.text, isEmpty);
    });

    testWidgets('Agent block actions attach selected and failed context', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final adapter = _RecordingAgentRuntimeAdapter();
      final contextSnapshot = const AgentContextBuilder().build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo',
          shell: '/bin/zsh',
          readOnly: false,
          shellHookAvailable: true,
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-selected',
            command: 'flutter test',
            exitCode: 0,
            outputExcerpt: 'All tests passed',
          ),
          lastFailedBlock: AgentCommandBlockSnapshot(
            id: 'block-failed',
            command: 'dart analyze',
            exitCode: 1,
            outputExcerpt: 'error: missing import',
          ),
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: adapter,
              agentContextSnapshot: contextSnapshot,
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Block'), findsOneWidget);
      expect(find.byTooltip('flutter test'), findsOneWidget);
      expect(find.text('Last failed'), findsOneWidget);
      expect(find.byTooltip('dart analyze'), findsOneWidget);
      expect(
        find.byKey(const Key('agent-explain-selected-block')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agent-debug-last-failed-block')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('agent-explain-selected-block')));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.messages
            .lastWhere((message) => message.role == AgentMessageRole.user)
            .parts
            .single
            .text,
        'Explain selected terminal block: flutter test',
      );
      expect(
        adapter.requests.single.context.snapshot?.selectedBlock?.id,
        'block-selected',
      );
      expect(
        adapter.requests.single.context.snapshot?.lastFailedBlock?.id,
        'block-failed',
      );
      expect(find.text('Context received.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-debug-last-failed-block')));
      await tester.pumpAndSettle();

      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.messages
            .lastWhere((message) => message.role == AgentMessageRole.user)
            .parts
            .single
            .text,
        'Debug last failed terminal block (exit 1): dart analyze',
      );
      expect(adapter.requests.last.context.cwd, '/repo');
      expect(adapter.requests.last.context.readOnly, isFalse);
    });

    testWidgets('reviews and inserts an Agent command proposal as a draft', (
      tester,
    ) async {
      final submitted = <String>[];
      final changed = <String>[];
      UniversalInputMode? requestedMode;
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final proposal = AgentCommandProposal(
        id: 'proposal-pwd',
        conversationId: 'conversation',
        command: 'pwd',
        explanation:
            'Print the current working directory without modifying files.',
        riskLevel: AgentCommandRiskLevel.low,
        warnings: const <String>['Read-only command.'],
        detectedEffects: const <String>['Prints the working directory.'],
        requiresConfirmation: false,
        source: AgentCommandProposalSource.mock,
        createdAt: DateTime(2026),
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: MockAgentRuntimeAdapter(
                steps: <MockAgentResponseStep>[
                  MockAgentResponseStep.text('Try this safe command.'),
                  MockAgentResponseStep.commandProposal(proposal),
                ],
              ),
              onChanged: changed.add,
              onModeChanged: (mode) {
                requestedMode = mode;
              },
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Suggest a safe cwd command',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(controller.text, isEmpty);
      expect(find.text('Proposed command'), findsOneWidget);
      expect(find.text('pwd'), findsOneWidget);
      expect(find.text('Low risk'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('agent-command-proposal-review')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-command-proposal-review')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('agent-command-proposal-review-dialog')),
        findsOneWidget,
      );
      expect(find.text('Review command proposal'), findsOneWidget);
      expect(find.text('Direct run eligible'), findsOneWidget);
      expect(
        find.text(
          'Print the current working directory without modifying files.',
        ),
        findsWidgets,
      );

      await tester.tap(
        find.byKey(const Key('agent-command-proposal-review-insert')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('agent-command-proposal-review-dialog')),
        findsNothing,
      );
      expect(controller.text, 'pwd');
      expect(changed.last, 'pwd');
      expect(requestedMode, UniversalInputMode.terminal);
      expect(submitted, isEmpty);
    });

    testWidgets('runs a low-risk Agent command proposal from review', (
      tester,
    ) async {
      final submitted = <String>[];
      final changed = <String>[];
      UniversalInputMode? requestedMode;
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final proposal = AgentCommandProposal(
        id: 'proposal-run-pwd',
        conversationId: 'conversation',
        command: 'pwd',
        explanation:
            'Print the current working directory without modifying files.',
        riskLevel: AgentCommandRiskLevel.low,
        requiresConfirmation: false,
        source: AgentCommandProposalSource.mock,
        createdAt: DateTime(2026),
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: MockAgentRuntimeAdapter(
                steps: <MockAgentResponseStep>[
                  MockAgentResponseStep.commandProposal(proposal),
                ],
              ),
              onChanged: changed.add,
              onModeChanged: (mode) {
                requestedMode = mode;
              },
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Run a safe cwd command',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('agent-command-proposal-review')),
      );
      await tester.tap(find.byKey(const Key('agent-command-proposal-review')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('agent-command-proposal-review-run')),
      );
      await tester.pumpAndSettle();

      expect(submitted, ['pwd']);
      expect(controller.text, isEmpty);
      expect(changed, containsAllInOrder(<String>['pwd', '']));
      expect(requestedMode, UniversalInputMode.terminal);
      expect(find.text('Agent command sent to terminal.'), findsOneWidget);
    });

    testWidgets('requires confirmation before running risky Agent proposals', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final proposal = AgentCommandProposal(
        id: 'proposal-sudo',
        conversationId: 'conversation',
        command: 'sudo lsof -i :8080',
        explanation: 'Inspect listeners with elevated privileges.',
        riskLevel: AgentCommandRiskLevel.medium,
        requiresConfirmation: false,
        source: AgentCommandProposalSource.mock,
        createdAt: DateTime(2026),
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: MockAgentRuntimeAdapter(
                steps: <MockAgentResponseStep>[
                  MockAgentResponseStep.commandProposal(proposal),
                ],
              ),
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Find the server on port 8080',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('agent-command-proposal-review')),
      );
      await tester.tap(find.byKey(const Key('agent-command-proposal-review')));
      await tester.pumpAndSettle();

      final disabledRun = tester.widget<FilledButton>(
        find.byKey(const Key('agent-command-proposal-review-run')),
      );
      expect(disabledRun.onPressed, isNull);
      expect(
        find.byKey(const Key('agent-command-proposal-run-confirmation')),
        findsOneWidget,
      );
      expect(submitted, isEmpty);

      await tester.tap(
        find.byKey(const Key('agent-command-proposal-run-confirmation')),
      );
      await tester.pumpAndSettle();
      final enabledRun = tester.widget<FilledButton>(
        find.byKey(const Key('agent-command-proposal-review-run')),
      );
      expect(enabledRun.onPressed, isNotNull);

      await tester.tap(
        find.byKey(const Key('agent-command-proposal-review-run')),
      );
      await tester.pumpAndSettle();

      expect(submitted, ['sudo lsof -i :8080']);
    });

    testWidgets('cancels an in-flight Agent stream from the pane', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.agent,
              agentRuntimeAdapter: MockAgentRuntimeAdapter(
                steps: <MockAgentResponseStep>[
                  MockAgentResponseStep.text('This should not appear.'),
                ],
                stepDelay: const Duration(milliseconds: 80),
              ),
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'Keep waiting',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pump();

      expect(find.text('Streaming'), findsWidgets);

      await tester.tap(find.byKey(const Key('agent-conversation-cancel')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('This should not appear.'), findsNothing);
    });

    testWidgets('stacks universal input context editor and toolbelt rows', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 720,
                child: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.auto,
                  contextChips: const ['cwd app'],
                  modelLabel: 'Default | auto',
                  onSubmitted: (_) async => false,
                ),
              ),
            ),
          ),
        ),
      );

      final barDecoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('shell-command-input-bar')),
                  )
                  .decoration
              as BoxDecoration;
      expect(barDecoration.borderRadius, isNotNull);
      expect(barDecoration.border, isNotNull);

      final chipRect = tester.getRect(find.text('cwd app'));
      final fieldRect = tester.getRect(
        find.byKey(const Key('shell-command-input-field')),
      );
      final modeRect = tester.getRect(
        find.byKey(const Key('shell-command-input-mode-terminal')),
      );
      final contextRect = tester.getRect(
        find.byKey(const Key('shell-command-input-context')),
      );
      final detectionRect = tester.getRect(
        find.byKey(const Key('shell-command-input-detection-label')),
      );
      final modelLabelRect = tester.getRect(
        find.byKey(const Key('shell-command-input-model-label')),
      );
      final runRect = tester.getRect(
        find.byKey(const Key('shell-command-run-button')),
      );

      expect(chipRect.bottom, lessThan(fieldRect.top));
      expect(fieldRect.bottom, lessThan(modeRect.top));
      expect(contextRect.center.dy, closeTo(modeRect.center.dy, 4));
      expect(detectionRect.center.dy, closeTo(modeRect.center.dy, 4));
      expect(modelLabelRect.center.dy, closeTo(runRect.center.dy, 4));
      expect(runRect.left, greaterThan(modelLabelRect.left));
    });

    testWidgets('mode prefix keeps remaining text in the command bar', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      var mode = UniversalInputMode.auto;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.dark),
              home: Scaffold(
                body: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: mode,
                  onModeChanged: (nextMode) {
                    setState(() {
                      mode = nextMode;
                    });
                  },
                  onSubmitted: (_) async => false,
                ),
              ),
            );
          },
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        '! git status',
      );
      await tester.pump();

      expect(mode, UniversalInputMode.terminal);
      expect(controller.text, 'git status');
      expect(find.text('Terminal command'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        '* explain the last failure',
      );
      await tester.pump();

      expect(mode, UniversalInputMode.agent);
      expect(controller.text, 'explain the last failure');
      expect(find.text('Agent natural language'), findsOneWidget);
    });

    testWidgets('command input suggestions render as an embedded panel', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.terminal,
                  suggestionsForInput: (_, _) => const [
                    'checkout',
                    'cherry-pick',
                  ],
                  onSubmitted: (_) async => false,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();
      final bar = find.byKey(const Key('shell-command-input-bar'));
      final initialBarHeight = tester.getSize(bar).height;
      expect(focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git che',
      );
      await tester.pump();
      await tester.pump();

      final panel = find.byKey(
        const Key('shell-command-input-suggestions-panel'),
      );
      final selectedSuggestion = find.byKey(
        const Key('shell-command-input-suggestion-checkout'),
      );

      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('terminal-autocomplete-menu')), findsNothing);
      expect(selectedSuggestion, findsOneWidget);
      expect(tester.getSize(bar).height, initialBarHeight);
      expect(focusNode.hasFocus, isTrue);
      expect(
        tester.getSemantics(selectedSuggestion),
        matchesSemantics(
          label: 'checkout',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );

      final barRect = tester.getRect(bar);
      final fieldRect = tester.getRect(
        find.byKey(const Key('shell-command-input-field')),
      );
      final panelRect = tester.getRect(panel);
      expect(panelRect.bottom, lessThanOrEqualTo(fieldRect.top));
      expect(fieldRect.top - panelRect.bottom, lessThanOrEqualTo(12));
      expect(panelRect.left, greaterThanOrEqualTo(barRect.left));
      expect(panelRect.left, greaterThan(fieldRect.left));
      expect(panelRect.right, lessThanOrEqualTo(barRect.right));
      expect(panelRect.width, lessThanOrEqualTo(660));
      final panelDecoration =
          tester.widget<DecoratedBox>(panel).decoration as BoxDecoration;
      expect(
        panelDecoration.color,
        AppThemeTokens.light.overlay.withValues(alpha: 0.96),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git cher',
      );
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(bar).height, initialBarHeight);
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('command input suggestions page past visible rows', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.terminal,
                  suggestionsForInput: (_, _) => const [
                    './alpha/',
                    './beta/',
                    './gamma/',
                    './delta/',
                    './epsilon/',
                    './zeta/',
                    './eta/',
                    './theta/',
                  ],
                  onSubmitted: (_) async => false,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'ls ./',
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('shell-command-input-suggestion-./alpha/')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-suggestion-./delta/')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-suggestion-./zeta/')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shell-command-input-suggestion-./eta/')),
        findsNothing,
      );

      for (var index = 0; index < 6; index += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.pump();

      final selectedSuggestion = find.byKey(
        const Key('shell-command-input-suggestion-./eta/'),
      );
      expect(
        find.byKey(const Key('shell-command-input-suggestion-./alpha/')),
        findsNothing,
      );
      expect(selectedSuggestion, findsOneWidget);
      expect(
        tester.getSemantics(selectedSuggestion),
        matchesSemantics(
          label: './eta/',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.text, 'ls ./eta/');
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('command input semantics expose the typed value', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.terminal,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git che',
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Command input'), findsOneWidget);
      final fieldSemantics = tester.getSemantics(
        find.byKey(const Key('shell-command-input-field')),
      );
      final fieldSemanticsData = fieldSemantics.getSemanticsData();
      expect(fieldSemanticsData.value, 'git che');
      expect(fieldSemanticsData.flagsCollection.isTextField, isTrue);
      expect(fieldSemanticsData.hasAction(SemanticsAction.setText), isTrue);
      semantics.dispose();
    });

    testWidgets('tab and click accept command input suggestions', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.terminal,
              suggestionsForInput: (_, _) => const ['checkout', 'cherry-pick'],
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git che',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.text, 'git checkout');
      expect(focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git che',
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('shell-command-input-suggestion-cherry-pick')),
      );
      await tester.pump();

      expect(controller.text, 'git cherry-pick');
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('tab applies Fig native replacement ranges', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final changed = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.terminal,
              suggestionsForInput: (_, _) => const ['commit'],
              figSuggestionsForInput: (_, _) => const {
                'commit': FigCompletionSuggestion(
                  name: 'commit',
                  replacementText: 'commit',
                  replaceStart: 4,
                  replaceEnd: 6,
                  cursorOffset: 10,
                  type: 'subcommand',
                  source: 'fig:git',
                ),
              },
              onChanged: changed.add,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'git cm --amend',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.text, 'git commit --amend');
      expect(controller.selection.baseOffset, 10);
      expect(changed.last, 'git commit --amend');
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('dangerous Fig suggestions expose warning affordance', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.terminal,
              suggestionsForInput: (_, _) => const ['merge'],
              figSuggestionsForInput: (_, _) => const {
                'merge': FigCompletionSuggestion(
                  name: 'merge',
                  replacementText: 'merge',
                  replaceStart: 6,
                  replaceEnd: 8,
                  cursorOffset: 11,
                  type: 'subcommand',
                  source: 'fig:gh',
                  isDangerous: true,
                ),
              },
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'gh pr me',
      );
      await tester.pump();
      await tester.pump();

      final suggestion = find.byKey(
        const Key('shell-command-input-suggestion-merge'),
      );
      expect(suggestion, findsOneWidget);
      expect(
        tester.getSemantics(suggestion),
        matchesSemantics(
          label: 'merge, dangerous command',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      expect(
        find.byIcon(Icons.warning_amber_rounded, skipOffstage: false),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('command input suggestions stay inside a narrow bar', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 360,
                child: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.terminal,
                  suggestionsForInput: (_, _) => const [
                    'very-long-command-suggestion-that-must-ellipsis',
                  ],
                  onSubmitted: (_) async => false,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'very',
      );
      await tester.pump();
      await tester.pump();

      final barRect = tester.getRect(
        find.byKey(const Key('shell-command-input-bar')),
      );
      final panelRect = tester.getRect(
        find.byKey(const Key('shell-command-input-suggestions-panel')),
      );
      final suggestionRect = tester.getRect(
        find.byKey(
          const Key(
            'shell-command-input-suggestion-'
            'very-long-command-suggestion-that-must-ellipsis',
          ),
        ),
      );

      expect(panelRect.left, greaterThanOrEqualTo(barRect.left));
      expect(panelRect.right, lessThanOrEqualTo(barRect.right));
      expect(suggestionRect.right, lessThanOrEqualTo(panelRect.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing slash opens slash commands and removes trigger', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.auto,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        '/',
      );
      await tester.pumpAndSettle();

      expect(find.text('/git-status'), findsOneWidget);
      await tester.tap(find.text('/git-status'));
      await tester.pumpAndSettle();

      expect(controller.text, 'git status --short --branch');
      expect(find.text('/git-status'), findsNothing);
    });

    testWidgets('typing at-sign opens context menu and removes trigger', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final selectedContext = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.dark),
              home: Scaffold(
                body: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  inputMode: UniversalInputMode.auto,
                  contextChips: selectedContext,
                  contextOptions: const [
                    UniversalInputToolOption(
                      id: 'cwd',
                      label: '@cwd',
                      value: '@cwd app',
                      icon: Icons.folder_rounded,
                      detail: 'app',
                    ),
                  ],
                  onContextSelected: (value) {
                    setState(() {
                      selectedContext.add(value);
                    });
                  },
                  onSubmitted: (_) async => false,
                ),
              ),
            );
          },
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        '@',
      );
      await tester.pumpAndSettle();

      expect(find.text('@cwd'), findsOneWidget);
      await tester.tap(find.text('@cwd'));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(find.text('@cwd app'), findsOneWidget);
    });

    testWidgets('natural-language send inserts the first suggestion', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              inputMode: UniversalInputMode.auto,
              classifyInput: (text) {
                if (text.trim().isEmpty) {
                  return const UniversalInputClassification.empty(
                    mode: UniversalInputMode.auto,
                  );
                }
                return UniversalInputClassification(
                  mode: UniversalInputMode.auto,
                  kind: UniversalInputKind.naturalLanguage,
                  source: UniversalInputDecisionSource.naturalLanguageScore,
                  confidence: 0.9,
                  tokens: text.trim().split(RegExp(r'\s+')),
                );
              },
              suggestionsForInput: (_, _) => const ['ls -la'],
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'show hidden files',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pump();

      expect(submitted, isEmpty);
      expect(controller.text, 'ls -la');
      expect(
        find.text('Suggested command inserted. Press Enter to run it.'),
        findsOneWidget,
      );
    });

    testWidgets('command correction panel accepts with button', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      var accepted = false;
      CommandCorrection? correction = const CommandCorrection(
        command: 'git status',
        reason: 'Corrects the executable name to git.',
        ruleId: 'executable-typo',
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.dark),
              home: Scaffold(
                body: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  commandCorrection: correction,
                  onAcceptCommandCorrection: (value) {
                    setState(() {
                      accepted = true;
                      controller.value = TextEditingValue(
                        text: value.command,
                        selection: TextSelection.collapsed(
                          offset: value.command.length,
                        ),
                      );
                      correction = null;
                    });
                  },
                  onDismissCommandCorrection: () {
                    setState(() {
                      correction = null;
                    });
                  },
                  onSubmitted: (_) async => false,
                ),
              ),
            );
          },
        ),
      );

      expect(
        find.byKey(const Key('shell-command-correction-panel')),
        findsOneWidget,
      );
      expect(find.text('git status'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('shell-command-correction-accept')),
      );
      await tester.pump();

      expect(accepted, isTrue);
      expect(controller.text, 'git status');
      expect(
        find.byKey(const Key('shell-command-correction-panel')),
        findsNothing,
      );
    });

    testWidgets('command correction panel accepts with right arrow', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      CommandCorrection? correction = const CommandCorrection(
        command: 'git status',
        reason: 'Corrects the executable name to git.',
        ruleId: 'executable-typo',
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.dark),
              home: Scaffold(
                body: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  commandCorrection: correction,
                  onAcceptCommandCorrection: (value) {
                    setState(() {
                      controller.value = TextEditingValue(
                        text: value.command,
                        selection: TextSelection.collapsed(
                          offset: value.command.length,
                        ),
                      );
                      correction = null;
                    });
                  },
                  onDismissCommandCorrection: () {
                    setState(() {
                      correction = null;
                    });
                  },
                  onSubmitted: (_) async => false,
                ),
              ),
            );
          },
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(controller.text, 'git status');
      expect(
        find.byKey(const Key('shell-command-correction-panel')),
        findsNothing,
      );
    });

    testWidgets('typing dismisses command correction panel', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      CommandCorrection? correction = const CommandCorrection(
        command: 'git status',
        reason: 'Corrects the executable name to git.',
        ruleId: 'executable-typo',
      );
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.dark),
              home: Scaffold(
                body: ShellCommandInputBar(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  commandCorrection: correction,
                  onDismissCommandCorrection: () {
                    setState(() {
                      correction = null;
                    });
                  },
                  onSubmitted: (_) async => false,
                ),
              ),
            );
          },
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'echo hello',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('shell-command-correction-panel')),
        findsNothing,
      );
    });

    testWidgets('run button keeps the command input text connection active', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              onSubmitted: (command) async {
                submitted.add(command);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'echo alpha',
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byKey(const Key('shell-command-run-button')));
      await tester.pump();

      expect(submitted, ['echo alpha']);
      expect(controller.text, isEmpty);
      expect(focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'echo beta',
      );
      expect(controller.text, 'echo beta');
    });

    testWidgets('Shift+Enter inserts newline and failed submit keeps text', (
      tester,
    ) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              onSubmitted: (command) async {
                submitted.add(command);
                return false;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'echo first',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.text, 'echo first\n');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submitted, ['echo first\n']);
      expect(controller.text, 'echo first\n');
      expect(focusNode.hasFocus, isTrue);
      expect(find.text('/repo'), findsNothing);
    });

    testWidgets('run button submits multiline command input', (tester) async {
      final submitted = <String>[];
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: ShellCommandInputBar(
                controller: controller,
                focusNode: focusNode,
                enabled: true,
                onSubmitted: (command) async {
                  submitted.add(command);
                  return true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        "printf 'multi-one\\n'\nprintf 'multi-two\\n'",
      );
      await tester.pump();

      final runButton = find.byKey(const Key('shell-command-run-button'));
      expect(runButton, findsOneWidget);
      expect(tester.getSize(runButton).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(runButton).height, greaterThanOrEqualTo(44));
      expect(
        tester.getTopLeft(runButton).dx,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('shell-command-input-field')))
              .dx,
        ),
      );

      await tester.tap(runButton);
      await tester.pump();

      expect(submitted, ["printf 'multi-one\\n'\nprintf 'multi-two\\n'"]);
      expect(controller.text, isEmpty);
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('Meta+R opens command search from the input field', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      var openCount = 0;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              onOpenCommandSearch: () => openCount += 1,
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-command-input-field')));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR, platform: 'macos');
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(openCount, 1);
    });

    testWidgets('shortcut listener does not take focus from the text field', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.dark),
          home: Scaffold(
            body: ShellCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              enabled: true,
              onOpenCommandSearch: () {},
              onSubmitted: (_) async => false,
            ),
          ),
        ),
      );

      final shortcutFocusFinder = find.byWidgetPredicate((widget) {
        if (widget is! Focus ||
            widget.onKeyEvent == null ||
            widget.child is! TextField) {
          return false;
        }
        return (widget.child as TextField).key ==
            const Key('shell-command-input-field');
      });
      expect(shortcutFocusFinder, findsOneWidget);
      final shortcutFocus = tester.widget<Focus>(shortcutFocusFinder);

      expect(shortcutFocus.canRequestFocus, isFalse);
      expect(shortcutFocus.skipTraversal, isTrue);
    });
  });
}

Finder _scrollableDescendant(Finder parent, AxisDirection axisDirection) {
  return find.descendant(
    of: parent,
    matching: find.byWidgetPredicate((widget) {
      return widget is Scrollable && widget.axisDirection == axisDirection;
    }),
  );
}

class _RecordingAgentRuntimeAdapter implements AgentRuntimeAdapter {
  final requests = <AgentRequest>[];

  @override
  Stream<AgentResponseEvent> send(AgentRequest request) async* {
    requests.add(request);
    yield AgentResponseStarted(requestId: request.id);
    yield AgentResponseTextDelta(
      requestId: request.id,
      delta: 'Context received.',
    );
    yield AgentResponseCompleted(requestId: request.id);
  }

  @override
  Future<void> cancel(String requestId) async {}
}

Widget _fakeLiveTerminalBuilder(
  BuildContext context,
  ShellCommandBlockOverlayItem block,
) {
  return ColoredBox(
    key: Key('fake-live-terminal-${block.id}'),
    color: Colors.black,
  );
}

Widget _fakeRowedLiveTerminalBuilder(
  BuildContext context,
  ShellCommandBlockOverlayItem block,
) {
  return Column(
    children: [
      for (var index = 0; index < 12; index += 1)
        SizedBox(
          key: Key('fake-live-terminal-row-${block.id}-$index'),
          height: 10,
          child: Text('row $index'),
        ),
    ],
  );
}

ShellCommandBlockOverlayItem _overlayItem({
  required String id,
  String command = 'flutter test',
  int rowOffset = 0,
  int rowSpan = 1,
  bool active = false,
  bool showDiffAction = false,
  ShellCommandBlockStatus status = ShellCommandBlockStatus.failed,
  String statusLabel = 'exit 1',
  String? cwd,
  String durationLabel = '--',
  String outputPreview = '',
  String outputRangeLabel = '',
  bool bookmarked = false,
  List<terminal.TerminalRow> terminalRows = const <terminal.TerminalRow>[],
  int terminalViewportCols = 0,
  int liveTerminalViewportRowOffset = 0,
  int liveTerminalRows = 1,
}) {
  return ShellCommandBlockOverlayItem(
    id: id,
    command: command,
    terminalRows: terminalRows,
    terminalViewportCols: terminalViewportCols,
    liveTerminalViewportRowOffset: liveTerminalViewportRowOffset,
    liveTerminalRows: liveTerminalRows,
    rowOffset: rowOffset,
    rowSpan: rowSpan,
    status: status,
    statusLabel: statusLabel,
    active: active,
    cwd: cwd,
    durationLabel: durationLabel,
    outputPreview: outputPreview,
    outputRangeLabel: outputRangeLabel,
    bookmarked: bookmarked,
    showFailureSnapshotAction: true,
    showReplayAction: true,
    showDiffAction: showDiffAction,
  );
}

import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlocksOverlay', () {
    testWidgets('renders active failed block status hints', (tester) async {
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
      expect(find.text('exit 1'), findsOneWidget);
      expect(find.text('Output captured'), findsOneWidget);
      expect(find.text('Replay context'), findsOneWidget);
      expect(find.text('Failure snapshot'), findsOneWidget);
      expect(find.text('Previous run'), findsNothing);
      expect(find.text('Copy output'), findsNothing);
      expect(find.text('Replay from here'), findsNothing);
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

    testWidgets('does not expose visual status chips as buttons', (
      tester,
    ) async {
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

      expect(
        find.byWidgetPredicate((widget) {
          return widget is Semantics &&
              widget.properties.label == 'Output captured' &&
              widget.properties.button == true;
        }),
        findsNothing,
      );
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
      expect(find.text('exit 1'), findsOneWidget);
      expect(find.text('Output captured'), findsOneWidget);
      expect(find.text('Replay context'), findsOneWidget);
      expect(find.text('Failure snapshot'), findsOneWidget);
      expect(find.text('Previous run'), findsOneWidget);
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

      expect(find.text('/repo'), findsOneWidget);
      expect(find.text('842ms'), findsOneWidget);
      expect(find.text('rows 12-18'), findsOneWidget);
      expect(
        find.byKey(const Key('shell-command-block-terminal-output-metadata')),
        findsOneWidget,
      );
      expect(find.byType(terminal.TerminalFramePreview), findsOneWidget);
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

      expect(commandTop - blockTop, lessThan(24));
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
              cwd: '/repo',
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('shell-command-input-field')),
        'ls -al',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitted, ['ls -al']);
      expect(controller.text, isEmpty);
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

ShellCommandBlockOverlayItem _overlayItem({
  required String id,
  String command = 'flutter test',
  int rowOffset = 0,
  int rowSpan = 1,
  bool active = false,
  bool showDiffAction = false,
  String? cwd,
  String durationLabel = '--',
  String outputPreview = '',
  String outputRangeLabel = '',
  List<terminal.TerminalRow> terminalRows = const <terminal.TerminalRow>[],
  int terminalViewportCols = 0,
}) {
  return ShellCommandBlockOverlayItem(
    id: id,
    command: command,
    terminalRows: terminalRows,
    terminalViewportCols: terminalViewportCols,
    rowOffset: rowOffset,
    rowSpan: rowSpan,
    status: ShellCommandBlockStatus.failed,
    statusLabel: 'exit 1',
    active: active,
    cwd: cwd,
    durationLabel: durationLabel,
    outputPreview: outputPreview,
    outputRangeLabel: outputRangeLabel,
    showFailureSnapshotAction: true,
    showReplayAction: true,
    showDiffAction: showDiffAction,
  );
}

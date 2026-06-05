import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlocksOverlay', () {
    testWidgets('renders active failed block actions', (tester) async {
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
      expect(find.text('Copy output'), findsOneWidget);
      expect(find.text('Replay from here'), findsOneWidget);
      expect(find.text('Save failure snapshot'), findsOneWidget);
      expect(find.text('Compare last run'), findsNothing);
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

      expect(find.text('Copy output'), findsNothing);
    });

    testWidgets('does not consume pointer events', (tester) async {
      var taps = 0;
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks([
        _overlayItem(id: 'cmd-pointer', active: true, rowSpan: 3),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 140,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps += 1,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned.fill(
                    child: ShellCommandBlocksOverlay(
                      viewModel: viewModel,
                      rowHeight: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(
        tester.getCenter(
          find.byKey(const Key('shell-command-block-cmd-pointer')),
        ),
      );
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('does not expose visual action chips as buttons', (
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
              widget.properties.label == 'Copy output' &&
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
      expect(find.text('Copy output'), findsNothing);
      expect(find.text('Replay from here'), findsNothing);
      expect(find.text('Save failure snapshot'), findsNothing);
      expect(find.text('Compare last run'), findsNothing);
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

      expect(tester.getTopLeft(blockFinder), const Offset(32, 48));
      expect(tester.getSize(blockFinder).width, 284);
    });
  });
}

ShellCommandBlockOverlayItem _overlayItem({
  required String id,
  String command = 'flutter test',
  int rowOffset = 0,
  int rowSpan = 1,
  bool active = false,
  bool showDiffAction = false,
}) {
  return ShellCommandBlockOverlayItem(
    id: id,
    command: command,
    rowOffset: rowOffset,
    rowSpan: rowSpan,
    status: ShellCommandBlockStatus.failed,
    statusLabel: 'exit 1',
    active: active,
    showFailureSnapshotAction: true,
    showReplayAction: true,
    showDiffAction: showDiffAction,
  );
}

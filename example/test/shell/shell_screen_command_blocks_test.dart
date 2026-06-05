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
  });
}

import 'package:app/features/productivity/shell_productivity_models.dart';
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
}

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

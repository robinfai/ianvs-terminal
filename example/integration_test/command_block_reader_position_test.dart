import 'dart:convert';
import 'dart:io';

import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native reader opens the cited row after font measurement', (
    tester,
  ) async {
    ensureMacosIntegrationTestFramesEnabled(tester.binding);
    final controller = CommandBlockController(
      request: (query) {
        final offset = query['offset'] as int? ?? 0;
        final limit = (query['limit'] as int? ?? 64).clamp(1, 128);
        final end = (offset + limit).clamp(0, 600);
        final block = <String, Object?>{
          'id': 'native-position',
          'command': 'fixture 600 rows',
          'cwd': '/private/tmp',
          'exitCode': 0,
          'running': false,
          'columns': 203,
          'totalLines': 600,
          'offset': offset,
          'nextOffset': end < 600 ? end : null,
          'lines': [
            for (var i = offset; i < end; i++)
              {'index': i, 'source_row': i + 9, 'text': 'ROW_${i + 1}'},
          ],
        };
        return query['id'] == null
            ? {
                'blocks': [block],
              }
            : {'block': block};
      },
    )..refresh();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommandBlockReader(
                context,
                controller: controller,
                id: 'native-position',
                initialRow: 466,
              ),
              child: const Text('Open evidence'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open evidence'));
    await tester.pumpAndSettle();
    final viewport = tester.widget<TerminalViewport>(
      find.byType(TerminalViewport).first,
    );
    final cell = viewport.controller.measuredCellSize!;
    final scroll = tester
        .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
        .controller!;
    final row = (scroll.offset - 8) / cell.height;
    const evidence = String.fromEnvironment('TRAIL_READER_POSITION_EVIDENCE');
    if (evidence.isNotEmpty) {
      await File(evidence).writeAsString(
        jsonEncode({
          'requested_row': 466,
          'actual_row': row,
          'cell_height': cell.height,
          'scroll_offset': scroll.offset,
        }),
      );
    }
    expect(row, closeTo(466, .5));
    await tester.pumpWidget(const SizedBox());
  });
}

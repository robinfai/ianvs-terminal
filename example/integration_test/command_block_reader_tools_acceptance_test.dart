import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidence = String.fromEnvironment('TRAIL_READER_TOOLS_EVIDENCE');
  for (final scene in [
    (name: 'M04-light-portrait', size: const Size(390, 844), dark: false),
    (name: 'M04-dark-small', size: const Size(320, 568), dark: true),
    (name: 'M04-landscape', size: const Size(568, 320), dark: false),
    (name: 'M04-short-landscape', size: const Size(568, 180), dark: true),
  ]) {
    testWidgets('Native fixed-font reader ${scene.name}', (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      await tester.binding.setSurfaceSize(scene.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final captureKey = GlobalKey();
      final controller = CommandBlockController(
        request: (query) {
          final offset = query['offset'] as int? ?? 0;
          final limit = query['limit'] as int? ?? 6;
          final end = (offset + limit).clamp(0, 600);
          final block = {
            'id': 'reader-tools',
            'command': 'cat logs/deploy.log',
            'cwd': '/workspace/trail',
            'exitCode': 0,
            'columns': 120,
            'totalLines': 600,
            'offset': offset,
            'nextOffset': end < 600 ? end : null,
            'lines': [
              for (var i = offset; i < end; i++)
                {
                  'index': i,
                  'source_row': i + 100,
                  'text': i == 130 || i == 300
                      ? 'ERROR deploy: 连接超时 · retry disabled; inspect upstream before restarting'
                      : '10:24:${(i % 60).toString().padLeft(2, '0')} INFO worker: health check completed for service trail-api',
                },
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
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildIanvsTerminalTheme(
              scene.dark ? Brightness.dark : Brightness.light,
              platform: TargetPlatform.iOS,
            ),
            builder: (context, child) =>
                MediaQuery.withNoTextScaling(child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showCommandBlockReader(
                    context,
                    controller: controller,
                    id: 'reader-tools',
                    chinese: true,
                    initialRow: 128,
                    onAttachRange: (_) {},
                  ),
                  child: const Text('Open reader'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open reader'));
      await tester.pumpAndSettle();
      final selection = tester
          .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
          .selectionController!;
      selection.setSelection(
        const TerminalSelection(
          startRow: 131,
          startCol: 0,
          endRow: 133,
          endCol: 25,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-reader-find')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('block-reader-find-query')),
        'ERROR',
      );
      await tester.pumpAndSettle();
      final output = tester.getRect(
        find.byKey(const Key('block-reader-scroll')),
      );
      expect(output.height, greaterThan(scene.size.height < 200 ? 20 : 80));
      final attach = tester.getSize(
        find.byKey(const Key('block-reader-attach')),
      );
      expect(attach.height, greaterThanOrEqualTo(44));
      final highlights = find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_TerminalViewportSurface',
          )
          .evaluate()
          .map((e) => e.findRenderObject())
          .whereType<RenderTerminalViewport>()
          .expand((r) => r.debugSearchHighlightRects);
      expect(highlights, hasLength(1));
      expect(selection.selection?.startRow, 131);
      expect(tester.takeException(), isNull);
      Future<void> capture(String suffix) async {
        if (evidence.isEmpty) return;
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidence).create(recursive: true);
        await File(
          '$evidence/${scene.name}$suffix.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await capture('');
      if (scene.name == 'M04-dark-small') {
        for (final (key, label, suffix) in [
          ('block-reader-find-clear', '清空查找文字', '-clear-hint'),
          ('block-reader-find-close', '关闭查找', '-close-hint'),
        ]) {
          await tester.longPress(find.byKey(Key(key)));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text(label), findsOneWidget);
          await capture(suffix);
          Tooltip.dismissAllToolTips();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('block-reader-find-query')),
                )
                .controller!
                .text,
            'ERROR',
          );
          expect(selection.selection?.startRow, 131);
        }
      }
      final gutter = find.byKey(const ValueKey('reader-line-numbers-1'));
      final gutterLeft = tester.getTopLeft(gutter).dx;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            ),
          )
          .controller!;
      horizontal.jumpTo(90);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(gutter).dx, closeTo(gutterLeft, .1));
      await capture('-horizontal');
      if (evidence.isNotEmpty) {
        await File('$evidence/${scene.name}.json').writeAsString(
          jsonEncode({
            'fixture':
                'synthetic logs, production reader, macOS native fonts; no physical iPhone',
            'fixed_font': true,
            'width': scene.size.width,
            'height': scene.size.height,
            'output_height': output.height,
            'attach_height': attach.height,
            'matching_row': 130,
            'painted_highlight_count': highlights.length,
            'selected_original_rows': [131, 132, 133],
            'gutter_stays_fixed_after_horizontal_scroll': true,
          }),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

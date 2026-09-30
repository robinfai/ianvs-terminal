import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

const _evidence = String.fromEnvironment('BLOCK_REVIEW_EVIDENCE_DIR');

class _Output {
  int count = 180;
  bool running = false;
  bool wide = false;
  bool evicted = false;
  String command = 'journalctl --unit api.service --since today';
  String cwd = '/srv/services/api';

  Map<String, Object?> snapshot(Map<String, Object?> request) {
    final full = request['id'] != null;
    final query = request['query'] as String? ?? '';
    if (request['regex'] == true && query == '[') {
      return {'error': 'Invalid regular expression'};
    }
    final lines = [
      for (var i = 0; i < count; i++)
        if (query.isEmpty || 'output line ${i + 1}'.contains(query))
          'output line ${i + 1}${wide ? " | 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789" : ""}',
    ];
    final start = full
        ? (request['offset'] as int? ?? 0).clamp(0, lines.length)
        : (lines.length - 48).clamp(0, lines.length);
    final end = (start + (request['limit'] as int? ?? 48)).clamp(
      start,
      lines.length,
    );
    final block = <String, Object?>{
      'id': 'review',
      'command': command,
      'cwd': cwd,
      'columns': 80,
      'running': running,
      'evicted': evicted,
      'exitCode': running ? null : 0,
      'offset': start,
      'totalLines': count,
      'matchingLines': lines.length,
      'nextOffset': end < lines.length ? end : null,
      'lines': [
        for (var i = start; i < end; i++)
          {'index': i, 'source_row': i + 100, 'text': lines[i]},
      ],
    };
    return full
        ? {'block': block}
        : {
            'blocks': [block],
          };
  }
}

Future<GlobalKey> _mount(
  WidgetTester tester,
  CommandBlockController controller, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  TargetPlatform platform = TargetPlatform.iOS,
  bool chinese = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: withVisualCaptureFonts(
          buildIanvsTerminalTheme(
            dark ? Brightness.dark : Brightness.light,
            platform: platform,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: TerminalCommandBlocksView(
            controller: controller,
            chinese: chinese,
            font: const TerminalFontConfig(family: visualCaptureMonoFont),
            onReinput: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundary;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (_evidence.isEmpty) return;
  await tester.runAsync(() async {
    final directory = Directory(_evidence);
    await directory.create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _openReader(WidgetTester tester, _Output output) async {
  await tester.tap(find.text(output.command));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('block-reader')), findsOneWidget);
}

Future<void> _openFilter(WidgetTester tester, {bool chinese = true}) async {
  await tester.tap(find.byKey(const Key('block-reader-actions')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text(chinese ? '过滤输出' : 'Filter output'),
      matching: find.byType(CheckedPopupMenuItem<String>),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);

  testWidgets('round 1 distinguishes waiting from completed empty output', (
    tester,
  ) async {
    final output = _Output()
      ..count = 0
      ..running = true
      ..command = 'sleep 5';
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(tester, controller);
    await _openReader(tester, output);
    await _capture(tester, boundary, '01-waiting');
    final waiting = find.text('等待输出…').evaluate().isNotEmpty;
    output.running = false;
    controller.refresh();
    await tester.pumpAndSettle();
    await _capture(tester, boundary, '02-completed-empty');
    expect(waiting, isTrue, reason: 'Running silence is not completed output.');
    expect(find.text('无输出'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('round 1 distinguishes no matches from an empty command', (
    tester,
  ) async {
    final output = _Output()..count = 12;
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(tester, controller, dark: true, scale: 1.3);
    await _openReader(tester, output);
    await _openFilter(tester);
    await tester.enterText(find.byType(TextField), 'not-found');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, '03-filter-empty');
    expect(find.text('无匹配结果'), findsOneWidget);
    expect(find.text('无输出'), findsNothing);
    await tester.tap(find.byTooltip('关闭过滤'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-reader-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final scene in [
    (name: 'landscape', size: const Size(844, 390), scale: 1.0, inset: 180.0),
    (
      name: 'landscape-2x',
      size: const Size(844, 390),
      scale: 2.0,
      inset: 180.0,
    ),
    (name: 'phone-2x', size: const Size(390, 844), scale: 2.0, inset: 330.0),
  ]) {
    testWidgets('round 2 filter fits ${scene.name} above the keyboard', (
      tester,
    ) async {
      final output = _Output();
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      final boundary = await _mount(
        tester,
        controller,
        size: scene.size,
        scale: scene.scale,
        dark: scene.scale > 1,
      );
      await _openReader(tester, output);
      await _openFilter(tester);
      await tester.enterText(find.byType(TextField), 'output');
      await tester.pump(const Duration(milliseconds: 200));
      tester.view.viewInsets = FakeViewPadding(bottom: scene.inset);
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '01-filter-${scene.name}');
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('关闭过滤').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(scene.size.height - scene.inset),
      );
      expect(
        tester.getSize(find.byKey(const Key('block-reader-scroll'))).height,
        greaterThanOrEqualTo(44),
        reason: 'Filtering must leave readable output above the keyboard.',
      );
      await tester.tap(find.byTooltip('关闭过滤'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets(
    'round 2 compact filter options preserve valid output on errors',
    (tester) async {
      final output = _Output();
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      final boundary = await _mount(
        tester,
        controller,
        size: const Size(844, 390),
        scale: 2,
        dark: true,
      );
      await _openReader(tester, output);
      await _openFilter(tester);
      await tester.enterText(find.byType(TextField), 'output');
      await tester.pump(const Duration(milliseconds: 200));
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-filter-options')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<CommandBlockFilter>, '正则表达式'),
      );
      await tester.pumpAndSettle();
      expect(controller.filters['review']?.regex, isTrue);
      await tester.enterText(find.byType(TextField), '[');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '02-invalid-regex');
      expect(find.text('正则无效，未更新结果'), findsOneWidget);
      expect(find.text('输出已不可用'), findsNothing);
      expect(find.byType(TerminalViewport), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('block-reader-latest')));
      await tester.pumpAndSettle();
      final visibleRows = tester
          .widgetList<TerminalViewport>(find.byType(TerminalViewport))
          .expand((view) => view.controller.frame.rows)
          .map((row) => row.text);
      expect(visibleRows, contains('output line 180'));
      expect(find.text('输出已不可用'), findsNothing);
      await tester.enterText(find.byType(TextField), 'output line 18');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(controller.errors, isEmpty);
      expect(find.byType(TerminalViewport), findsWidgets);
      await tester.tap(find.byTooltip('关闭过滤'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('round 3 latest action never covers output while reading', (
    tester,
  ) async {
    final output = _Output()..wide = true;
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(tester, controller, dark: true, scale: 2);
    await _openReader(tester, output);
    final reader = find.byKey(const Key('block-reader-scroll'));
    final latest = find.byKey(const Key('block-reader-latest'));
    final scroll = tester.widget<ListView>(reader).controller!;
    await _capture(tester, boundary, '01-reading-wide');
    expect(latest.hitTestable(), findsOneWidget);
    expect(tester.getSize(latest).height, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(latest).overlaps(tester.getRect(reader)),
      isFalse,
      reason: 'The latest-output action must not cover terminal cells.',
    );
    final top = tester.getTopLeft(reader).dy;
    await tester.dragFrom(const Offset(120, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    final reading = scroll.offset;
    controller.setAppearance(dividers: false);
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(reading, .1));
    await tester.tap(latest);
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(latest, findsNothing);
    await tester.dragFrom(Offset(120, top + 100), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(latest.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'round 3 following survives viewport resize but manual reading wins',
    (tester) async {
      final output = _Output()
        ..running = true
        ..wide = true;
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      final boundary = await _mount(tester, controller);
      await _openReader(tester, output);
      final reader = find.byKey(const Key('block-reader-scroll'));
      final scroll = tester.widget<ListView>(reader).controller!;
      expect(scroll.offset, scroll.position.maxScrollExtent);
      tester.view.physicalSize = const Size(390, 500);
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '02-live-resize');
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .1));
      await tester.dragFrom(const Offset(100, 250), const Offset(0, 180));
      await tester.pumpAndSettle();
      final reading = scroll.offset;
      output.count += 20;
      controller.refresh();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(reading, .1));
      tester.view.physicalSize = const Size(390, 420);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(reading, .1));
      await _capture(tester, boundary, '03-live-paused');
      await tester.tap(find.byKey(const Key('block-reader-latest')));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  for (final scene in [
    (name: 'small-phone', size: const Size(320, 568), keyboard: 240.0),
    (name: 'phone-safe-area', size: const Size(375, 667), keyboard: 290.0),
    (name: 'landscape-safe-area', size: const Size(844, 390), keyboard: 180.0),
  ]) {
    testWidgets('continued review filter remains usable ${scene.name}', (
      tester,
    ) async {
      final output = _Output()..evicted = true;
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      final boundary = await _mount(
        tester,
        controller,
        size: scene.size,
        scale: 2,
        dark: true,
      );
      await _openReader(tester, output);
      await _openFilter(tester);
      await tester.enterText(find.byType(TextField), 'output');
      await tester.pump(const Duration(milliseconds: 200));
      tester.view.padding = scene.size.width > scene.size.height
          ? const FakeViewPadding(left: 47, right: 47)
          : const FakeViewPadding(top: 20);
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '04-${scene.name}');
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('关闭过滤').hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('block-reader-scroll'))).height,
        greaterThanOrEqualTo(44),
        reason: 'Safe areas and history notices must leave readable output.',
      );
      final notice = find.byKey(const Key('block-reader-history-notice'));
      expect(notice.hitTestable(), findsOneWidget);
      expect(tester.getSize(notice).shortestSide, greaterThanOrEqualTo(44));
      await tester.tap(notice);
      await tester.pump();
      expect(find.text('退出码 0\n较早的输出已超出滚动历史保留范围'), findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭过滤'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets('continued review export fits small phone at large text', (
    tester,
  ) async {
    final output = _Output()..count = 12;
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(
      tester,
      controller,
      size: const Size(320, 568),
      scale: 2,
    );
    await tester.tap(find.byTooltip('命令块操作'));
    await tester.pumpAndSettle();
    final export = find.widgetWithText(PopupMenuItem<String>, '导出为 Markdown…');
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    await _capture(tester, boundary, '05-export-small-phone');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('取消').hitTestable(), findsOneWidget);
    expect(find.text('复制 Markdown').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    final contextOption = find.widgetWithText(CheckboxListTile, '目录和退出状态');
    await tester.ensureVisible(contextOption);
    await tester.pumpAndSettle();
    await tester.tap(contextOption);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(contextOption).value, isTrue);
    final preview = find.byType(SelectableText);
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(preview).data, contains(output.cwd));
    await _capture(tester, boundary, '05-export-options-scrolled');
    expect(find.text('复制 Markdown').hitTestable(), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('continued review invalid filter survives reopening the reader', (
    tester,
  ) async {
    final output = _Output()..count = 400;
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(tester, controller);
    await _openReader(tester, output);
    await _openFilter(tester);
    await tester.enterText(find.byType(TextField), 'output line 18');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('正则表达式'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '[');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await _capture(tester, boundary, '06-error-before-return');
    await tester.tap(find.byKey(const Key('block-reader-close')));
    await tester.pumpAndSettle();
    await _openReader(tester, output);
    await _capture(tester, boundary, '07-error-after-return');
    final rows = tester
        .widgetList<TerminalViewport>(find.byType(TerminalViewport))
        .expand((view) => view.controller.frame.rows)
        .map((row) => row.text);
    expect(rows, contains('output line 18'));
    expect(rows, isNot(contains('output line 1')));
    expect(find.text('正则无效，未更新结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('continued review context selector exposes a touchable menu', (
    tester,
  ) async {
    final output = _Output()..count = 12;
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(tester, controller);
    await _openReader(tester, output);
    await _openFilter(tester);
    final selector = find.byTooltip('上下文行数');
    expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(
        of: selector,
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsOneWidget,
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<int>, '3'));
    await tester.pumpAndSettle();
    expect(controller.filters['review']?.contextLines, 3);
    expect(find.text('上下文 3'), findsOneWidget);
    await _capture(tester, boundary, '08-context-selector');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'continued review English error fits small phone above keyboard',
    (tester) async {
      final output = _Output()..evicted = true;
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      final boundary = await _mount(
        tester,
        controller,
        size: const Size(320, 568),
        scale: 2,
        chinese: false,
      );
      await _openReader(tester, output);
      await _openFilter(tester, chinese: false);
      tester.view.padding = const FakeViewPadding(top: 20);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-filter-options')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<CommandBlockFilter>,
          'Regular expression',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '[');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '09-error-english-small');
      expect(find.text('Invalid regex; results unchanged'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        (tester.getCenter(find.byTooltip('Close filter')).dy -
                tester.getCenter(find.byType(EditableText)).dy)
            .abs(),
        lessThanOrEqualTo(8),
        reason: 'An error must not move filter controls away from their input.',
      );
      expect(
        tester.getSize(find.byKey(const Key('block-reader-scroll'))).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byTooltip('Close filter'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('continued review search error keeps close beside the input', (
    tester,
  ) async {
    final output = _Output();
    final controller = CommandBlockController(request: output.snapshot)
      ..refresh();
    final boundary = await _mount(
      tester,
      controller,
      size: const Size(320, 568),
      scale: 2,
      chinese: false,
    );
    await tester.tap(find.byTooltip('Find in blocks'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '[');
    await tester.tap(find.byTooltip('Regular expression'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await _capture(tester, boundary, '10-search-error-small');
    expect(find.text('Invalid regular expression'), findsOneWidget);
    expect(find.byTooltip('Close find').hitTestable(), findsOneWidget);
    expect(
      (tester.getCenter(find.byTooltip('Close find')).dy -
              tester.getCenter(find.byType(EditableText)).dy)
          .abs(),
      lessThanOrEqualTo(8),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close find'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

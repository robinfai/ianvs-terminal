import 'package:flutter/cupertino.dart' show CupertinoTextMagnifier;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import 'command_blocks_test.dart' show block;

class _Output {
  int base = 1000;
  int lineCount = 400;
  bool running = false;
  bool sparseFilter = false;
  bool evictOnNextPage = false;
  final queries = <Map<String, Object?>>[];
  String line(int i) => 'row $i · 中文';

  Map<String, Object?> request(Map<String, Object?> query) {
    queries.add(Map.of(query));
    final indices = query['query'] == 'match'
        ? sparseFilter
              ? [for (var i = 0; i < lineCount; i += 3) i]
              : [126, 128, 300]
        : [for (var i = 0; i < lineCount; i++) i];
    final offset = query['offset'] as int? ?? 0;
    final limit = (query['limit'] as int? ?? 64).clamp(1, 128);
    if (evictOnNextPage && offset > 0) base++;
    final end = (offset + limit).clamp(0, indices.length);
    final value = {
      ...block('source', lineCount: 0, running: running),
      'offset': offset,
      'totalLines': lineCount,
      'matchingLines': indices.length,
      'nextOffset': end < indices.length ? end : null,
      'lines': [
        for (final i in indices.skip(offset).take(limit))
          {
            'index': i,
            'source_row': base + i,
            'text': line(i),
            'wrapped': i == 127,
          },
      ],
    };
    return query['id'] == null
        ? {
            'blocks': [value],
          }
        : {'block': value};
  }
}

void main() {
  String? clipboard;
  setUp(() {
    clipboard = 'previous clipboard';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<CommandBlockController> mount(
    WidgetTester tester,
    _Output output, {
    bool filtered = false,
    bool phone = false,
  }) async {
    if (phone) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
    }
    final controller = CommandBlockController(request: output.request)
      ..refresh();
    addTearDown(controller.dispose);
    if (filtered) {
      controller.filter('source', const CommandBlockFilter(query: 'match'));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommandBlockReader(
                context,
                controller: controller,
                id: 'source',
                initialRow: controller.readingStates.containsKey('source')
                    ? null
                    : filtered && !output.sparseFilter
                    ? 0
                    : 124,
              ),
              child: const Text('Read'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> action(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('block-reader-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Offset rowPoint(WidgetTester tester, int row, int col) {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is TerminalViewport &&
          widget.controller.frame.rows.any((entry) => entry.sourceRow == row),
    );
    final view = tester.widget<TerminalViewport>(finder.first);
    final cell = view.controller.measuredCellSize!;
    final index = view.controller.frame.rows.indexWhere(
      (entry) => entry.sourceRow == row,
    );
    return tester.getTopLeft(finder.first) +
        Offset((col + .2) * cell.width, (index + .5) * cell.height);
  }

  for (final phone in [false, true]) {
    for (final reverse in [false, true]) {
      for (final filtered in [false, true]) {
        testWidgets(
          'reader drags and copies across pages (phone $phone, reverse $reverse, filtered $filtered)',
          (tester) async {
            final output = _Output()..sparseFilter = filtered;
            await mount(tester, output, phone: phone, filtered: filtered);
            final first = filtered ? 378 : 126;
            final last = filtered ? 390 : 130;
            final start = rowPoint(
              tester,
              reverse ? last : first,
              phone && reverse ? 5 : 0,
            );
            final end = rowPoint(tester, reverse ? first : last, phone ? 1 : 3);
            final gesture = await tester.startGesture(
              start,
              kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
            );
            if (phone) {
              await tester.pump(
                kLongPressTimeout + const Duration(milliseconds: 50),
              );
            } else {
              await tester.pump(const Duration(milliseconds: 20));
            }
            await gesture.moveTo(end);
            await tester.pump(const Duration(milliseconds: 30));
            if (phone) {
              final dragged = tester
                  .widget<CommandBlockTerminal>(
                    find.byType(CommandBlockTerminal).first,
                  )
                  .selectionController!
                  .selection!;
              expect(dragged.startRow, first);
              expect(dragged.endRow, last);
              final magnifier = tester.widget<CupertinoTextMagnifier>(
                find.byKey(terminalSelectionMagnifierKey),
              );
              expect(
                magnifier.magnifierInfo.value.currentLineBoundaries.center.dy,
                closeTo(end.dy, .01),
              );
            }
            await gesture.up();
            await tester.pumpAndSettle();
            final selection = tester
                .widget<CommandBlockTerminal>(
                  find.byType(CommandBlockTerminal).first,
                )
                .selectionController!
                .selection!;
            expect(selection.startRow, first);
            expect(selection.endRow, last);
            if (phone) {
              expect(find.byKey(terminalTouchCopyMenuItemKey), findsOneWidget);
              // Incoming state after the menu opens cannot change the captured copy.
              output.base += 10;
              await tester.tap(find.byKey(terminalTouchCopyMenuItemKey));
            } else {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
            }
            await tester.pumpAndSettle();
            final expected = filtered
                ? '${output.line(first).substring(selection.startCol)}\n${output.line(381)}\n${output.line(384)}\n${output.line(387)}\n${output.line(last).substring(0, selection.endCol)}'
                : '${output.line(first).substring(selection.startCol)}\n${output.line(127)}${output.line(128)}\n${output.line(129)}\n${output.line(last).substring(0, selection.endCol)}';
            expect(clipboard, expected);
            expect(tester.testTextInput.isVisible, isFalse);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          variant: TargetPlatformVariant({
            if (phone) TargetPlatform.iOS else TargetPlatform.macOS,
          }),
        );
      }
    }
  }

  testWidgets(
    'touch copy rejects output evicted before the menu opens',
    (tester) async {
      final output = _Output();
      await mount(tester, output, phone: true);
      final gesture = await tester.startGesture(rowPoint(tester, 126, 5));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(rowPoint(tester, 130, 1));
      output.base += 10;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(terminalTouchCopyMenuItemKey), findsNothing);
      expect(find.text('Output is no longer available'), findsWidgets);
      expect(clipboard, 'previous clipboard');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  for (final phone in [false, true]) {
    for (final upward in [false, true]) {
      for (final filtered in [false, true]) {
        testWidgets(
          'reader edge drag scrolls beyond its starting page (phone $phone, upward $upward, filtered $filtered)',
          (tester) async {
            final output = _Output()
              ..lineCount = 1600
              ..sparseFilter = filtered;
            final controller = await mount(
              tester,
              output,
              phone: phone,
              filtered: filtered,
            );
            final stride = filtered ? 3 : 1;
            final anchor = (upward ? 130 : 126) * stride;
            final page = tester.state(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is TerminalViewport &&
                        widget.controller.frame.rows.any(
                          (row) => row.sourceRow == anchor,
                        ),
                  )
                  .first,
            );
            final scroll = tester
                .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
                .controller!;
            final bounds = tester.getRect(
              find.byKey(const Key('block-reader-scroll')),
            );
            final start = rowPoint(tester, anchor, 5);
            final gesture = await tester.startGesture(
              start,
              kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
            );
            await tester.pump(
              phone
                  ? kLongPressTimeout + const Duration(milliseconds: 50)
                  : const Duration(milliseconds: 20),
            );
            final edge = Offset(
              start.dx,
              upward ? bounds.top - 24 : bounds.bottom + (phone ? -1 : 24),
            );
            final before = scroll.offset;
            await gesture.moveTo(edge);
            await tester.pump(const Duration(milliseconds: 120));
            expect(
              scroll.offset,
              upward ? lessThan(before) : greaterThan(before),
            );
            await gesture.moveTo(Offset(start.dx, bounds.center.dy));
            await tester.pump();
            final paused = scroll.offset;
            await tester.pump(const Duration(milliseconds: 200));
            expect(
              scroll.offset,
              paused,
              reason: 'Returning inside stops edge scrolling.',
            );
            await gesture.moveTo(edge);
            for (var i = 0; i < 190; i++) {
              await tester.pump(const Duration(milliseconds: 50));
              if (i == 30) {
                final beforeRefresh = scroll.offset;
                output.lineCount += 100;
                controller.refresh();
                await tester.pump();
                expect(
                  scroll.offset,
                  beforeRefresh,
                  reason:
                      'Incoming output cannot reset an active reading gesture.',
                );
              }
            }
            expect(
              page.mounted,
              isTrue,
              reason: 'The active pointer owner must survive page recycling.',
            );
            final selection = tester
                .widget<CommandBlockTerminal>(
                  find.byType(CommandBlockTerminal).first,
                )
                .selectionController!
                .selection!;
            if (upward) {
              expect(selection.startRow, 0);
              expect(selection.endRow, anchor);
            } else {
              expect(selection.startRow, anchor);
              expect(selection.endRow, greaterThan(256 * stride));
            }
            await gesture.up();
            await tester.pumpAndSettle();
            final stopped = scroll.offset;
            await tester.pump(const Duration(milliseconds: 300));
            expect(scroll.offset, stopped);
            if (phone) {
              await tester.tap(find.byKey(terminalTouchCopyMenuItemKey));
            } else {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
            }
            await tester.pumpAndSettle();
            final expected = StringBuffer();
            for (
              var row = selection.startRow;
              row <= selection.endRow;
              row += stride
            ) {
              if (row > selection.startRow && (filtered || row != 128)) {
                expected.writeln();
              }
              final line = output.line(row);
              expected.write(
                line.substring(
                  row == selection.startRow ? selection.startCol : 0,
                  row == selection.endRow ? selection.endCol : null,
                ),
              );
            }
            expect(clipboard, expected.toString());
            await tester.tap(find.byKey(const Key('block-reader-actions')));
            await tester.pumpAndSettle();
            expect(
              page.mounted,
              isFalse,
              reason: 'Inactive pages must return to normal recycling.',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            final saved = controller.readingStates['source']!;
            await tester.tap(find.byKey(const Key('block-reader-close')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Read'));
            await tester.pumpAndSettle();
            final restored = controller.readingStates['source']!;
            expect(restored.sourceRow, saved.sourceRow);
            expect(restored.pixelOffset, closeTo(saved.pixelOffset, .01));
            expect(restored.selection!.toJson(), selection.toJson());
            expect(tester.testTextInput.isVisible, isFalse);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          variant: TargetPlatformVariant({
            if (phone) TargetPlatform.iOS else TargetPlatform.macOS,
          }),
        );
      }
    }
  }

  for (final phone in [false, true]) {
    for (final unmount in [false, true]) {
      testWidgets(
        'reader edge scroll stops on cancellation or disposal (phone $phone, unmount $unmount)',
        (tester) async {
          await mount(tester, _Output(), phone: phone);
          final scroll = tester
              .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
              .controller!;
          final bounds = tester.getRect(
            find.byKey(const Key('block-reader-scroll')),
          );
          final gesture = await tester.startGesture(
            rowPoint(tester, 126, 5),
            kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
          );
          await tester.pump(
            phone
                ? kLongPressTimeout + const Duration(milliseconds: 50)
                : const Duration(milliseconds: 20),
          );
          await gesture.moveTo(Offset(bounds.left + 60, bounds.bottom - 1));
          await tester.pump(const Duration(milliseconds: 120));
          if (unmount) {
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(milliseconds: 300));
            await gesture.cancel();
          } else {
            await gesture.cancel();
            await tester.pump();
            final stopped = scroll.offset;
            await tester.pump(const Duration(milliseconds: 300));
            expect(scroll.offset, stopped);
            expect(find.byKey(terminalTouchCopyMenuItemKey), findsNothing);
            await tester.pumpWidget(const SizedBox());
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          if (phone) TargetPlatform.iOS else TargetPlatform.macOS,
        }),
      );
    }
  }

  for (final phone in [false, true]) {
    testWidgets(
      'selecting running output pauses tail following until explicitly resumed (phone $phone)',
      (tester) async {
        final output = _Output()..running = true;
        final controller = await mount(tester, output, phone: phone);
        await tester.tap(find.byKey(const Key('block-reader-latest')));
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
            .controller!;
        expect(scroll.offset, scroll.position.maxScrollExtent);
        final gesture = await tester.startGesture(
          rowPoint(tester, 396, 5),
          kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
        );
        await tester.pump(
          phone
              ? kLongPressTimeout + const Duration(milliseconds: 50)
              : const Duration(milliseconds: 20),
        );
        await gesture.moveTo(rowPoint(tester, 398, 5));
        await tester.pump();
        final before = scroll.offset;
        final sharedSelection = tester
            .widget<CommandBlockTerminal>(
              find.byType(CommandBlockTerminal).first,
            )
            .selectionController!;
        final selectedBefore = sharedSelection.selection!.toJson();
        output.lineCount += 20;
        controller.refresh();
        await tester.pumpAndSettle();
        expect(
          scroll.offset,
          before,
          reason:
              'Selected history must stay under the pointer when new output arrives.',
        );
        expect(sharedSelection.selection!.toJson(), selectedBefore);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('block-reader-latest')), findsOneWidget);
        await tester.tap(find.byKey(const Key('block-reader-latest')));
        await tester.pumpAndSettle();
        expect(scroll.offset, scroll.position.maxScrollExtent);
        output.lineCount += 20;
        controller.refresh();
        await tester.pumpAndSettle();
        expect(scroll.offset, scroll.position.maxScrollExtent);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({
        if (phone) TargetPlatform.iOS else TargetPlatform.macOS,
      }),
    );
  }

  testWidgets(
    'reader Option drag copies a rectangle across pages after horizontal scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final output = _Output();
      await mount(tester, output);
      final viewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport).first,
      );
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            ),
          )
          .controller!;
      horizontal.jumpTo(viewport.controller.measuredCellSize!.width * 3);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final gesture = await tester.startGesture(
        rowPoint(tester, 126, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(rowPoint(tester, 130, 7));
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      final selection = tester
          .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
          .selectionController!;
      expect(selection.isBlockSelection, isTrue);
      expect(selection.selection!.toJson(), {
        'start_row': 126,
        'start_col': 4,
        'end_row': 130,
        'end_col': 7,
      });
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(clipboard, '126\n127\n128\n129\n130');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('reader keyboard copies selection across native pages', (
    tester,
  ) async {
    final output = _Output();
    await mount(tester, output);
    final outputRect = tester
        .getRect(find.byType(TerminalViewport).first)
        .intersect(
          tester.getRect(find.byKey(const Key('block-reader-scroll'))),
        );
    await tester.tapAt(outputRect.topLeft + const Offset(40, 5));
    final selection = tester
        .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
        .selectionController!;
    // Copying is the behavior under test; select a known range spanning two
    // native pages independently of pointer hit testing.
    selection.setSelection(
      const TerminalSelection(
        startRow: 126,
        startCol: 4,
        endRow: 130,
        endCol: 3,
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      clipboard,
      '126 · 中文\n${output.line(127)}${output.line(128)}\n${output.line(129)}\nrow',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reader distinguishes whole output, filtered output and selection',
    (tester) async {
      final output = _Output();
      await mount(tester, output, filtered: true);
      await action(tester, 'block-reader-copy-output');
      final full = StringBuffer();
      for (var i = 0; i < 400; i++) {
        if (i > 0 && i != 128) full.writeln();
        full.write(output.line(i));
      }
      expect(clipboard, full.toString());
      await action(tester, 'block-reader-copy-filtered');
      expect(clipboard, [126, 128, 300].map(output.line).join('\n'));
      tester
          .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
          .selectionController!
          .setSelection(
            const TerminalSelection(
              startRow: 126,
              startCol: 4,
              endRow: 300,
              endCol: 3,
            ),
          );
      await tester.pump();
      await action(tester, 'block-reader-copy-selection');
      expect(clipboard, '126 · 中文\n${output.line(128)}\nrow');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'copy does not replace clipboard with a partially evicted snapshot',
    (tester) async {
      final output = _Output();
      await mount(tester, output);
      output.evictOnNextPage = true;
      await action(tester, 'block-reader-copy-output');
      expect(clipboard, 'previous clipboard');
      expect(find.text('Output is no longer available'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stale selected rows never copy replacement history', (
    tester,
  ) async {
    final output = _Output();
    await mount(tester, output);
    tester
        .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
        .selectionController!
        .setSelection(
          const TerminalSelection(
            startRow: 126,
            startCol: 0,
            endRow: 130,
            endCol: 3,
          ),
        );
    await tester.pump();
    output.base += 10;
    await action(tester, 'block-reader-copy-selection');
    expect(clipboard, 'previous clipboard');
    expect(find.text('Output is no longer available'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'column selections preserve wide characters and rectangle line breaks',
    () async {
      final controller = CommandBlockController(
        request: (_) => {
          'block': {
            ...block('source', lineCount: 0),
            'lines': [
              {
                'index': 0,
                'source_row': 100,
                'text': 'A中B🙂C',
                'wrapped': true,
              },
              {
                'index': 1,
                'source_row': 101,
                'text': 'X文Y🙂Z',
                'wrapped': false,
              },
            ],
          },
        },
      );
      addTearDown(controller.dispose);
      const selection = TerminalSelection(
        startRow: 0,
        startCol: 1,
        endRow: 1,
        endCol: 3,
      );
      expect(
        await controller.outputText('source', selection: selection),
        '中B🙂CX文',
      );
      expect(
        await controller.outputText(
          'source',
          selection: selection,
          blockSelection: true,
        ),
        '中\n文',
      );
      expect(
        await controller.outputText('source', blockSelection: true),
        'A中B🙂CX文Y🙂Z',
      );
    },
  );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/features/terminal/terminal_viewport_colors.dart';

import '../support/fake_pty_backend.dart';
import '../support/test_runtime.dart';

void main() {
  testWidgets(
    'terminal viewport maps pointer offsets to cells and caches paragraphs',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'echo hello',
                styleRuns: [TerminalStyleRun(start: 0, end: 10)],
              ),
              TerminalRow(index: 1, text: 'pwd'),
            ],
            cursor: TerminalCursor(row: 1, col: 1, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugCellForOffset(const Offset(20, 10)).row, 0);
      final buildsAfterFirstPaint = renderObject.debugParagraphBuilds;

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'echo hello'),
            TerminalRow(index: 1, text: 'pwd /tmp'),
          ],
          cursor: TerminalCursor(row: 1, col: 4, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(
        renderObject.debugParagraphBuilds,
        lessThan(buildsAfterFirstPaint + 3),
      );
      expect(controller.measuredCellSize, renderObject.debugCellSize);
      expect(controller.measuredCellSize!.width, greaterThan(0));
      expect(controller.measuredCellSize!.height, greaterThan(0));
    },
  );

  testWidgets(
    'terminal viewport maps upward wheel motion into positive scrollback deltas',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -40)),
      );
      await tester.pump();
      expect(scrollLines, isNotEmpty);
      expect(scrollLines.single.abs(), greaterThan(1));
      expect(scrollLines.single, isPositive);
    },
  );

  testWidgets('terminal viewport sends arrow keys for alternate scroll mode', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'hello')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 10,
          modes: TerminalFrameModes(
            alternateScreen: true,
            alternateScroll: true,
          ),
        ),
      );
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: testRuntime(bindings),
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );
    final scrollLines = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: scrollLines.add,
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(TerminalViewport));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 40)),
    );
    await tester.pump();

    expect(scrollLines, isEmpty);
    expect(bindings.writes, hasLength(1));
    expect(ascii.decode(bindings.writes.single), '\x1B[B\x1B[B');
  });

  testWidgets(
    'terminal viewport only rebuilds dirty row visuals for delta frames',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            frameKind: TerminalFrameKind.snapshot,
            rows: [
              TerminalRow(index: 0, text: 'alpha'),
              TerminalRow(index: 1, text: 'beta'),
            ],
            cursor: TerminalCursor(row: 1, col: 1, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: SelectionController(),
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      expect(renderObject.debugRowPictureBuildsForRow(0), 1);
      expect(renderObject.debugRowPictureBuildsForRow(1), 1);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 1, text: 'beta*')],
          cursor: TerminalCursor(row: 1, col: 2, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugRowPictureBuildsForRow(0), 1);
      expect(renderObject.debugRowPictureBuildsForRow(1), 2);
      expect(renderObject.debugLastRebuiltRowIndexes, <int>[1]);
      expect(
        controller.frame.rows.take(2).map((row) => row.text).toList(),
        <String>['alpha', 'beta*'],
      );
    },
  );

  testWidgets(
    'terminal viewport skips row visual rebuilds for cursor-only delta frames',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            frameKind: TerminalFrameKind.snapshot,
            rows: [TerminalRow(index: 0, text: 'cursor lane')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: SelectionController(),
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final rowBuildsBefore = renderObject.debugRowPictureBuildsForRow(0);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [],
          cursor: TerminalCursor(row: 0, col: 4, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugRowPictureBuildsForRow(0), rowBuildsBefore);
      expect(renderObject.debugLastRebuiltRowIndexes, isEmpty);
    },
  );

  testWidgets(
    'terminal viewport reuses row visuals when a scrolling delta shifts the viewport',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          TerminalFrameDiff.fromJson(<String, Object?>{
            'frame_kind': 'snapshot',
            'rows': <Object?>[
              <String, Object?>{
                'index': 0,
                'text': 'alpha',
                'style_runs': const <Object?>[],
              },
              <String, Object?>{
                'index': 1,
                'text': 'beta',
                'style_runs': const <Object?>[],
              },
              <String, Object?>{
                'index': 2,
                'text': 'gamma',
                'style_runs': const <Object?>[],
              },
            ],
            'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
            'viewport_rows': 3,
            'viewport_cols': 80,
            'dirty_ranges': <Object?>[
              <String, Object?>{'start': 0, 'end': 3},
            ],
            'scrollback_offset': 0,
            'scrollback_max_offset': 20,
            'viewport_start_row': 20,
          }),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: SelectionController(),
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      expect(_resolvedRowText(renderObject, 0), 'alpha');
      expect(_resolvedRowText(renderObject, 1), 'beta');
      expect(_resolvedRowText(renderObject, 2), 'gamma');

      controller.updateFrame(
        TerminalFrameDiff.fromJson(<String, Object?>{
          'frame_kind': 'delta',
          'rows': <Object?>[
            <String, Object?>{
              'index': 2,
              'text': 'delta',
              'style_runs': const <Object?>[],
            },
          ],
          'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
          'viewport_rows': 3,
          'viewport_cols': 80,
          'dirty_ranges': <Object?>[
            <String, Object?>{'start': 2, 'end': 3},
          ],
          'scrollback_offset': 0,
          'scrollback_max_offset': 21,
          'viewport_start_row': 21,
          'viewport_row_shift': -1,
        }),
      );
      await tester.pump();

      expect(renderObject.debugLastRebuiltRowIndexes, <int>[2]);
      expect(_resolvedRowText(renderObject, 0), 'beta');
      expect(_resolvedRowText(renderObject, 1), 'gamma');
      expect(_resolvedRowText(renderObject, 2), 'delta');
      final shiftedRowZeroCells = renderObject.debugResolvedCellsForRow(0);
      expect(shiftedRowZeroCells, isNotEmpty);
      for (final cell in shiftedRowZeroCells) {
        expect(
          cell.placementRect.top,
          lessThan(renderObject.debugCellSize.height / 2),
          reason:
              'shifted row 0 cells must repaint near row 0, not at old lower rows',
        );
        expect(
          cell.drawOffset.dy,
          lessThan(renderObject.debugCellSize.height),
          reason: 'shifted row 0 glyph draw offsets must stay within row 0',
        );
      }
      final shiftedRowZeroSpans = renderObject.debugBackgroundSpansForRow(0);
      for (final span in shiftedRowZeroSpans) {
        expect(
          span.rect.top,
          closeTo(0, 0.001),
          reason:
              'shifted row 0 background spans must repaint at row 0, not old row 1',
        );
      }
      final shiftedRowOneCells = renderObject.debugResolvedCellsForRow(1);
      expect(shiftedRowOneCells, isNotEmpty);
      for (final cell in shiftedRowOneCells) {
        expect(
          cell.placementRect.top,
          greaterThan(renderObject.debugCellSize.height / 2),
          reason: 'shifted row 1 cells must repaint below row 0',
        );
      }
    },
  );

  testWidgets(
    'terminal viewport repaints consecutive full-width wrapped rows without leaving a shorter middle row',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            frameKind: TerminalFrameKind.snapshot,
            rows: [
              TerminalRow(index: 0, text: '*****'),
              TerminalRow(index: 1, text: '***'),
              TerminalRow(index: 2, text: '*****'),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 4,
            viewportCols: 5,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 3)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: SelectionController(),
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      expect(_resolvedRowText(renderObject, 0), '*****');
      expect(_resolvedRowText(renderObject, 1), '***');
      expect(_resolvedRowText(renderObject, 2), '*****');
      final middleBuildsBefore = renderObject.debugRowPictureBuildsForRow(1);

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [
            TerminalRow(index: 0, text: '*****', wrapped: true),
            TerminalRow(index: 1, text: '*****', wrapped: true),
            TerminalRow(index: 2, text: '*****'),
          ],
          cursor: TerminalCursor(row: 2, col: 5, visible: true),
          viewportRows: 4,
          viewportCols: 5,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 3)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(_resolvedRowText(renderObject, 0), '*****');
      expect(_resolvedRowText(renderObject, 1), '*****');
      expect(_resolvedRowText(renderObject, 2), '*****');
      expect(
        renderObject.debugRowPictureBuildsForRow(1),
        greaterThan(middleBuildsBefore),
      );
      expect(renderObject.debugLastRebuiltRowIndexes, <int>[0, 1, 2]);
    },
  );

  testWidgets(
    'terminal viewport translates trackpad pan updates into positive scrollback deltas',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(center));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(center, pan: const Offset(0, -36)),
      );
      await tester.pump();
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(scrollLines, isNotEmpty);
      expect(scrollLines.single, isPositive);
    },
  );

  testWidgets('terminal viewport continues trackpad momentum after pan end', (
    tester,
  ) async {
    final controller = TerminalViewportController()
      ..updateFrame(
        _scrollbackFrame(
          viewportStartRow: 20,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 20,
        ),
      );

    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: testRuntime(FakePtyBackend()),
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );
    final scrollLines = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (delta) {
                scrollLines.add(delta);
                final frame = controller.frame;
                final nextOffset = (frame.scrollbackOffset + delta)
                    .clamp(0, frame.scrollbackMaxOffset)
                    .toInt();
                controller.updateFrame(
                  _scrollbackFrame(
                    viewportStartRow: frame.scrollbackMaxOffset - nextOffset,
                    scrollbackOffset: nextOffset,
                    scrollbackMaxOffset: frame.scrollbackMaxOffset,
                    viewportRows: frame.viewportRows,
                  ),
                );
              },
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(TerminalViewport));
    final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(trackpad.panZoomStart(center));
    await tester.pump();
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(center, pan: const Offset(0, -24)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(center, pan: const Offset(0, -24)),
    );
    await tester.pump();

    final scrollCountBeforeEnd = scrollLines.length;
    final offsetBeforeEnd = controller.frame.scrollbackOffset;

    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(scrollCountBeforeEnd, greaterThan(0));
    expect(scrollLines.length, greaterThan(scrollCountBeforeEnd));
    expect(controller.frame.scrollbackOffset, greaterThan(offsetBeforeEnd));
  });

  testWidgets(
    'terminal viewport momentum can carry scrollback back to bottom after a downward flick',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (delta) {
                  scrollLines.add(delta);
                  final frame = controller.frame;
                  final nextOffset = (frame.scrollbackOffset + delta)
                      .clamp(0, frame.scrollbackMaxOffset)
                      .toInt();
                  controller.updateFrame(
                    _scrollbackFrame(
                      viewportStartRow: frame.scrollbackMaxOffset - nextOffset,
                      scrollbackOffset: nextOffset,
                      scrollbackMaxOffset: frame.scrollbackMaxOffset,
                      viewportRows: frame.viewportRows,
                    ),
                  );
                },
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(center));
      await tester.pump();
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(center, pan: const Offset(0, 24)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(center, pan: const Offset(0, 24)),
      );
      await tester.pump();

      final scrollCountBeforeEnd = scrollLines.length;
      final offsetBeforeEnd = controller.frame.scrollbackOffset;

      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(scrollCountBeforeEnd, greaterThan(0));
      expect(offsetBeforeEnd, greaterThan(0));
      expect(scrollLines.length, greaterThan(scrollCountBeforeEnd));
      expect(scrollLines.where((delta) => delta.isNegative), isNotEmpty);
      expect(controller.frame.scrollbackOffset, 0);
    },
  );

  testWidgets(
    'terminal viewport sends SGR mouse press bytes when mouse mode is enabled',
    (tester) async {
      final bindings = FakePtyBackend();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'sgr',
            ),
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: SelectionController(),
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;
      await tester.tapAt(
        renderObject.localToGlobal(
          Offset(cellSize.width / 2, cellSize.height / 2),
        ),
      );
      await tester.pump();

      expect(bindings.writes, isNotEmpty);
      expect(ascii.decode(bindings.writes.first), '\x1B[<0;1;1M');
    },
  );

  testWidgets(
    'terminal viewport keeps local selection when mouse mode is off',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello world')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;
      await tester.dragFrom(
        renderObject.localToGlobal(
          Offset(cellSize.width / 2, cellSize.height / 2),
        ),
        Offset(cellSize.width * 4, 0),
      );
      await tester.pump();

      expect(bindings.writes, isEmpty);
      expect(selectionController.selection, isNotNull);
    },
  );

  testWidgets(
    'terminal viewport double-click selects a whole xterm-style word',
    (tester) async {
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'alpha beta gamma')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      await _mouseDoubleClickAt(
        tester,
        renderObject.localToGlobal(
          Offset(cellSize.width * 7, cellSize.height / 2),
        ),
      );

      expect(selectionController.textForFrame(controller.frame), 'beta');
    },
  );

  testWidgets(
    'terminal viewport double-click selects a contiguous whitespace run',
    (tester) async {
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'alpha   beta')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      await _mouseDoubleClickAt(
        tester,
        renderObject.localToGlobal(
          Offset(cellSize.width * 6, cellSize.height / 2),
        ),
      );

      expect(selectionController.textForFrame(controller.frame), '   ');
    },
  );

  testWidgets('terminal viewport double-click drag expands selection by word', (
    tester,
  ) async {
    final selectionController = SelectionController();
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'alpha beta gamma')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(FakePtyBackend()),
                readFrame: () => controller.frame,
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final renderObject = _terminalRenderObject(tester);
    final cellSize = renderObject.debugCellSize;
    await _mouseDoubleClickDrag(
      tester,
      start: renderObject.localToGlobal(
        Offset(cellSize.width * 7, cellSize.height / 2),
      ),
      end: renderObject.localToGlobal(
        Offset(cellSize.width * 2, cellSize.height / 2),
      ),
    );

    expect(selectionController.textForFrame(controller.frame), 'alpha beta');
  });

  testWidgets(
    'terminal viewport double-click word selection follows wrapped logical rows',
    (tester) async {
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(index: 0, text: 'super', wrapped: true),
              TerminalRow(index: 1, text: 'word'),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      await _mouseDoubleClickAt(
        tester,
        renderObject.localToGlobal(
          Offset(cellSize.width, cellSize.height * 1.5),
        ),
      );

      expect(selectionController.textForFrame(controller.frame), 'superword');
    },
  );

  testWidgets(
    'terminal viewport keeps option-drag block selection by default',
    (tester) async {
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello world')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(
        renderObject.localToGlobal(
          Offset(cellSize.width / 2, cellSize.height / 2),
        ),
        Offset(cellSize.width * 4, cellSize.height),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      expect(selectionController.selection, isNotNull);
      expect(selectionController.isBlockSelection, isTrue);
    },
  );

  testWidgets('terminal viewport can disable option-drag block selection', (
    tester,
  ) async {
    final selectionController = SelectionController();
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'hello world')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(FakePtyBackend()),
                readFrame: () => controller.frame,
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              optionDragMode: TerminalOptionDragMode.normalSelection,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(
      renderObject.localToGlobal(
        Offset(cellSize.width / 2, cellSize.height / 2),
      ),
      Offset(cellSize.width * 4, cellSize.height),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(selectionController.selection, isNotNull);
    expect(selectionController.isBlockSelection, isFalse);
  });

  testWidgets('terminal viewport copies selection on pointer up when enabled', (
    tester,
  ) async {
    final copied = <String>[];
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'hello world')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: SelectionController(),
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(FakePtyBackend()),
                readFrame: () => controller.frame,
                readSelection: () => 'hello',
                copySelection: (text) async => copied.add(text),
                readClipboard: () async => '',
              ),
              copyOnSelect: true,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    await tester.dragFrom(
      renderObject.localToGlobal(
        Offset(cellSize.width / 2, cellSize.height / 2),
      ),
      Offset(cellSize.width * 4, 0),
    );
    await tester.pump();

    expect(copied, ['hello']);
  });

  testWidgets(
    'terminal viewport does not auto-scroll while the pointer stays inside the viewport',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
          ),
        );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, cellSize.height * 3.5),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(
        renderObject.localToGlobal(Offset(cellSize.width * 2, 4)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, renderObject.size.height - 4),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      expect(scrollLines, isEmpty);
      expect(selectionController.selection, isNotNull);

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'terminal viewport auto-scrolls selection upward only after the pointer leaves the viewport',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
          ),
        );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (delta) {
                  scrollLines.add(delta);
                  final frame = controller.frame;
                  final nextOffset = (frame.scrollbackOffset + delta)
                      .clamp(0, frame.scrollbackMaxOffset)
                      .toInt();
                  controller.updateFrame(
                    _scrollbackFrame(
                      viewportStartRow: frame.scrollbackMaxOffset - nextOffset,
                      scrollbackOffset: nextOffset,
                      scrollbackMaxOffset: frame.scrollbackMaxOffset,
                    ),
                  );
                },
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, cellSize.height * 3.5),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(
        renderObject.localToGlobal(Offset(cellSize.width * 2, -4)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrollLines, isNotEmpty);
      expect(scrollLines.last, isPositive);
      expect(selectionController.selection, isNotNull);
      expect(selectionController.selection!.startRow, lessThan(13));

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'terminal viewport auto-scrolls selection downward only after the pointer leaves the viewport',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
          ),
        );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (delta) {
                  scrollLines.add(delta);
                  final frame = controller.frame;
                  final nextOffset = (frame.scrollbackOffset + delta)
                      .clamp(0, frame.scrollbackMaxOffset)
                      .toInt();
                  controller.updateFrame(
                    _scrollbackFrame(
                      viewportStartRow: frame.scrollbackMaxOffset - nextOffset,
                      scrollbackOffset: nextOffset,
                      scrollbackMaxOffset: frame.scrollbackMaxOffset,
                    ),
                  );
                },
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, cellSize.height * 1.5),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, renderObject.size.height + 4),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrollLines, isNotEmpty);
      expect(scrollLines.last, isNegative);
      expect(selectionController.selection, isNotNull);
      expect(selectionController.selection!.endRow, greaterThan(11));

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets('terminal viewport stops edge auto-scroll after pointer up', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    final selectionController = SelectionController();
    final controller = TerminalViewportController()
      ..updateFrame(
        _scrollbackFrame(
          viewportStartRow: 10,
          scrollbackOffset: 10,
          scrollbackMaxOffset: 20,
        ),
      );
    final scrollLines = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(bindings),
                readFrame: () => controller.frame,
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              onScrollLines: (delta) {
                scrollLines.add(delta);
                final frame = controller.frame;
                final nextOffset = (frame.scrollbackOffset + delta)
                    .clamp(0, frame.scrollbackMaxOffset)
                    .toInt();
                controller.updateFrame(
                  _scrollbackFrame(
                    viewportStartRow: frame.scrollbackMaxOffset - nextOffset,
                    scrollbackOffset: nextOffset,
                    scrollbackMaxOffset: frame.scrollbackMaxOffset,
                  ),
                );
              },
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    final gesture = await tester.startGesture(
      renderObject.localToGlobal(
        Offset(cellSize.width * 2, cellSize.height * 3.5),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await gesture.moveTo(
      renderObject.localToGlobal(Offset(cellSize.width * 2, -4)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final scrollCountBeforeUp = scrollLines.length;

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(scrollCountBeforeUp, greaterThan(0));
    expect(scrollLines.length, scrollCountBeforeUp);
  });

  testWidgets(
    'terminal viewport does not start local edge auto-scroll when mouse mode is enabled',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
            modes: const TerminalFrameModes(
              mouseMode: 'button_event',
              mouseEncoding: 'sgr',
            ),
          ),
        );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2, cellSize.height * 3.5),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(
        renderObject.localToGlobal(Offset(cellSize.width * 2, -4)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      expect(scrollLines, isEmpty);
      expect(selectionController.selection, isNull);

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'terminal viewport ignores local double-click word selection when mouse mode is enabled',
    (tester) async {
      final bindings = FakePtyBackend();
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'alpha beta')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(
              mouseMode: 'button_event',
              mouseEncoding: 'sgr',
            ),
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(bindings),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      await _mouseDoubleClickAt(
        tester,
        renderObject.localToGlobal(
          Offset(cellSize.width * 7, cellSize.height / 2),
        ),
      );

      expect(selectionController.selection, isNull);
      expect(bindings.writes, isNotEmpty);
    },
  );

  testWidgets(
    'terminal viewport sends focus tracking bytes on focus gain and loss',
    (tester) async {
      final bindings = FakePtyBackend();
      final focusNode = FocusNode(debugLabel: 'test-terminal-focus');
      addTearDown(focusNode.dispose);
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(focusTracking: true),
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 120,
                  child: TerminalViewport(
                    focusNode: focusNode,
                    controller: controller,
                    selectionController: SelectionController(),
                    inputController: TerminalInputController(
                      sessionId: '1',
                      runtime: testRuntime(bindings),
                      readFrame: () => controller.frame,
                      readSelection: () => '',
                      copySelection: (_) async {},
                      readClipboard: () async => '',
                    ),
                    onScrollLines: (_) {},
                    onScrollToOffset: (_) {},
                  ),
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(bindings.writes.map(ascii.decode).toList(), ['\x1B[I', '\x1B[O']);
    },
  );

  testWidgets('terminal viewport opens OSC 8 hyperlink on explicit tap', (
    tester,
  ) async {
    final opened = <String>[];
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'open docs')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          hyperlinks: [
            TerminalHyperlinkRange(
              row: 0,
              startCol: 5,
              endCol: 9,
              uri: 'https://example.com/docs',
            ),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: SelectionController(),
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(FakePtyBackend()),
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              onOpenLink: opened.add,
            ),
          ),
        ),
      ),
    );

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    await _mouseClickAt(
      tester,
      renderObject.localToGlobal(
        Offset(cellSize.width * 6, cellSize.height / 2),
      ),
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();

    expect(opened, ['https://example.com/docs']);
  });

  testWidgets('terminal viewport opens visible URL hints on explicit tap', (
    tester,
  ) async {
    final opened = <String>[];
    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'see https://example.com/path now'),
          ],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 200,
            child: TerminalViewport(
              controller: controller,
              selectionController: SelectionController(),
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: testRuntime(FakePtyBackend()),
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              onOpenLink: opened.add,
            ),
          ),
        ),
      ),
    );

    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final cellSize = renderObject.debugCellSize;
    await _mouseClickAt(
      tester,
      renderObject.localToGlobal(
        Offset(cellSize.width * 8, cellSize.height / 2),
      ),
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();

    expect(opened, ['https://example.com/path']);
  });

  testWidgets(
    'terminal viewport does not open hyperlinks during a double-click selection sequence',
    (tester) async {
      final opened = <String>[];
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'open docs')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            hyperlinks: [
              TerminalHyperlinkRange(
                row: 0,
                startCol: 5,
                endCol: 9,
                uri: 'https://example.com/docs',
              ),
            ],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                onOpenLink: opened.add,
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      await _mouseDoubleClickAt(
        tester,
        renderObject.localToGlobal(
          Offset(cellSize.width * 6, cellSize.height / 2),
        ),
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pump();

      expect(opened, isEmpty);
      expect(selectionController.textForFrame(controller.frame), 'docs');
    },
  );

  testWidgets(
    'terminal viewport does not open hyperlinks while drag-selecting',
    (tester) async {
      final opened = <String>[];
      final selectionController = SelectionController();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'open docs')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            hyperlinks: [
              TerminalHyperlinkRange(
                row: 0,
                startCol: 5,
                endCol: 9,
                uri: 'https://example.com/docs',
              ),
            ],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: TerminalInputController(
                  sessionId: '1',
                  runtime: testRuntime(FakePtyBackend()),
                  readFrame: () => controller.frame,
                  readSelection: () => '',
                  copySelection: (_) async {},
                  readClipboard: () async => '',
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                onOpenLink: opened.add,
              ),
            ),
          ),
        ),
      );

      final renderObject = _terminalRenderObject(tester);
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 6, cellSize.height / 2),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 8, cellSize.height / 2),
        ),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(kDoubleTapTimeout);

      expect(opened, isEmpty);
      expect(selectionController.selection, isNotNull);
    },
  );

  test(
    'terminal text style keeps a nerd-font fallback ahead of generic system fonts',
    () {
      expect(terminalPrimaryFontFamily, 'JetBrainsMono Nerd Font Mono');
      expect(terminalFontFamilyFallback, isNotEmpty);
      expect(terminalFontFamilyFallback.first, 'Menlo');
      expect(terminalFontFamilyFallback, contains('Apple Symbols'));
    },
  );

  testWidgets('terminal viewport defaults follow the light theme colors', (
    tester,
  ) async {
    final renderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.light,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ab')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    expect(
      renderObject.debugColors.canvasBackground.toARGB32(),
      const Color(0xFFF8F7F2).toARGB32(),
    );
    expect(
      renderObject.debugResolvedCellsForRow(0).first.foreground.toARGB32(),
      const Color(0xFF111111).toARGB32(),
    );
  });

  testWidgets('terminal viewport defaults follow the dark theme colors', (
    tester,
  ) async {
    final renderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.dark,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ab')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    expect(
      renderObject.debugColors.canvasBackground.toARGB32(),
      const Color(0xFF050608).toARGB32(),
    );
    expect(
      renderObject.debugResolvedCellsForRow(0).first.foreground.toARGB32(),
      const Color(0xFFF8FAFC).toARGB32(),
    );
  });

  testWidgets(
    'terminal viewport invalidates cached default colors on theme switch',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ab')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      await _pumpTerminalViewportWithController(
        tester,
        controller: controller,
        themeMode: ThemeMode.dark,
      );
      var renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      expect(
        renderObject.debugResolvedCellsForRow(0).first.foreground.toARGB32(),
        const Color(0xFFF8FAFC).toARGB32(),
      );

      await _pumpTerminalViewportWithController(
        tester,
        controller: controller,
        themeMode: ThemeMode.light,
      );
      renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(
        renderObject.debugColors.foreground.toARGB32(),
        const Color(0xFF111111).toARGB32(),
      );
      expect(
        renderObject.debugResolvedCellsForRow(0).first.foreground.toARGB32(),
        const Color(0xFF111111).toARGB32(),
      );
    },
  );

  testWidgets(
    'terminal viewport keeps explicit style colors above theme defaults',
    (tester) async {
      final renderObject = await _pumpThemedTerminalViewport(
        tester,
        themeMode: ThemeMode.light,
        frame: const TerminalFrameDiff(
          rows: [
            TerminalRow(
              index: 0,
              text: 'ab',
              styleRuns: [
                TerminalStyleRun(
                  start: 0,
                  end: 1,
                  foreground: Color(0xFFABCDEF),
                  background: Color(0xFF123456),
                ),
              ],
            ),
          ],
          cursor: TerminalCursor(row: 0, col: 2, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(
        cells[0].foreground.toARGB32(),
        const Color(0xFFABCDEF).toARGB32(),
      );
      expect(
        cells[0].background?.toARGB32(),
        const Color(0xFF123456).toARGB32(),
      );
      expect(
        cells[1].foreground.toARGB32(),
        const Color(0xFF111111).toARGB32(),
      );
      expect(cells[1].background, isNull);
    },
  );

  testWidgets(
    'terminal viewport resolves powerline rows into terminal cells and keeps cursor aligned by cell column',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: '󰀵a',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 1,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 1,
                    end: 2,
                    foreground: Color(0xFFFAB387),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 2,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(cells.map((cell) => cell.text).toList(), ['󰀵', '', 'a']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.powerlineCustom,
        TerminalGlyphClass.text,
      ]);
      expect(cells.map((cell) => cell.background?.toARGB32()).toList(), [
        const Color(0xFFF38BA8).toARGB32(),
        const Color(0xFFF38BA8).toARGB32(),
        const Color(0xFFFAB387).toARGB32(),
      ]);
      expect(cells.map((cell) => cell.foreground.toARGB32()).toList(), [
        const Color(0xFF11111B).toARGB32(),
        const Color(0xFFFAB387).toARGB32(),
        const Color(0xFF11111B).toARGB32(),
      ]);

      final cursorRect = renderObject.debugCursorRect!;
      expect(cursorRect.left, 3 * renderObject.debugCellSize.width);
      expect(cursorRect.width, renderObject.debugCellSize.width);
    },
  );

  testWidgets(
    'terminal viewport positions regular glyphs using shared row text metrics',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'A')],
            cursor: TerminalCursor(row: 0, col: 1, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cell = renderObject.debugResolvedCellsForRow(0).single;
      final rowTextMetrics = renderObject.debugRowTextMetrics;
      final targetBaselineY = _snapToDevicePixel(
        ((renderObject.debugCellSize.height - rowTextMetrics.textHeight) / 2) +
            rowTextMetrics.ascent,
        tester.view.devicePixelRatio,
      );

      expect(cell.placementPolicy, TerminalGlyphPlacementPolicy.baselineLeft);
      expect(cell.usesCustomGeometry, isFalse);
      expect(cell.drawOffset.dx, 0);
      expect(rowTextMetrics.textHeight, greaterThan(0));
      expect(
        cell.drawOffset.dy,
        closeTo(targetBaselineY - cell.glyphBaseline, 0.001),
      );
      expect(cell.baselineY, closeTo(targetBaselineY, 0.001));
      expect(
        cell.drawOffset.dy + cell.glyphBaseline,
        closeTo(cell.baselineY, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport aligns letters and nerd-font glyphs to the same baseline',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'A󰀵B')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);

      expect(cells.map((cell) => cell.text).toList(), ['A', '󰀵', 'B']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.text,
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.text,
      ]);
      expect(cells.every((cell) => !cell.usesCustomGeometry), isTrue);
      expect(cells[0].baselineY, closeTo(cells[1].baselineY, 0.001));
      expect(cells[1].baselineY, closeTo(cells[2].baselineY, 0.001));
      expect(
        cells[0].drawOffset.dy + cells[0].glyphBaseline,
        closeTo(cells[0].baselineY, 0.001),
      );
      expect(
        cells[1].drawOffset.dy + cells[1].glyphBaseline,
        closeTo(cells[1].baselineY, 0.001),
      );
      expect(
        cells[2].drawOffset.dy + cells[2].glyphBaseline,
        closeTo(cells[2].baselineY, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport keeps supplementary PUA icons out of the powerline lane',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '󰀵')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);

      expect(cells.map((cell) => cell.text).toList(), ['󰀵', '']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.powerlineCustom,
      ]);
      expect(cells[0].usesCustomGeometry, isFalse);
      expect(cells[1].usesCustomGeometry, isTrue);
    },
  );

  testWidgets(
    'terminal viewport gives powerline glyphs directional placement and bleed',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: '',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 1,
                    foreground: Color(0xFFFAB387),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 1,
                    end: 2,
                    foreground: Color(0xFFF38BA8),
                    background: Color(0xFFFAB387),
                  ),
                  TerminalStyleRun(
                    start: 2,
                    end: 3,
                    foreground: Color(0xFFB4BEFE),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFFF38BA8),
                    background: Color(0xFFB4BEFE),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;
      final dpr = tester.view.devicePixelRatio;

      expect(cells.map((cell) => cell.placementPolicy).toList(), [
        TerminalGlyphPlacementPolicy.powerlineRightArrow,
        TerminalGlyphPlacementPolicy.powerlineLeftArrow,
        TerminalGlyphPlacementPolicy.powerlineLeftCap,
        TerminalGlyphPlacementPolicy.powerlineRightCap,
      ]);
      expect(cells.every((cell) => cell.usesCustomGeometry), isTrue);
      expect(cells[0].placementRect.right, greaterThan(cellWidth));
      expect(cells[1].placementRect.left, lessThan(cellWidth));
      expect(cells[2].placementRect.left, lessThan(2 * cellWidth));
      expect(
        cells[2].placementRect.right,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(
        cells[3].placementRect.left,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(cells[3].placementRect.right, greaterThan(4 * cellWidth));
      expect(
        cells[2].placementRect.width,
        lessThan(cells[0].placementRect.width),
      );
      expect(
        cells[3].placementRect.width,
        lessThan(cells[1].placementRect.width),
      );
      expect(cells[0].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[0].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[1].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[1].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[2].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[2].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[3].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[3].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport coalesces adjacent same-color cells into continuous background spans',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'abc',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final spans = renderObject.debugBackgroundSpansForRow(0);
      final cellWidth = renderObject.debugCellSize.width;
      final dpr = tester.view.devicePixelRatio;

      expect(spans, hasLength(2));
      expect(spans[0].startColumn, 0);
      expect(spans[0].endColumn, 3);
      expect(spans[0].rect.left, 0);
      expect(
        spans[0].rect.width,
        closeTo(
          _snapToDevicePixel(3 * cellWidth, dpr) - _snapToDevicePixel(0, dpr),
          0.001,
        ),
      );
      expect(spans[1].startColumn, 3);
      expect(spans[1].endColumn, 4);
      expect(
        spans[1].rect.left,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(
        spans[1].rect.width,
        closeTo(
          _snapToDevicePixel(4 * cellWidth, dpr) -
              _snapToDevicePixel(3 * cellWidth, dpr),
          0.001,
        ),
      );
    },
  );

  testWidgets(
    'terminal viewport advances the next glyph after a wide CJK character',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '你a')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;

      expect(cells, hasLength(2));
      expect(cells[0].text, '你');
      expect(cells[0].column, 0);
      expect(cells[1].text, 'a');
      expect(cells[1].column, 2);
      expect(cells[1].drawOffset.dx, closeTo(2 * cellWidth, 0.001));
    },
  );

  testWidgets(
    'terminal viewport keeps emoji zwj clusters on one wide glyph slot',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '👨‍👩‍👧a')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;

      expect(cells, hasLength(2));
      expect(cells[0].text, '👨‍👩‍👧');
      expect(cells[0].column, 0);
      expect(cells[1].text, 'a');
      expect(cells[1].column, 2);
      expect(cells[1].drawOffset.dx, closeTo(2 * cellWidth, 0.001));
    },
  );

  testWidgets(
    'terminal viewport snaps baselines, background spans, and powerline rects to device pixels',
    (tester) async {
      tester.view.devicePixelRatio = 2.5;
      tester.view.physicalSize = const Size(2400, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'A󰀵B',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final spans = renderObject.debugBackgroundSpansForRow(0);
      final dpr = tester.view.devicePixelRatio;

      for (final cell in cells.where((cell) => !cell.usesCustomGeometry)) {
        expect(
          cell.drawOffset.dy + cell.glyphBaseline,
          closeTo(cell.baselineY, 0.001),
        );
        expect(_isSnappedToDevicePixel(cell.baselineY, dpr), isTrue);
      }
      for (final cell in cells.where((cell) => cell.usesCustomGeometry)) {
        expect(_isSnappedToDevicePixel(cell.baselineY, dpr), isTrue);
      }
      for (final span in spans) {
        _expectRectSnapped(span.rect, dpr);
      }
      for (final cell in cells.where((cell) => cell.usesCustomGeometry)) {
        _expectRectSnapped(cell.placementRect, dpr);
      }
    },
  );

  testWidgets(
    'terminal cursor blinks while focused and the frame cursor is visible',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      addTearDown(focusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isFalse);

      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isTrue);
    },
  );

  testWidgets('terminal cursor defaults to a block shape', (tester) async {
    final renderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.dark,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    final cursorRect = renderObject.debugCursorRect!;
    final cellSize = renderObject.debugCellSize;

    expect(cursorRect.left, 2 * cellSize.width);
    expect(cursorRect.width, cellSize.width);
    expect(cursorRect.height, cellSize.height);
    expect(cursorRect.top, 0);
  });

  testWidgets('terminal viewport paints underline cursor overrides', (
    tester,
  ) async {
    final renderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.dark,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
      cursor: const TerminalProfileCursor(shape: TerminalCursorShape.underline),
    );

    final cursorRect = renderObject.debugCursorRect!;
    final cellSize = renderObject.debugCellSize;

    expect(cursorRect.left, 2 * cellSize.width);
    expect(cursorRect.width, cellSize.width);
    expect(cursorRect.height, lessThan(cellSize.height / 3));
    expect(cursorRect.bottom, cellSize.height);
  });

  testWidgets('terminal viewport updates measured cells for font overrides', (
    tester,
  ) async {
    final defaultRenderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.dark,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
    final defaultCellHeight = defaultRenderObject.debugCellSize.height;

    final largerFontRenderObject = await _pumpThemedTerminalViewport(
      tester,
      themeMode: ThemeMode.dark,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 2, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
      font: const TerminalProfileFont(size: 18, lineHeight: 1.8),
    );

    expect(
      largerFontRenderObject.debugCellSize.height,
      greaterThan(defaultCellHeight),
    );
  });

  testWidgets(
    'terminal cursor stops blinking and resets visible when focus is lost',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      final nextFocusNode = FocusNode(debugLabel: 'terminal-test-next-focus');
      addTearDown(focusNode.dispose);
      addTearDown(nextFocusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 200,
                  child: TerminalViewport(
                    controller: controller,
                    selectionController: selectionController,
                    inputController: inputController,
                    onScrollLines: (_) {},
                    onScrollToOffset: (_) {},
                    focusNode: focusNode,
                  ),
                ),
                Focus(
                  focusNode: nextFocusNode,
                  child: const SizedBox(width: 1, height: 1),
                ),
              ],
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      nextFocusNode.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
      expect(nextFocusNode.hasFocus, isTrue);

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isTrue);
    },
  );

  testWidgets(
    'terminal cursor resets visible when the frame cursor hides and shows again',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      addTearDown(focusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 2, visible: false),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 2, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);
    },
  );

  testWidgets(
    'terminal cursor hides when scrollback leaves the live bottom viewport',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 20,
            scrollbackOffset: 0,
            scrollbackMaxOffset: 20,
          ),
        );

      await _pumpTerminalViewportWithController(
        tester,
        controller: controller,
        themeMode: ThemeMode.dark,
      );

      final renderObject = _terminalRenderObject(tester);

      expect(renderObject.debugCursorVisible, isTrue);
      expect(renderObject.debugCursorRect, isNotNull);

      controller.updateFrame(
        _scrollbackFrame(
          viewportStartRow: 10,
          scrollbackOffset: 10,
          scrollbackMaxOffset: 20,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isFalse);
      expect(renderObject.debugCursorRect, isNull);
    },
  );

  testWidgets(
    'terminal cursor reappears after returning from scrollback to bottom',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          _scrollbackFrame(
            viewportStartRow: 10,
            scrollbackOffset: 10,
            scrollbackMaxOffset: 20,
          ),
        );

      await _pumpTerminalViewportWithController(
        tester,
        controller: controller,
        themeMode: ThemeMode.dark,
      );

      final renderObject = _terminalRenderObject(tester);

      expect(renderObject.debugCursorVisible, isFalse);
      expect(renderObject.debugCursorRect, isNull);

      controller.updateFrame(
        _scrollbackFrame(
          viewportStartRow: 20,
          scrollbackOffset: 0,
          scrollbackMaxOffset: 20,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isTrue);
      expect(renderObject.debugCursorRect, isNotNull);
    },
  );

  testWidgets(
    'terminal cursor stays hidden and does not keep blinking when it falls outside the viewport',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-outside-focus');
      addTearDown(focusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 24, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = _terminalRenderObject(tester);

      expect(renderObject.debugCursorVisible, isFalse);
      expect(renderObject.debugCursorRect, isNull);

      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isFalse);
      expect(renderObject.debugCursorRect, isNull);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 80, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isFalse);
      expect(renderObject.debugCursorRect, isNull);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isTrue);
      expect(renderObject.debugCursorRect, isNotNull);
    },
  );

  testWidgets(
    'terminal viewport rebinds focus and controller updates after widget rebuild',
    (tester) async {
      final focusNodeA = FocusNode(debugLabel: 'terminal-test-focus-a');
      final focusNodeB = FocusNode(debugLabel: 'terminal-test-focus-b');
      addTearDown(focusNodeA.dispose);
      addTearDown(focusNodeB.dispose);

      final controllerA = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final controllerB = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      Widget buildViewport({
        required TerminalViewportController controller,
        required FocusNode focusNode,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        buildViewport(controller: controllerA, focusNode: focusNodeA),
      );

      focusNodeA.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      await tester.pumpWidget(
        buildViewport(controller: controllerB, focusNode: focusNodeB),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(renderObject.debugCursorVisible, isTrue);

      focusNodeB.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isFalse);
    },
  );

  testWidgets(
    'terminal viewport preserves trailing-space styles and resolves inverse colors',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'abc   ',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 6,
                    foreground: Color(0xFF22C55E),
                    background: Color(0xFFEF4444),
                    inverse: true,
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugLastPaintedRowTexts.first, 'abc   ');

      final resolvedStyle = renderObject.debugResolvedStylesForRow(0).single;
      expect(resolvedStyle.start, 0);
      expect(resolvedStyle.end, 6);
      expect(
        resolvedStyle.foreground.toARGB32(),
        const Color(0xFFEF4444).toARGB32(),
      );
      expect(
        resolvedStyle.background?.toARGB32(),
        const Color(0xFF22C55E).toARGB32(),
      );
    },
  );

  testWidgets(
    'terminal viewport only shows a scrollbar for overflow and dragging it uses absolute offsets',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollToOffsets = <int>[];
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: scrollToOffsets.add,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(terminalScrollbarTrackKey), findsNothing);
      expect(find.byKey(terminalScrollbarThumbKey), findsNothing);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'hello')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 120,
        ),
      );
      await tester.pump();

      expect(find.byKey(terminalScrollbarTrackKey), findsOneWidget);
      expect(find.byKey(terminalScrollbarThumbKey), findsOneWidget);

      await tester.drag(
        find.byKey(terminalScrollbarThumbKey),
        const Offset(0, -60),
      );
      await tester.pump();

      expect(scrollToOffsets, isNotEmpty);
      expect(scrollToOffsets.last, greaterThan(0));
      expect(scrollLines, isEmpty);
      expect(selectionController.selection, isNull);
    },
  );
}

Future<RenderTerminalViewport> _pumpThemedTerminalViewport(
  WidgetTester tester, {
  required ThemeMode themeMode,
  required TerminalFrameDiff frame,
  TerminalViewportColors? colors,
  TerminalProfileFont font = const TerminalProfileFont(),
  TerminalProfileCursor cursor = const TerminalProfileCursor(),
}) async {
  final controller = TerminalViewportController()..updateFrame(frame);
  await _pumpTerminalViewportWithController(
    tester,
    controller: controller,
    themeMode: themeMode,
    colors: colors,
    font: font,
    cursor: cursor,
  );
  return tester.allRenderObjects.whereType<RenderTerminalViewport>().last;
}

Future<void> _pumpTerminalViewportWithController(
  WidgetTester tester, {
  required TerminalViewportController controller,
  required ThemeMode themeMode,
  TerminalViewportColors? colors,
  TerminalProfileFont font = const TerminalProfileFont(),
  TerminalProfileCursor cursor = const TerminalProfileCursor(),
}) async {
  final selectionController = SelectionController();
  final inputController = TerminalInputController(
    sessionId: '1',
    runtime: testRuntime(FakePtyBackend()),
    readSelection: () => '',
    copySelection: (_) async {},
    readClipboard: () async => '',
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            colors: colors,
            font: font,
            cursor: cursor,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TerminalFrameDiff _scrollbackFrame({
  required int viewportStartRow,
  required int scrollbackOffset,
  required int scrollbackMaxOffset,
  int viewportRows = 8,
  TerminalFrameModes modes = TerminalFrameModes.empty,
}) {
  return TerminalFrameDiff(
    rows: List<TerminalRow>.generate(
      viewportRows,
      (index) => TerminalRow(
        index: index,
        text: 'line${(viewportStartRow + index).toString().padLeft(2, '0')}',
      ),
    ),
    cursor: const TerminalCursor(row: 0, col: 0, visible: true),
    viewportRows: viewportRows,
    viewportCols: 80,
    dirtyRanges: [TerminalDirtyRange(start: 0, end: viewportRows)],
    scrollbackOffset: scrollbackOffset,
    scrollbackMaxOffset: scrollbackMaxOffset,
    viewportStartRow: viewportStartRow,
    modes: modes,
  );
}

RenderTerminalViewport _terminalRenderObject(WidgetTester tester) {
  return tester.allRenderObjects.whereType<RenderTerminalViewport>().last;
}

String _resolvedRowText(RenderTerminalViewport renderObject, int row) {
  return renderObject
      .debugResolvedCellsForRow(row)
      .map((cell) => cell.text)
      .join();
}

Future<void> _mouseClickAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _mouseDoubleClickAt(WidgetTester tester, Offset position) async {
  await _mouseClickAt(tester, position);
  await tester.pump(const Duration(milliseconds: 40));
  await _mouseClickAt(tester, position);
}

Future<void> _mouseDoubleClickDrag(
  WidgetTester tester, {
  required Offset start,
  required Offset end,
}) async {
  await _mouseClickAt(tester, start);
  await tester.pump(const Duration(milliseconds: 40));
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

double _snapToDevicePixel(double value, double devicePixelRatio) {
  if (!value.isFinite || !devicePixelRatio.isFinite || devicePixelRatio <= 0) {
    return value;
  }
  return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
}

bool _isSnappedToDevicePixel(double value, double devicePixelRatio) {
  final deviceValue = value * devicePixelRatio;
  return (deviceValue - deviceValue.roundToDouble()).abs() < 0.001;
}

void _expectRectSnapped(Rect rect, double devicePixelRatio) {
  expect(_isSnappedToDevicePixel(rect.left, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.top, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.right, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.bottom, devicePixelRatio), isTrue);
}

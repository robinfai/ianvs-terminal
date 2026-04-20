import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';

import 'package:app/features/terminal/render_terminal_viewport.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_painter_models.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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

  test(
    'terminal text style keeps a nerd-font fallback ahead of generic system fonts',
    () {
      expect(terminalPrimaryFontFamily, 'JetBrainsMono Nerd Font Mono');
      expect(terminalFontFamilyFallback, isNotEmpty);
      expect(terminalFontFamilyFallback.first, 'Menlo');
      expect(terminalFontFamilyFallback, contains('Apple Symbols'));
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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

      expect(renderObject.debugLastPaintedRowTexts.single, 'abc   ');

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
        coreClient: TerminalCoreClient(FakeCoreBindings()),
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

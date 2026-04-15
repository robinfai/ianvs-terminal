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
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .single;

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
    'terminal viewport accumulates scroll wheel delta into multi-line steps',
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
      expect(scrollLines.single, isNegative);
    },
  );
}

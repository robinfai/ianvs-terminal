import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

void main() {
  testWidgets(
    'iPhone one-finger drag scrolls without creating a selection',
    (tester) async {
      final harness = _MobileViewportHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final surface = _terminalSurface();
      final rect = tester.getRect(surface);
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.bottom - 24),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, -96));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      expect(harness.scrollDeltas, isNotEmpty);
      expect(harness.scrollDeltas.reduce((a, b) => a + b), greaterThan(0));
      expect(harness.selectionController.selection, isNull);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone long press selects a word and exposes a 44-point copy action',
    (tester) async {
      final harness = _MobileViewportHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final wordPosition = renderObject.localToGlobal(
        Offset(
          renderObject.debugCellSize.width * 7.5,
          renderObject.debugCellSize.height * 0.5,
        ),
      );
      await tester.longPressAt(wordPosition);
      await tester.pumpAndSettle();

      expect(harness.selectionController.selection, isNotNull);
      final copyAction = find.byKey(terminalTouchCopyMenuItemKey);
      expect(copyAction, findsOneWidget);
      expect(tester.getSize(copyAction).height, greaterThanOrEqualTo(44));

      await tester.tap(copyAction);
      await tester.pumpAndSettle();
      expect(harness.copiedText, <String>['beta']);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}

Finder _terminalSurface() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
);

final class _MobileViewportHarness {
  _MobileViewportHarness()
    : controller = TerminalViewportController()
        ..updateMeasuredCellSize(const Size(10, 18))
        ..updateFrame(_frame),
      selectionController = SelectionController() {
    inputController = TerminalInputController(
      sessionId: 'mobile-review',
      runtime: _NoopInputSink(),
      readFrame: () => controller.frame,
      readSelection: () => selectionController.textForFrame(controller.frame),
      copySelection: (text) async => copiedText.add(text),
      readClipboard: () async => '',
    );
  }

  static const _frame = TerminalFrameDiff(
    rows: <TerminalRow>[
      TerminalRow(index: 0, text: 'alpha beta gamma', sourceRow: 0),
      TerminalRow(index: 1, text: 'second terminal row', sourceRow: 1),
      TerminalRow(index: 2, text: 'third terminal row', sourceRow: 2),
      TerminalRow(index: 3, text: 'fourth terminal row', sourceRow: 3),
      TerminalRow(index: 4, text: 'fifth terminal row', sourceRow: 4),
      TerminalRow(index: 5, text: 'sixth terminal row', sourceRow: 5),
    ],
    cursor: TerminalCursor(row: 5, col: 0, visible: false),
    viewportRows: 6,
    viewportCols: 30,
    dirtyRanges: <TerminalDirtyRange>[TerminalDirtyRange(start: 0, end: 6)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 100,
    viewportStartRow: 0,
  );

  final TerminalViewportController controller;
  final SelectionController selectionController;
  late final TerminalInputController inputController;
  final List<int> scrollDeltas = <int>[];
  final List<String> copiedText = <String>[];

  Widget widget() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: scrollDeltas.add,
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    controller.dispose();
    selectionController.dispose();
  }
}

final class _NoopInputSink implements TerminalInputSink {
  @override
  void sendInput(String sessionId, Uint8List bytes) {}
}

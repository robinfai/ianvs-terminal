import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

const contextAtOutput = TerminalSemanticContext(
  occurrenceId: 'old-block',
  sessionId: '1',
  sessionEpoch: 2,
  cwd: '/old',
  frameRevision: '18446744073709551615',
  viewportRow: 1,
);

void main() {
  for (final (explicit, contextMenu) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      'captures ${explicit ? 'OSC 8' : 'soft-wrapped file'} before ${contextMenu ? 'context menu' : 'delayed tap'} dispatch',
      (tester) async {
        final opened = <TerminalLinkTarget>[];
        var ancestorMenus = 0;
        final controller = TerminalViewportController()
          ..updateFrame(
            TerminalFrameDiff(
              rows: const [
                TerminalRow(index: 0, text: '错 src/长', wrapped: true),
                TerminalRow(index: 1, text: '文件.dart:7:2'),
              ],
              cursor: const TerminalCursor(row: 0, col: 0, visible: false),
              viewportRows: 2,
              viewportCols: 20,
              dirtyRanges: const [TerminalDirtyRange(start: 0, end: 2)],
              scrollbackOffset: 0,
              scrollbackMaxOffset: 0,
              hyperlinks: explicit
                  ? const [
                      TerminalHyperlinkRange(
                        row: 1,
                        startCol: 0,
                        endCol: 12,
                        uri: 'file:///explicit/path',
                        protocolId: 'osc-first',
                      ),
                    ]
                  : const [],
            ),
          );
        final runtime = TerminalRuntimeController(
          backend: _Backend(),
          copyToClipboard: (_) async {},
          readClipboard: () async => '',
          enableSessionPolling: false,
        );
        final selection = SelectionController();
        final input = TerminalInputController(
          sessionId: '1',
          runtime: runtime,
          readFrame: () => controller.frame,
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );
        addTearDown(controller.dispose);
        addTearDown(runtime.dispose);
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              onSecondaryTapUp: (_) => ancestorMenus++,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  height: 100,
                  child: TerminalViewport(
                    controller: controller,
                    selectionController: selection,
                    inputController: input,
                    onScrollLines: (_) {},
                    onScrollToOffset: (_) {},
                    onOpenLinkTarget: opened.add,
                    onLinkContextMenu: opened.add,
                    semanticContextForRow: (_) => contextAtOutput,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final surface = tester.renderObject<RenderTerminalViewport>(
          find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == '_TerminalViewportSurface',
          ),
        );
        final position = surface.localToGlobal(
          Offset(
            surface.debugCellSize.width * 2.5,
            surface.debugCellSize.height * 1.5,
          ),
        );
        if (contextMenu) {
          final pointer = TestPointer(7, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(
            pointer.down(position, buttons: kSecondaryMouseButton),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(opened, isEmpty);
          expect(ancestorMenus, 0);
          await tester.sendEventToBinding(pointer.up());
        } else {
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
        }
        controller.updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'https://new.invalid')],
            cursor: TerminalCursor(row: 0, col: 0, visible: false),
            viewportRows: 2,
            viewportCols: 20,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(opened, hasLength(1));
        expect(ancestorMenus, 0);
        expect(
          opened.single.semanticContext!.frameRevision,
          '18446744073709551615',
        );
        expect(opened.single.semanticContext!.viewportRow, 1);
        expect(
          identical(opened.single.semanticContext, contextAtOutput),
          isTrue,
        );
        if (explicit) {
          expect(opened.single.uri, 'file:///explicit/path');
          expect(opened.single.explicitHyperlink, isTrue);
          expect(opened.single.protocolId, 'osc-first');
          expect(opened.single.fileTarget, isNull);
        } else {
          expect(opened.single.fileTarget!.path, 'src/长文件.dart');
          expect(
            (opened.single.fileTarget!.line, opened.single.fileTarget!.column),
            (7, 2),
          );
        }
        if (contextMenu) {
          // Blank output must still allow the surrounding block menu.
          await tester.tapAt(
            surface.localToGlobal(
              Offset(
                surface.debugCellSize.width * 18.5,
                surface.debugCellSize.height * 1.5,
              ),
            ),
            buttons: kSecondaryMouseButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(ancestorMenus, 1);
          expect(opened, hasLength(1));
        }
      },
    );
  }
}

class _Backend implements PtySessionBackend {
  @override
  void closeSession(String sessionId) {}
  @override
  int ping() => 42;
  @override
  List<PtyEvent> pollEvents(String sessionId) => [];
  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}
  @override
  void scrollViewport(String sessionId, int deltaLines) {}
  @override
  void scrollViewportTo(String sessionId, int offset) {}
  @override
  void writeInput(String sessionId, List<int> bytes) {}
}

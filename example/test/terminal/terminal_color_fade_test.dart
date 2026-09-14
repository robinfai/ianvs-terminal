import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

import '../helpers/pump_app.dart';

void main() {
  group('Terminal program colors', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'retain fading RGB in $brightness and respond to high contrast',
        (tester) async {
          final controller = TerminalViewportController();
          final selection = SelectionController();
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          final background = brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF0F0F0);
          final grays = brightness == Brightness.dark
              ? [119, 90, 60, 36]
              : [150, 180, 210, 234];

          Future<void> pumpContrast(bool highContrast) => tester.pumpApp(
            MediaQuery(
              data: MediaQueryData(highContrast: highContrast),
              child: Builder(
                builder: (context) => _FadeViewport(
                  controller: controller,
                  selection: selection,
                  colors: resolveTerminalColors(context).viewport,
                ),
              ),
            ),
            brightness: brightness,
          );

          for (final gray in grays) {
            final foreground = Color.fromARGB(255, gray, gray, gray);
            controller.updateFrame(_frame(foreground, background));
            await pumpContrast(false);
            final render = tester.renderObject<RenderTerminalViewport>(
              find.byType(_FadeViewport),
            );
            expect(
              render.debugResolvedStylesForRow(0).single.foreground,
              foreground,
            );
          }
          final original = Color.fromARGB(
            255,
            grays.last,
            grays.last,
            grays.last,
          );
          await pumpContrast(true);
          final render = tester.renderObject<RenderTerminalViewport>(
            find.byType(_FadeViewport),
          );
          final enhanced = render
              .debugResolvedStylesForRow(0)
              .single
              .foreground;
          expect(enhanced, isNot(original));
          final luminances = [
            enhanced.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );

          await pumpContrast(false);
          expect(
            render.debugResolvedStylesForRow(0).single.foreground,
            original,
          );

          // The host overrides native default colors. Default/dim text must
          // remain readable even when a program chooses the opposite background.
          final oppositeBackground = brightness == Brightness.light
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF0F0F0);
          controller.updateFrame(_frame(null, oppositeBackground, dim: true));
          await pumpContrast(false);
          final implicit = render
              .debugResolvedStylesForRow(0)
              .single
              .foreground;
          final implicitLuminances = [
            implicit.computeLuminance(),
            oppositeBackground.computeLuminance(),
          ]..sort();
          expect(
            (implicitLuminances.last + 0.05) /
                (implicitLuminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );
        },
      );
    }
  });
}

TerminalFrameDiff _frame(
  Color? foreground,
  Color background, {
  bool dim = false,
}) => TerminalFrameDiff(
  rows: [
    TerminalRow(
      index: 0,
      text: '⠁',
      styleRuns: [
        TerminalStyleRun(
          start: 0,
          end: 1,
          foreground: foreground,
          background: background,
          dim: dim,
        ),
      ],
    ),
  ],
  cursor: const TerminalCursor(row: 0, col: 0, visible: false),
  viewportRows: 1,
  viewportCols: 1,
  dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
  scrollbackOffset: 0,
  scrollbackMaxOffset: 0,
  defaultBackground: background,
);

class _FadeViewport extends LeafRenderObjectWidget {
  const _FadeViewport({
    required this.controller,
    required this.selection,
    required this.colors,
  });
  final TerminalViewportController controller;
  final SelectionController selection;
  final TerminalViewportColors colors;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) =>
      RenderTerminalViewport(
        controller: controller,
        selectionController: selection,
        cursorVisible: false,
        font: const TerminalFontConfig(),
        cursor: const TerminalCursorConfig(),
        devicePixelRatio: 1,
        colors: colors,
        useFrameDefaultColors: false,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTerminalViewport renderObject,
  ) {
    renderObject.colors = colors;
  }
}

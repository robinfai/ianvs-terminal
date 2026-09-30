import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';
import 'package:ianvs_terminal/src/terminal/terminal_font_fallback.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux renders the bundled default with an old Apple font profile',
    (tester) async {
      const stored = TerminalFontConfig(
        fallback: <String>[
          'Menlo',
          'JetBrainsMono Nerd Font',
          'SF Mono',
          'Monaco',
          'Apple Symbols',
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Noto Color Emoji',
        ],
      );
      final before = stored.toJson();
      final originalNarrow = _width('i', stored);
      final originalWide = _width('W', stored);
      final rendered = terminalFontForRendering(stored);
      final narrow = _width('i', rendered);
      final wide = _width('W', rendered);
      expect(rendered.family, terminalBundledFontFamily);
      expect(wide, closeTo(narrow, 0.01));
      expect(wide, closeTo(stored.size * 0.6, 0.1));
      expect(_width('0', rendered), closeTo(narrow, 0.01));
      if ((originalWide - originalNarrow).abs() > 0.01) {
        expect(rendered.family, isNot(stored.family));
        expect(wide, lessThan(originalWide));
      }
      expect(stored.toJson(), before);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: <TerminalRow>[
              TerminalRow(index: 0, text: 'iiii WWWW 0000'),
              TerminalRow(index: 1, text: '.... mmmm ____'),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: false),
            viewportRows: 2,
            viewportCols: 20,
            dirtyRanges: <TerminalDirtyRange>[
              TerminalDirtyRange(start: 0, end: 2),
            ],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final selection = SelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 180,
            child: _FontViewport(
              font: stored,
              controller: controller,
              selection: selection,
            ),
          ),
        ),
      );
      final renderObject = tester.renderObject<RenderTerminalViewport>(
        find.byType(_FontViewport),
      );
      expect(renderObject.debugFont.family, rendered.family);
      expect(renderObject.debugCellSize.width, closeTo(wide, 0.01));
      debugPrint(
        'Linux real-font check: ${stored.family} i=$originalNarrow W=$originalWide; ${rendered.family} i=$narrow W=$wide; cell=${renderObject.debugCellSize.width}',
      );
    },
    skip: !Platform.isLinux,
  );

  testWidgets(
    'Linux application carries all four font faces and licenses',
    (tester) async {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json'))
              as List<dynamic>;
      final family = manifest.cast<Map<String, dynamic>>().singleWhere(
        (entry) => entry['family'] == terminalBundledFontFamily,
      );
      final fonts = (family['fonts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(fonts, hasLength(4));
      expect(
        fonts
            .map((font) => '${font['weight']}/${font['style'] ?? 'normal'}')
            .toSet(),
        <String>{'400/normal', '700/normal', '400/italic', '700/italic'},
      );
      for (final font in fonts) {
        final bytes = await rootBundle.load(font['asset'] as String);
        expect(bytes.lengthInBytes, greaterThan(1000000));
      }
      for (final name in <String>[
        'OFL.txt',
        'JETBRAINS-OFL.txt',
        'NERD-FONTS-LICENSE.txt',
        'SOURCES.md',
      ]) {
        expect(
          await rootBundle.loadString(
            'packages/ianvs_terminal/assets/fonts/$name',
          ),
          isNotEmpty,
        );
      }
    },
    skip: !Platform.isLinux,
  );

  testWidgets(
    'Linux preserves a dynamically loaded monospace platform family',
    (tester) async {
      const font = TerminalFontConfig(family: 'SF Mono');
      terminalFontForRendering(font);
      final bytes = await rootBundle.load(
        'packages/ianvs_terminal/assets/fonts/JetBrainsMonoNerdFontMono-Regular.ttf',
      );
      await ui.loadFontFromList(
        bytes.buffer.asUint8List(),
        fontFamily: font.family,
      );
      await tester.pump();
      final rendered = terminalFontForRendering(font);
      expect(rendered.family, font.family);
      expect(_width('W', rendered), closeTo(_width('i', rendered), 0.01));
      expect(_width('W', rendered), closeTo(font.size * 0.6, 0.1));
    },
    skip: !Platform.isLinux,
  );
}

double _width(String text, TerminalFontConfig font) {
  final paragraph =
      (ui.ParagraphBuilder(
              ui.ParagraphStyle(fontFamily: font.family, fontSize: font.size),
            )
            ..pushStyle(
              ui.TextStyle(
                fontFamily: font.family,
                fontSize: font.size,
                fontFamilyFallback: font.fallback,
              ),
            )
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
  try {
    return paragraph.maxIntrinsicWidth;
  } finally {
    paragraph.dispose();
  }
}

class _FontViewport extends LeafRenderObjectWidget {
  const _FontViewport({
    required this.font,
    required this.controller,
    required this.selection,
  });

  final TerminalFontConfig font;
  final TerminalViewportController controller;
  final SelectionController selection;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selection,
      cursorVisible: false,
      font: font,
      cursor: const TerminalCursorConfig(),
      devicePixelRatio: 1,
      colors: TerminalViewportColors.dark,
    );
  }
}

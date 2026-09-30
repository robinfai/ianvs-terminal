import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/terminal_font_fallback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default family resolves to the bundled package font on every platform',
    () {
      const stored = TerminalFontConfig();
      final before = stored.toJson();
      for (final platform in TargetPlatform.values) {
        final rendered = terminalFontForRendering(stored, platform: platform);
        expect(rendered.family, terminalBundledFontFamily);
        expect(rendered.size, stored.size);
        expect(rendered.lineHeight, stored.lineHeight);
        expect(rendered.fallback, stored.fallback);
        expect(stored.toJson(), before);
        expect(
          identical(
            terminalFontForRendering(rendered, platform: platform),
            rendered,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'old Apple profile keeps glyph fallback order with the bundled default',
    () {
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
      final rendered = terminalFontForRendering(
        stored,
        platform: TargetPlatform.linux,
      );
      expect(rendered.family, terminalBundledFontFamily);
      expect(rendered.fallback, <String>[
        ...stored.fallback,
        ...terminalPortableMonospaceFallbacks,
      ]);
      expect(stored.family, terminalPrimaryFontFamily);
    },
  );

  test('custom font choices and fallback order remain intact', () {
    const stored = TerminalFontConfig(
      family: 'Personal Font',
      fallback: <String>['Custom CJK', 'Noto Color Emoji', 'Noto Sans Mono'],
    );
    final rendered = terminalFontForRendering(
      stored,
      platform: TargetPlatform.linux,
    );
    expect(rendered.family, stored.family);
    expect(rendered.fallback, <String>[
      ...stored.fallback,
      'DejaVu Sans Mono',
      'Liberation Mono',
      'monospace',
    ]);
    for (final platform in TargetPlatform.values) {
      if (platform != TargetPlatform.linux) {
        expect(
          identical(
            terminalFontForRendering(stored, platform: platform),
            stored,
          ),
          isTrue,
        );
      }
    }
  });

  testWidgets(
    'bundled real regular bold and italic faces have a monospace grid',
    (tester) async {
      await tester.runAsync(
        () => _loadFontFaces(terminalBundledFontFamily, <String>[
          'Regular',
          'Bold',
          'Italic',
          'BoldItalic',
        ]),
      );
      final rendered = terminalFontForRendering(const TerminalFontConfig());
      for (final weight in <ui.FontWeight>[
        ui.FontWeight.normal,
        ui.FontWeight.bold,
      ]) {
        for (final style in ui.FontStyle.values) {
          final narrow = _width(
            'i',
            rendered.family,
            weight: weight,
            style: style,
          );
          expect(
            _width('W', rendered.family, weight: weight, style: style),
            closeTo(narrow, 0.01),
          );
          expect(narrow, closeTo(rendered.size * 0.6, 0.1));
        }
      }
    },
  );

  testWidgets(
    'custom loaded family is preserved without availability guessing',
    (tester) async {
      const customFamily = 'Ianvs Custom Mono Test';
      await tester.runAsync(
        () => _loadFontFaces(customFamily, <String>['Regular']),
      );
      final rendered = terminalFontForRendering(
        const TerminalFontConfig(family: customFamily),
      );
      expect(rendered.family, customFamily);
      expect(
        _width('W', rendered.family),
        closeTo(_width('i', rendered.family), 0.01),
      );
      expect(_width('W', rendered.family), closeTo(8.4, 0.1));
    },
  );
}

Future<void> _loadFontFaces(String family, List<String> styles) async {
  // Package suites run from the package root. Flutter's tester does not support
  // Isolate.resolvePackageUri, and root-app asset keys differ from dependencies.
  final loader = FontLoader(family);
  for (final style in styles) {
    final bytes = await File(
      'assets/fonts/JetBrainsMonoNerdFontMono-$style.ttf',
    ).readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

double _width(
  String text,
  String family, {
  ui.FontWeight weight = ui.FontWeight.normal,
  ui.FontStyle style = ui.FontStyle.normal,
}) {
  final paragraph =
      (ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: family, fontSize: 14))
            ..pushStyle(
              ui.TextStyle(
                fontFamily: family,
                fontSize: 14,
                fontWeight: weight,
                fontStyle: style,
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/terminal/terminal_text_document_style.dart';

void main() {
  const palette = TerminalTextDocumentPalette(
    foreground: Color(0xFFF8FAFC),
    accent: Color(0xFF7DD3FC),
    secondary: Color(0xFFF0ABFC),
    tertiary: Color(0xFFFDE68A),
    muted: Color(0xFF94A3B8),
  );

  test('text document type hints and bounded labels resolve predictably', () {
    expect(
      TerminalTextDocumentStyler.kindFor(
        type: 'application/problem+json; charset=utf-8',
        visibleLines: const <String>['{"ok": true}'],
      ),
      TerminalTextDocumentKind.json,
    );
    expect(
      TerminalTextDocumentStyler.kindFor(
        type: '.md',
        visibleLines: const <String>['plain'],
      ),
      TerminalTextDocumentKind.markdown,
    );
    expect(
      TerminalTextDocumentStyler.kindFor(
        type: null,
        visibleLines: const <String>['# Heading', '- item'],
      ),
      TerminalTextDocumentKind.markdown,
    );
    expect(
      TerminalTextDocumentStyler.kindFor(
        type: 'text/plain',
        visibleLines: const <String>['{"not": "auto-detected"}'],
      ),
      TerminalTextDocumentKind.plainText,
    );
    expect(
      TerminalTextDocumentStyler.displayLabel(
        List<String>.filled(40, 'x').join(),
        TerminalTextDocumentKind.code,
      ).runes.length,
      32,
    );
  });

  test('JSON styling prioritizes keys, values, literals and numbers', () {
    final runs = TerminalTextDocumentStyler.styleRow(
      text: '{"count": 42, "ok": true}',
      kind: TerminalTextDocumentKind.json,
      palette: palette,
    );

    expect(runs, isNotEmpty);
    expect(
      runs.any((run) => run.foreground == palette.accent && run.bold),
      isTrue,
    );
    expect(runs.any((run) => run.foreground == palette.tertiary), isTrue);
    expect(runs.every((run) => run.end > run.start), isTrue);
  });

  test('code styling converts Unicode offsets to terminal columns safely', () {
    final runs = TerminalTextDocumentStyler.styleRow(
      text: '你 const answer = "👩‍💻"; // ok',
      kind: TerminalTextDocumentKind.code,
      palette: palette,
    );

    expect(runs, isNotEmpty);
    expect(runs.every((run) => run.start >= 0 && run.end > run.start), isTrue);
    expect(
      runs.any((run) => run.foreground == palette.muted && run.italic),
      isTrue,
    );
  });
}

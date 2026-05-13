import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

void main() {
  test('terminal text cells keep combining marks with their base glyph', () {
    final cells = TerminalTextCells.fromText('e\u0301a');

    expect(cells.cellCount, 2);
    expect(cells.cells[0].text, 'e\u0301');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, 'a');
    expect(cells.cells[1].column, 1);
    expect(cells.sliceColumns(0, 1), 'e\u0301');
  });

  test(
    'terminal text cells reserve continuation cells for wide CJK glyphs',
    () {
      final cells = TerminalTextCells.fromText('你a');

      expect(cells.cellCount, 3);
      expect(cells.cells[0].text, '你');
      expect(cells.cells[0].column, 0);
      expect(cells.cells[0].columnSpan, 2);
      expect(cells.cells[1].isContinuation, isTrue);
      expect(cells.cells[2].text, 'a');
      expect(cells.cells[2].column, 2);
    },
  );

  test(
    'terminal text cells treat regional indicator pairs as one flag emoji',
    () {
      final cells = TerminalTextCells.fromText('🇺🇸🇨🇦a');

      expect(cells.cellCount, 5);
      expect(cells.cells[0].text, '🇺🇸');
      expect(cells.cells[0].column, 0);
      expect(cells.cells[0].columnSpan, 2);
      expect(cells.cells[1].isContinuation, isTrue);
      expect(cells.cells[2].text, '🇨🇦');
      expect(cells.cells[2].column, 2);
      expect(cells.cells[2].columnSpan, 2);
      expect(cells.cells[3].isContinuation, isTrue);
      expect(cells.cells[4].text, 'a');
      expect(cells.cells[4].column, 4);
    },
  );
}

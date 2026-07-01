import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

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

  test(
    'terminal text cells reserve wide cells for emoji presentation clusters',
    () {
      final cells = TerminalTextCells.fromText('✈️1️⃣1⃣✈︎a');

      expect(cells.cellCount, 8);
      expect(cells.cells[0].text, '✈️');
      expect(cells.cells[0].column, 0);
      expect(cells.cells[0].columnSpan, 2);
      expect(cells.cells[1].isContinuation, isTrue);
      expect(cells.cells[2].text, '1️⃣');
      expect(cells.cells[2].column, 2);
      expect(cells.cells[2].columnSpan, 2);
      expect(cells.cells[3].isContinuation, isTrue);
      expect(cells.cells[4].text, '1⃣');
      expect(cells.cells[4].column, 4);
      expect(cells.cells[4].columnSpan, 2);
      expect(cells.cells[5].isContinuation, isTrue);
      expect(cells.cells[6].text, '✈︎');
      expect(cells.cells[6].column, 6);
      expect(cells.cells[6].columnSpan, 1);
      expect(cells.cells[7].text, 'a');
      expect(cells.cells[7].column, 7);
      expect(cells.sliceColumns(0, 2), '✈️');
      expect(cells.sliceColumns(2, 4), '1️⃣');
      expect(cells.sliceColumns(4, 6), '1⃣');
      expect(cells.sliceColumns(6, 7), '✈︎');
    },
  );

  test('terminal text cells keep plain text variation selectors narrow', () {
    final cells = TerminalTextCells.fromText('a️️©️↔️');

    expect(cells.cellCount, 6);
    expect(cells.cells[0].text, 'a️');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, '️');
    expect(cells.cells[1].column, 1);
    expect(cells.cells[1].columnSpan, 1);
    expect(cells.cells[2].text, '©️');
    expect(cells.cells[2].column, 2);
    expect(cells.cells[2].columnSpan, 2);
    expect(cells.cells[3].isContinuation, isTrue);
    expect(cells.cells[4].text, '↔️');
    expect(cells.cells[4].column, 4);
    expect(cells.cells[4].columnSpan, 2);
    expect(cells.cells[5].isContinuation, isTrue);
    expect(cells.sliceColumns(0, 1), 'a️');
    expect(cells.sliceColumns(1, 2), '️');
    expect(cells.sliceColumns(2, 4), '©️');
    expect(cells.sliceColumns(4, 6), '↔️');
  });

  test('terminal text cells keep default ignorable format controls narrow', () {
    const formatted = 'a\u00AD\u{1BCA0}\u{E0001}b';
    final cells = TerminalTextCells.fromText(formatted);

    expect(cells.cellCount, 2);
    expect(cells.cells[0].text, 'a\u00AD\u{1BCA0}\u{E0001}');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, 'b');
    expect(cells.cells[1].column, 1);
    expect(cells.sliceColumns(0, 1), 'a\u00AD\u{1BCA0}\u{E0001}');
    expect(cells.sliceColumns(1, 2), 'b');
  });

  test('terminal text cells keep plain text ZWJ clusters narrow', () {
    final trailingJoiner = TerminalTextCells.fromText('a‍');

    expect(trailingJoiner.cellCount, 1);
    expect(trailingJoiner.cells[0].text, 'a‍');
    expect(trailingJoiner.cells[0].column, 0);
    expect(trailingJoiner.cells[0].columnSpan, 1);

    final joinedText = TerminalTextCells.fromText('a‍bX');

    expect(joinedText.cellCount, 3);
    expect(joinedText.cells[0].text, 'a‍');
    expect(joinedText.cells[0].column, 0);
    expect(joinedText.cells[0].columnSpan, 1);
    expect(joinedText.cells[1].text, 'b');
    expect(joinedText.cells[1].column, 1);
    expect(joinedText.cells[1].columnSpan, 1);
    expect(joinedText.cells[2].text, 'X');
    expect(joinedText.cells[2].column, 2);
    expect(joinedText.sliceColumns(0, 1), 'a‍');
    expect(joinedText.sliceColumns(1, 2), 'b');
  });

  test('terminal text cells keep emoji tag sequences in one wide cell', () {
    const scotlandFlag =
        '\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}';
    final cells = TerminalTextCells.fromText('${scotlandFlag}a');

    expect(cells.cellCount, 3);
    expect(cells.cells[0].text, scotlandFlag);
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 2);
    expect(cells.cells[1].isContinuation, isTrue);
    expect(cells.cells[2].text, 'a');
    expect(cells.cells[2].column, 2);
    expect(cells.sliceColumns(0, 2), scotlandFlag);
  });

  test('terminal text cells keep dangling emoji tag text narrow', () {
    final cells = TerminalTextCells.fromText('a\u{E0067}\u{1F3F4}\u{E007F}X');

    expect(cells.cellCount, 4);
    expect(cells.cells[0].text, 'a\u{E0067}');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, '\u{1F3F4}\u{E007F}');
    expect(cells.cells[1].column, 1);
    expect(cells.cells[1].columnSpan, 2);
    expect(cells.cells[2].isContinuation, isTrue);
    expect(cells.cells[3].text, 'X');
    expect(cells.cells[3].column, 3);
  });

  test('terminal text cells keep emoji ZWJ sequences in one wide cell', () {
    const technologist = '👩\u{200D}💻';
    final cells = TerminalTextCells.fromText('${technologist}a');

    expect(cells.cellCount, 3);
    expect(cells.cells[0].text, technologist);
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 2);
    expect(cells.cells[1].isContinuation, isTrue);
    expect(cells.cells[2].text, 'a');
    expect(cells.cells[2].column, 2);
    expect(cells.sliceColumns(0, 2), technologist);
  });

  test(
    'terminal text cells keep multi-emoji ZWJ sequences in one wide cell',
    () {
      const family = '👨\u{200D}👩\u{200D}👧\u{200D}👦';
      final cells = TerminalTextCells.fromText('${family}a');

      expect(cells.cellCount, 3);
      expect(cells.cells[0].text, family);
      expect(cells.cells[0].column, 0);
      expect(cells.cells[0].columnSpan, 2);
      expect(cells.cells[1].isContinuation, isTrue);
      expect(cells.cells[2].text, 'a');
      expect(cells.cells[2].column, 2);
      expect(cells.sliceColumns(0, 2), family);
      expect(cells.sliceColumns(1, 2), family);
      expect(cells.sliceColumns(2, 3), 'a');
    },
  );

  test(
    'terminal text cells keep emoji skin tone modifiers in one wide cell',
    () {
      const wavingHandMediumSkinTone = '👋🏽';
      final cells = TerminalTextCells.fromText('${wavingHandMediumSkinTone}a');

      expect(cells.cellCount, 3);
      expect(cells.cells[0].text, wavingHandMediumSkinTone);
      expect(cells.cells[0].column, 0);
      expect(cells.cells[0].columnSpan, 2);
      expect(cells.cells[1].isContinuation, isTrue);
      expect(cells.cells[2].text, 'a');
      expect(cells.cells[2].column, 2);
      expect(cells.sliceColumns(0, 2), wavingHandMediumSkinTone);
    },
  );

  test('terminal text cells keep plain text skin tone modifiers narrow', () {
    final cells = TerminalTextCells.fromText('a🏽X');

    expect(cells.cellCount, 2);
    expect(cells.cells[0].text, 'a🏽');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, 'X');
    expect(cells.cells[1].column, 1);
    expect(cells.sliceColumns(0, 1), 'a🏽');
    expect(cells.sliceColumns(1, 2), 'X');
  });

  test('terminal text cells keep Nerd Font private-use icons narrow', () {
    final cells = TerminalTextCells.fromText('󰣇a');

    expect(cells.cellCount, 3);
    expect(cells.cells[0].text, '');
    expect(cells.cells[0].column, 0);
    expect(cells.cells[0].columnSpan, 1);
    expect(cells.cells[1].text, '󰣇');
    expect(cells.cells[1].column, 1);
    expect(cells.cells[1].columnSpan, 1);
    expect(cells.cells[2].text, 'a');
    expect(cells.cells[2].column, 2);
  });
}

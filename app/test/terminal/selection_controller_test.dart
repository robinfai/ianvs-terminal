import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_painter_models.dart';

void main() {
  TerminalFrameDiff frameWithRows(List<TerminalRow> rows) {
    return TerminalFrameDiff(
      rows: rows,
      cursor: const TerminalCursor(row: 0, col: 0, visible: true),
      viewportRows: rows.length,
      viewportCols: 80,
      dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
      scrollbackOffset: 0,
      scrollbackMaxOffset: 0,
    );
  }

  test('textForFrame returns empty string when there is no selection', () {
    final controller = SelectionController();

    final text = controller.textForFrame(
      frameWithRows(const [TerminalRow(index: 0, text: 'hello')]),
    );

    expect(text, isEmpty);
  });

  test('textForFrame joins multi-line selections with newlines', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 2));
    controller.update(const TerminalCellPosition(1, 3));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'hello'),
        TerminalRow(index: 1, text: 'world'),
      ]),
    );

    expect(text, 'llo\nwor');
  });

  test('textForFrame keeps wrapped rows contiguous for linear selections', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 2));
    controller.update(const TerminalCellPosition(1, 3));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'hello', wrapped: true),
        TerminalRow(index: 1, text: 'world'),
      ]),
    );

    expect(text, 'llowor');
  });

  test('textForFrame normalizes reverse multi-line selections', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(2, 4));
    controller.update(const TerminalCellPosition(0, 1));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'alpha'),
        TerminalRow(index: 1, text: 'beta'),
        TerminalRow(index: 2, text: 'gamma'),
      ]),
    );

    expect(text, 'lpha\nbeta\ngamm');
  });

  test('textForFrame clamps selection end to row length', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 1));
    controller.update(const TerminalCellPosition(1, 20));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'abc'),
        TerminalRow(index: 1, text: 'xy'),
      ]),
    );

    expect(text, 'bc\nxy');
  });

  test('textForFrame returns clipped columns for block selections', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 1), block: true);
    controller.update(const TerminalCellPosition(2, 4));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'abc'),
        TerminalRow(index: 1, text: 'vwxyz'),
        TerminalRow(index: 2, text: 'mn'),
      ]),
    );

    expect(text, 'bc\nwxy\nn');
  });

  test('textForFrame keeps asymmetric multi-line column ranges linearized', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 3));
    controller.update(const TerminalCellPosition(2, 2));

    final text = controller.textForFrame(
      frameWithRows(const [
        TerminalRow(index: 0, text: 'abcde'),
        TerminalRow(index: 1, text: 'vwxyz'),
        TerminalRow(index: 2, text: 'mnopq'),
      ]),
    );

    expect(text, 'de\nvwxyz\nmn');
  });

  test('textForFrame uses terminal cell columns for non-BMP glyphs', () {
    final controller = SelectionController();
    controller.begin(const TerminalCellPosition(0, 1));
    controller.update(const TerminalCellPosition(0, 3));

    final text = controller.textForFrame(
      frameWithRows(const [TerminalRow(index: 0, text: '󰀵abc')]),
    );

    expect(text, 'ab');
  });

  test('terminal text cells treat wide CJK glyphs as two columns', () {
    final cells = TerminalTextCells.fromText('你a');

    expect(cells.cellCount, 3);
    expect(cells.sliceColumns(0, 2), '你');
    expect(cells.sliceColumns(1, 2), '你');
    expect(cells.sliceColumns(2, 3), 'a');
  });

  test('terminal text cells keep emoji zwj clusters in one wide cell', () {
    final cells = TerminalTextCells.fromText('👨‍👩‍👧a');

    expect(cells.cellCount, 3);
    expect(cells.sliceColumns(0, 2), '👨‍👩‍👧');
    expect(cells.sliceColumns(1, 2), '👨‍👩‍👧');
    expect(cells.sliceColumns(2, 3), 'a');
  });

  test(
    'terminal text cells keep combining marks attached to the base glyph',
    () {
      final cells = TerminalTextCells.fromText('e\u0301a');

      expect(cells.cellCount, 2);
      expect(cells.sliceColumns(0, 1), 'e\u0301');
      expect(cells.sliceColumns(1, 2), 'a');
    },
  );
}

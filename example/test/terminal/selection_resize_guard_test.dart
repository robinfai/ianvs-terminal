import 'package:app/features/terminal/selection_resize_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test(
    'keyboard and window resizes keep the selected grid until dismissal',
    () {
      final selection = SelectionController();
      final guard = SelectionResizeGuard(selection);
      addTearDown(selection.dispose);
      addTearDown(guard.dispose);
      final applied = <String>[];
      guard.resize(() => applied.add('initial'));
      selection.setSelection(
        const TerminalSelection(startRow: 5, startCol: 1, endRow: 5, endCol: 8),
      );
      guard.resize(() => applied.add('keyboard hidden'));
      guard.resize(() => applied.add('window resized'));
      selection.update(const TerminalCellPosition(6, 2));
      expect(applied, ['initial']);
      expect(selection.selection!.startRow, 5);
      selection.clear();
      expect(applied, ['initial', 'window resized']);
      selection.clear();
      expect(applied, hasLength(2));
      guard.resize(() => applied.add('normal resize'));
      expect(applied.last, 'normal resize');
    },
  );

  test('closing a selected pane discards its pending resize', () {
    final selection = SelectionController();
    final guard = SelectionResizeGuard(selection);
    addTearDown(selection.dispose);
    selection.begin(const TerminalCellPosition(0, 0));
    var calls = 0;
    guard.resize(() => calls++);
    guard.dispose();
    selection.clear();
    expect(calls, 0);
  });
}

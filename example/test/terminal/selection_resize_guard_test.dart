import 'package:app/features/terminal/selection_resize_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  for (final endCol in [1, 8]) {
    test('resize clears empty or nonempty selection before reflow $endCol', () {
      final selection = SelectionController();
      final guard = SelectionResizeGuard(selection);
      addTearDown(selection.dispose);
      addTearDown(guard.dispose);
      selection.setSelection(
        TerminalSelection(startRow: 0, startCol: 1, endRow: 0, endCol: endCol),
      );
      var calls = 0;
      guard.resize(() {
        expect(selection.selection, isNull);
        calls++;
      });
      expect(calls, 1);
      guard.dispose();
      guard.resize(() => calls++);
      expect(calls, 1);
    });
  }
}

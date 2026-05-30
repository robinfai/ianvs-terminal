import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session state pane layout', () {
    test('split defaults non-finite ratios', () {
      final layout = TerminalPaneLayoutNode.split(
        id: 'split-1',
        splitAxis: TerminalSplitAxis.horizontal,
        first: TerminalPaneLayoutNode.leaf(_pane('pane-1')),
        second: TerminalPaneLayoutNode.leaf(_pane('pane-2')),
        ratio: double.nan,
      );

      expect(layout.ratio, 0.5);
    });
  });
}

TerminalPane _pane(String id) {
  return TerminalPane(sessionId: id, title: id, profileId: 'default');
}

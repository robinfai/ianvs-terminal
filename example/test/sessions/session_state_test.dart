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

    test('tab active session falls back when active pane id is stale', () {
      final tab = TerminalTab(
        sessionId: 'closed-root',
        title: 'closed-root',
        profileId: 'default',
        paneLayout: TerminalPaneLayoutNode.leaf(_pane('remaining-pane')),
        activePaneSessionId: 'closed-pane',
      );

      expect(tab.activeSessionId, 'remaining-pane');
      expect(tab.activePane.sessionId, 'remaining-pane');
    });

    test(
      'tab active session prefers tab root when active pane id is stale',
      () {
        final tab = TerminalTab(
          sessionId: 'root-pane',
          title: 'root-pane',
          profileId: 'default',
          panes: [_pane('root-pane'), _pane('second-pane')],
          activePaneSessionId: 'closed-pane',
        );

        expect(tab.activeSessionId, 'root-pane');
      },
    );
  });
}

TerminalPane _pane(String id) {
  return TerminalPane(sessionId: id, title: id, profileId: 'default');
}

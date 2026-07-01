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

    test('replacing split root pane keeps tab root metadata synchronized', () {
      final oldProgress = TerminalPaneProgressState(
        source: 'osc9;4',
        named: false,
        action: 'set',
        state: 'normal',
        percent: 25,
        label: 'Old',
      );
      final newProgress = TerminalPaneProgressState(
        source: 'osc9;4',
        named: false,
        action: 'set',
        state: 'normal',
        percent: 80,
        label: 'Deploy',
      );
      final namedProgress = <String, TerminalPaneProgressState>{
        'build': TerminalPaneProgressState(
          source: 'osc934',
          named: true,
          action: 'set',
          id: 'build',
          state: 'normal',
          percent: 60,
          label: 'Compile',
        ),
      };
      final notification = TerminalPaneNotificationState(
        source: 'osc777',
        title: 'Deploy done',
        message: 'root pane notification',
      );
      final tab = TerminalTab(
        sessionId: 'root-pane',
        title: 'Old root',
        profileId: 'old-profile',
        shellIntegration: const TerminalShellIntegrationSnapshot(
          username: 'old',
        ),
        oscBadge: 'Old',
        progress: oldProgress,
        namedProgress: const <String, TerminalPaneProgressState>{},
        recentNotifications: const <TerminalPaneNotificationState>[],
        paneLayout: TerminalPaneLayoutNode.split(
          id: 'split-root-side',
          splitAxis: TerminalSplitAxis.horizontal,
          first: TerminalPaneLayoutNode.leaf(
            _pane('root-pane').copyWith(
              title: 'Old root',
              profileId: 'old-profile',
              shellIntegration: const TerminalShellIntegrationSnapshot(
                username: 'old',
              ),
              oscBadge: 'Old',
              progress: oldProgress,
            ),
          ),
          second: TerminalPaneLayoutNode.leaf(_pane('side-pane')),
        ),
      );
      final replacement = _pane('root-pane').copyWith(
        title: 'Root deploy',
        profileId: 'deploy-profile',
        shellIntegration: const TerminalShellIntegrationSnapshot(
          username: 'deploy',
        ),
        oscBadge: 'Deploy',
        progress: newProgress,
        namedProgress: namedProgress,
        recentNotifications: [notification],
      );

      final updated = tab.replacePane(replacement);

      expect(updated.title, 'Root deploy');
      expect(updated.profileId, 'deploy-profile');
      expect(updated.shellIntegration.username, 'deploy');
      expect(updated.oscBadge, 'Deploy');
      expect(updated.progress?.label, 'Deploy');
      expect(updated.namedProgress, namedProgress);
      expect(updated.recentNotifications, [notification]);
      expect(updated.paneFor('root-pane')?.oscBadge, 'Deploy');

      final cleared = updated.replacePane(
        replacement.copyWith(
          oscBadge: null,
          progress: null,
          namedProgress: const <String, TerminalPaneProgressState>{},
          recentNotifications: const <TerminalPaneNotificationState>[],
        ),
      );

      expect(cleared.oscBadge, isNull);
      expect(cleared.progress, isNull);
      expect(cleared.namedProgress, isEmpty);
      expect(cleared.recentNotifications, isEmpty);
      expect(cleared.paneFor('root-pane')?.oscBadge, isNull);
    });
  });
}

TerminalPane _pane(String id) {
  return TerminalPane(sessionId: id, title: id, profileId: 'default');
}

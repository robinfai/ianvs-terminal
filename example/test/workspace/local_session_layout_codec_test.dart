import 'dart:convert';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/workspace/local_session_layout_codec.dart';
import 'package:app/features/workspace/local_terminal_layout_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalSessionLayoutCodec', () {
    test('captures topology and only fresh-launch intent', () {
      final profile = defaultTerminalProfile().copyWith(
        shell: '/bin/zsh',
        args: const <String>['-l'],
        env: const <String, String>{
          'TOKEN': 'secret-value',
          'LANG': 'en_US.UTF-8',
        },
        cwd: '/profile-cwd',
      );
      final first = TerminalPane(
        sessionId: 'live-1',
        title: 'Runtime title',
        profileId: profile.id,
        profileSnapshot: profile,
        relaunchSpec: const TerminalRelaunchSpec(
          profileId: 'default',
          cwd: '/old-cwd',
        ),
        shellIntegration: const TerminalShellIntegrationSnapshot(
          currentDirectory: '/current-cwd',
        ),
      );
      final second = TerminalPane(
        sessionId: 'live-2',
        title: 'Exited runtime',
        profileId: profile.id,
        profileSnapshot: profile,
        isExited: true,
        exitCode: 9,
      );
      final paneLayout = TerminalPaneLayoutNode.split(
        id: 'split-live',
        splitAxis: TerminalSplitAxis.vertical,
        first: TerminalPaneLayoutNode.leaf(first),
        second: TerminalPaneLayoutNode.leaf(second),
        ratio: 0.63,
      );
      final state = _state(
        profiles: <TerminalProfile>[profile],
        tabs: <TerminalTab>[
          TerminalTab(
            sessionId: first.sessionId,
            title: first.title,
            profileId: first.profileId,
            profileSnapshot: first.profileSnapshot,
            panes: paneLayout.panes,
            paneLayout: paneLayout,
            activePaneSessionId: second.sessionId,
          ),
        ],
        activeSessionId: second.sessionId,
      );

      final layout = LocalSessionLayoutCodec.capture(state);

      expect(layout.activeTabId, first.sessionId);
      expect(layout.activeTab!.activePaneId, second.sessionId);
      expect(layout.activeTab!.root.direction, TerminalPaneSplitDirection.down);
      expect(layout.activeTab!.root.ratio, 0.63);
      final firstSpec = layout.activeTab!.root
          .findPane(first.sessionId)!
          .relaunchSpec!;
      expect(firstSpec.command!.program, '/bin/zsh');
      expect(firstSpec.command!.arguments, <String>['-l']);
      expect(firstSpec.cwd, '/current-cwd');
      expect(
        layout.activeTab!.root.findPane(second.sessionId)!.relaunchSpec!.cwd,
        '/profile-cwd',
      );
      final encoded = jsonEncode(layout.toJson());
      expect(encoded, isNot(contains('Runtime title')));
      expect(encoded, isNot(contains('secret-value')));
      expect(encoded, isNot(contains('exitCode')));
      expect(encoded, isNot(contains('recordingPath')));
    });

    test('restores topology with newly relaunched session ids', () {
      final profile = defaultTerminalProfile();
      final layout = TerminalLayout(
        activeTabId: 'old-tab',
        tabs: <TerminalLayoutTab>[
          TerminalLayoutTab(
            id: 'old-tab',
            activePaneId: 'old-2',
            root: TerminalPaneNode.split(
              id: 'old-split',
              direction: TerminalPaneSplitDirection.right,
              ratio: 0.42,
              first: TerminalPaneNode.leaf(
                id: 'old-1',
                relaunchSpec: const TerminalRelaunchSpec(
                  profileId: 'default',
                  cwd: '/one',
                ),
              ),
              second: TerminalPaneNode.leaf(
                id: 'old-2',
                relaunchSpec: const TerminalRelaunchSpec(
                  profileId: 'default',
                  cwd: '/two',
                ),
              ),
            ),
          ),
        ],
      );
      var nextId = 0;

      final restored = LocalSessionLayoutCodec.restore(
        layout,
        relaunch: (spec) {
          nextId += 1;
          final launchProfile = profile.copyWith(cwd: spec.cwd);
          return TerminalPane(
            sessionId: 'new-$nextId',
            title: launchProfile.name,
            profileId: launchProfile.id,
            profileSnapshot: launchProfile,
            relaunchSpec: spec,
          );
        },
      );

      expect(restored.failures, isEmpty);
      expect(restored.tabs, hasLength(1));
      expect(restored.activeSessionId, 'new-2');
      final tab = restored.tabs.single;
      expect(tab.sessionId, 'new-1');
      expect(tab.activePaneSessionId, 'new-2');
      expect(tab.effectivePaneLayout.splitAxis, TerminalSplitAxis.horizontal);
      expect(tab.effectivePaneLayout.ratio, 0.42);
      expect(
        tab.effectivePanes.map((pane) => pane.profileSnapshot!.cwd),
        <String?>['/one', '/two'],
      );
      expect(tab.containsSession('old-1'), isFalse);
      expect(tab.containsSession('old-2'), isFalse);
    });

    test('reports failed relaunches and collapses their split branch', () {
      final profile = defaultTerminalProfile();
      final layout = TerminalLayout(
        activeTabId: 'tab-1',
        tabs: <TerminalLayoutTab>[
          TerminalLayoutTab(
            id: 'tab-1',
            activePaneId: 'missing-pane',
            root: TerminalPaneNode.split(
              id: 'split-1',
              direction: TerminalPaneSplitDirection.down,
              first: TerminalPaneNode.leaf(
                id: 'good-pane',
                relaunchSpec: const TerminalRelaunchSpec(profileId: 'default'),
              ),
              second: TerminalPaneNode.leaf(
                id: 'missing-pane',
                relaunchSpec: const TerminalRelaunchSpec(profileId: 'missing'),
              ),
            ),
          ),
        ],
      );

      final restored = LocalSessionLayoutCodec.restore(
        layout,
        relaunch: (spec) => spec.profileId == 'missing'
            ? null
            : TerminalPane(
                sessionId: 'new-good',
                title: profile.name,
                profileId: profile.id,
                profileSnapshot: profile,
              ),
      );

      expect(restored.failures, hasLength(1));
      expect(restored.failures.single.paneId, 'missing-pane');
      expect(restored.failures.single.intent.profileId, 'missing');
      expect(restored.tabs.single.effectivePanes, hasLength(1));
      expect(restored.activeSessionId, 'new-good');
    });
  });
}

SessionState _state({
  required List<TerminalProfile> profiles,
  required List<TerminalTab> tabs,
  required String? activeSessionId,
}) {
  return SessionState(
    tabs: tabs,
    activeSessionId: activeSessionId,
    profiles: profiles,
    defaultProfileId: profiles.first.id,
    configuredDefaultProfileId: profiles.first.id,
    configurationWarnings: const <TerminalProfileLoadWarning>[],
    themeMode: TerminalThemeMode.system,
    terminalViewportPadding:
        TerminalAppAppearance.defaultTerminalViewportPadding,
    isReady: true,
  );
}

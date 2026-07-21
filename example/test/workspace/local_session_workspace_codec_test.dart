import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/workspace/local_session_workspace_codec.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalSessionWorkspaceCodec', () {
    test('captures runtime topology as local relaunch intent', () {
      final profile = defaultTerminalProfile();
      final first = TerminalPane(
        sessionId: 'live-1',
        title: 'Root',
        profileId: profile.id,
        profileSnapshot: profile.copyWith(
          shell: '/bin/zsh',
          args: const ['-l'],
          env: const {'TOKEN': 'secret-value', 'LANG': 'en_US.UTF-8'},
          cwd: '/profile-cwd',
        ),
        sessionDescriptor: TerminalSessionDescriptor(
          id: 'descriptor-1',
          profileId: profile.id,
          createdAtUtc: DateTime.utc(2026, 7, 21, 4, 30),
          recordingPath: '/recordings/live-1.ndjson',
        ),
        shellIntegration: const TerminalShellIntegrationSnapshot(
          currentDirectory: '/current-cwd',
        ),
      );
      final second = TerminalPane(
        sessionId: 'live-2',
        title: 'Second',
        profileId: profile.id,
        profileSnapshot: profile,
        isExited: true,
        exitCode: 9,
      );
      final layout = TerminalPaneLayoutNode.split(
        id: 'split-live',
        splitAxis: TerminalSplitAxis.vertical,
        first: TerminalPaneLayoutNode.leaf(first),
        second: TerminalPaneLayoutNode.leaf(second),
        ratio: 0.63,
      );
      final state = _state(
        profiles: [profile],
        tabs: [
          TerminalTab(
            sessionId: first.sessionId,
            title: first.title,
            profileId: first.profileId,
            profileSnapshot: first.profileSnapshot,
            panes: layout.panes,
            paneLayout: layout,
            activePaneSessionId: second.sessionId,
          ),
        ],
        activeSessionId: second.sessionId,
      );

      final identity = TerminalWorkspaceIdentity.forProject('/repo/ianvs');
      final workspace = LocalSessionWorkspaceCodec.capture(
        state,
        identity: identity,
      );

      expect(workspace.identity, identity);
      expect(workspace.activeTabId, first.sessionId);
      expect(workspace.activeTab!.activePaneId, second.sessionId);
      expect(
        workspace.activeTab!.root.direction,
        TerminalPaneSplitDirection.down,
      );
      expect(workspace.activeTab!.root.ratio, 0.63);
      expect(
        workspace.activeTab!.root.findPane(first.sessionId)!.sessionIntent!.cwd,
        '/current-cwd',
      );
      final firstDescriptor = workspace.activeTab!.root
          .findPane(first.sessionId)!
          .sessionDescriptor!;
      expect(firstDescriptor.id, 'descriptor-1');
      expect(firstDescriptor.command!.program, '/bin/zsh');
      expect(firstDescriptor.command!.arguments, ['-l']);
      expect(firstDescriptor.environment.keys, ['LANG', 'TOKEN']);
      expect(firstDescriptor.title, 'Root');
      expect(firstDescriptor.createdAtUtc, DateTime.utc(2026, 7, 21, 4, 30));
      expect(firstDescriptor.exitState, TerminalSessionExitState.running);
      expect(firstDescriptor.recordingPath, '/recordings/live-1.ndjson');
      expect(workspace.toJson().toString(), isNot(contains('secret-value')));
      expect(
        workspace.activeTab!.root
            .findPane(second.sessionId)!
            .sessionIntent!
            .cwd,
        profile.cwd,
      );
      final secondDescriptor = workspace.activeTab!.root
          .findPane(second.sessionId)!
          .sessionDescriptor!;
      expect(secondDescriptor.exitState, TerminalSessionExitState.exited);
      expect(secondDescriptor.exitCode, 9);
    });

    test('restores topology with newly relaunched session ids', () {
      final profile = defaultTerminalProfile();
      final workspace = TerminalWorkspace(
        activeTabId: 'old-tab',
        tabs: [
          TerminalWorkspaceTab(
            id: 'old-tab',
            activePaneId: 'old-2',
            root: TerminalPaneNode.split(
              id: 'old-split',
              direction: TerminalPaneSplitDirection.right,
              ratio: 0.42,
              first: TerminalPaneNode.leaf(
                id: 'old-1',
                sessionIntent: const TerminalPaneSessionIntent(
                  profileId: 'default',
                  cwd: '/one',
                ),
              ),
              second: TerminalPaneNode.leaf(
                id: 'old-2',
                sessionIntent: const TerminalPaneSessionIntent(
                  profileId: 'default',
                  cwd: '/two',
                ),
              ),
            ),
          ),
        ],
      );
      var nextId = 0;

      final restored = LocalSessionWorkspaceCodec.restore(
        workspace,
        relaunch: (intent) {
          nextId += 1;
          final launchProfile = profile.copyWith(cwd: intent.cwd);
          return TerminalPane(
            sessionId: 'new-$nextId',
            title: intent.title ?? launchProfile.name,
            profileId: launchProfile.id,
            profileSnapshot: launchProfile,
            sessionDescriptor: intent,
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
      expect(tab.effectivePanes.map((pane) => pane.profileSnapshot!.cwd), [
        '/one',
        '/two',
      ]);
      expect(tab.containsSession('old-1'), isFalse);
      expect(tab.containsSession('old-2'), isFalse);
      expect(tab.effectivePanes.map((pane) => pane.sessionDescriptor!.id), [
        'old-1',
        'old-2',
      ]);
    });

    test('reports failed relaunches and collapses their split branch', () {
      final profile = defaultTerminalProfile();
      final workspace = TerminalWorkspace(
        activeTabId: 'tab-1',
        tabs: [
          TerminalWorkspaceTab(
            id: 'tab-1',
            activePaneId: 'missing-pane',
            root: TerminalPaneNode.split(
              id: 'split-1',
              direction: TerminalPaneSplitDirection.down,
              first: TerminalPaneNode.leaf(
                id: 'good-pane',
                sessionIntent: const TerminalPaneSessionIntent(
                  profileId: 'default',
                ),
              ),
              second: TerminalPaneNode.leaf(
                id: 'missing-pane',
                sessionIntent: const TerminalPaneSessionIntent(
                  profileId: 'missing',
                ),
              ),
            ),
          ),
        ],
      );

      final restored = LocalSessionWorkspaceCodec.restore(
        workspace,
        relaunch: (intent) => intent.profileId == 'missing'
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

    test('does not invoke the relauncher when restart policy is never', () {
      final workspace = TerminalWorkspace(
        tabs: [
          TerminalWorkspaceTab(
            id: 'tab-1',
            activePaneId: 'pane-1',
            root: TerminalPaneNode.leaf(
              id: 'pane-1',
              sessionDescriptor: const TerminalSessionDescriptor(
                id: 'descriptor-1',
                profileId: 'default',
                restartPolicy: TerminalSessionRestartPolicy.never,
              ),
            ),
          ),
        ],
      );
      var relaunchAttempts = 0;

      final restored = LocalSessionWorkspaceCodec.restore(
        workspace,
        relaunch: (_) {
          relaunchAttempts += 1;
          return null;
        },
      );

      expect(relaunchAttempts, 0);
      expect(restored.tabs, isEmpty);
      expect(restored.failures, hasLength(1));
      expect(restored.failures.single.error, isA<StateError>());
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
    configurationWarnings: const [],
    themeMode: TerminalThemeMode.system,
    terminalViewportPadding:
        TerminalAppAppearance.defaultTerminalViewportPadding,
    isReady: true,
  );
}

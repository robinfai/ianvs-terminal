import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  test(
    'SSH connection chain includes jumps with independent host overrides',
    () {
      final profile = defaultTerminalProfile().copyWith(
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'app.example',
          user: 'deploy',
          port: 2200,
          proxyJump: 'alias,ops@[2001:db8::1]:2222',
          proxyJumpProfiles: [
            terminal.TerminalSshJumpConfig(
              host: 'bastion.example',
              user: 'admin',
              port: 2220,
            ),
            terminal.TerminalSshJumpConfig(),
          ],
        ),
      );
      final pane = TerminalPane(
        sessionId: 'ssh-chain',
        title: 'SSH',
        profileId: profile.id,
        profileSnapshot: profile,
      );
      final chain = pane.shellConnectionChain;
      expect(chain.map((hop) => hop.kind), [
        ShellConnectionHopKind.localClient,
        ShellConnectionHopKind.jump,
        ShellConnectionHopKind.jump,
        ShellConnectionHopKind.sshShell,
      ]);
      expect(chain.skip(1).map((hop) => hop.address), [
        'admin@bastion.example:2220',
        'ops@[2001:db8::1]:2222',
        'deploy@app.example:2200',
      ]);
      expect(chain.last.contextId, 'root');
      expect(chain.clear, throwsUnsupportedError);
    },
  );

  group('$SessionState title updates', () {
    test(
      'keeps layout identity only for title metadata and preserves state',
      () {
        final original = SessionState.initial().copyWith(
          tabs: [
            const TerminalTab(
              sessionId: 'root',
              title: 'Shell',
              profileId: 'local',
            ),
          ],
          activeSessionId: 'root',
          isReady: true,
          recordingSessionIds: {'root'},
          lastError: 'Retained error',
        );
        final renamed = original.withPaneTitle('root', 'Codex');
        expect(renamed.tabs.single.title, 'Codex');
        expect(original.tabs.single.title, 'Shell');
        expect(renamed.layoutIdentity, same(original.layoutIdentity));
        expect(
          renamed.withPaneTitle('root', 'Next').layoutIdentity,
          same(original.layoutIdentity),
        );
        expect(renamed.recordingSessionIds, same(original.recordingSessionIds));
        expect(renamed.lastError, original.lastError);
        expect(renamed.tabs.clear, throwsUnsupportedError);
        expect(renamed.withPaneTitle('root', 'Codex'), same(renamed));
        expect(renamed.withPaneTitle('missing', 'Codex'), same(renamed));
        for (final changed in [
          renamed.copyWith(activeSessionId: null),
          renamed.copyWith(terminalViewportPadding: 16),
          renamed.copyWith(tabs: []),
          renamed.copyWith(recordingBusySessionIds: {'root'}),
          renamed.copyWith(lastError: null),
        ]) {
          expect(changed.layoutIdentity, isNot(same(original.layoutIdentity)));
        }
      },
    );
  });

  group('Session state immutability', () {
    test('defensively copies collection constructor inputs', () {
      const tab = TerminalTab(
        sessionId: 'session-1',
        title: 'Session 1',
        profileId: 'default',
      );
      final profile = defaultTerminalProfile();
      const warning = TerminalProfileLoadWarning(
        profileId: 'default',
        profileName: 'Local Shell',
        path: r'$.profiles[0]',
        rawValueSummary: 'invalid value',
        fallbackSummary: 'used defaults',
      );
      final tabs = <TerminalTab>[tab];
      final profiles = <TerminalProfile>[profile];
      final warnings = <TerminalProfileLoadWarning>[warning];
      final reconnections = <String, String>{'attempt': tab.sessionId};

      final state = SessionState(
        tabs: tabs,
        activeSessionId: tab.sessionId,
        profiles: profiles,
        defaultProfileId: profile.id,
        configuredDefaultProfileId: profile.id,
        configurationWarnings: warnings,
        themeMode: TerminalThemeMode.system,
        languageMode: TerminalLanguageMode.system,
        terminalViewportPadding:
            TerminalAppAppearance.defaultTerminalViewportPadding,
        isReady: true,
        reconnectionTargets: reconnections,
      );
      tabs.clear();
      profiles.clear();
      warnings.clear();
      reconnections.clear();

      expect(state.tabs, <TerminalTab>[tab]);
      expect(state.profiles, <TerminalProfile>[profile]);
      expect(state.configurationWarnings, <TerminalProfileLoadWarning>[
        warning,
      ]);
      expect(state.tabs.clear, throwsUnsupportedError);
      expect(state.profiles.clear, throwsUnsupportedError);
      expect(state.configurationWarnings.clear, throwsUnsupportedError);
      expect(state.reconnectionTargets, {'attempt': tab.sessionId});
      expect(state.reconnectionTargets.clear, throwsUnsupportedError);
    });

    test('copyWith defensively copies replacement collections', () {
      final tabs = <TerminalTab>[
        const TerminalTab(
          sessionId: 'session-1',
          title: 'Session 1',
          profileId: 'default',
        ),
      ];
      final reconnections = <String, String>{'attempt': 'session-1'};

      final state = SessionState.initial().copyWith(
        tabs: tabs,
        reconnectionTargets: reconnections,
      );
      tabs.clear();
      reconnections.clear();

      expect(state.tabs, hasLength(1));
      expect(() => state.tabs.add(state.tabs.single), throwsUnsupportedError);
      expect(
        () => SessionState.initial().profiles.add(defaultTerminalProfile()),
        throwsUnsupportedError,
      );
      expect(state.reconnectionTargets, {'attempt': 'session-1'});
      expect(state.reconnectionTargets.clear, throwsUnsupportedError);
    });
  });

  group('Session reconnection chains', () {
    final first = _reconnectionTab('first', isExited: true);
    final second = _reconnectionTab('second', isExited: true);
    final live = _reconnectionTab('live');

    SessionState chain() => SessionState.initial().copyWith(
      tabs: [first, second, live],
      activeSessionId: 'first',
      reconnectionTargets: {'first': 'second', 'second': 'live'},
    );

    test(
      'resolves the live descendant rather than another same-profile pane',
      () {
        final original = chain();
        final state = original.copyWith(
          tabs: [...original.tabs, _reconnectionTab('independent')],
        );

        expect(state.liveReconnectionFor('first'), 'live');
        expect(state.liveReconnectionFor('second'), 'live');
        expect(state.liveReconnectionFor('independent'), isNull);
        expect(state.liveReconnectionFor('live'), isNull);
        expect(state.liveReconnectionFor('missing'), isNull);
        expect(state.latestReconnectionFor('first'), 'live');
        expect(state.latestReconnectionFor('independent'), 'independent');
        expect(state.latestReconnectionFor('missing'), 'missing');
      },
    );

    test('redirects across a removed intermediate diagnostic pane', () {
      final original = chain();

      final updated = original.copyWith(tabs: [first, live]);

      expect(updated.reconnectionTargets, {'first': 'live'});
      expect(updated.liveReconnectionFor('first'), 'live');
      expect(updated.liveReconnectionFor('second'), isNull);
      expect(original.reconnectionTargets, {
        'first': 'second',
        'second': 'live',
      });
      expect(updated.reconnectionTargets.clear, throwsUnsupportedError);
    });

    test(
      'closes three generations newest-first after pane layout reordering',
      () {
        for (final reordered in [
          [first.rootPane, second.rootPane, live.rootPane],
          [second.rootPane, first.rootPane, live.rootPane],
          [live.rootPane, first.rootPane, second.rootPane],
        ]) {
          final tab = first.copyWith(
            paneLayout: TerminalPaneLayoutNode.fromPanes(
              reordered,
              TerminalSplitAxis.horizontal,
            ),
          );
          final state = chain().copyWith(tabs: [tab]);

          expect(
            state.sessionIdsInCloseOrder(
              tab.effectivePanes.map((pane) => pane.sessionId),
            ),
            ['live', 'second', 'first'],
          );
        }
      },
    );

    test(
      'close order traverses unrequested links but returns only candidates',
      () {
        final state = chain();

        expect(state.sessionIdsInCloseOrder(['first', 'live']), [
          'live',
          'first',
        ]);
        expect(state.sessionIdsInCloseOrder(['first']), ['first']);
        expect(state.sessionIdsInCloseOrder(['second', 'second']), ['second']);
        expect(state.sessionIdsInCloseOrder([]), isEmpty);
        expect(state.sessionIdsInCloseOrder(['independent', 'first', 'live']), [
          'independent',
          'live',
          'first',
        ]);
      },
    );

    test('prunes closed live targets while retaining earlier diagnostics', () {
      final withoutLive = chain().copyWith(tabs: [first, second]);

      expect(withoutLive.reconnectionTargets, {'first': 'second'});
      expect(withoutLive.liveReconnectionFor('first'), isNull);
      expect(withoutLive.liveReconnectionFor('second'), isNull);
      expect(withoutLive.latestReconnectionFor('first'), 'second');
      final retried = withoutLive.copyWith(
        tabs: [...withoutLive.tabs, _reconnectionTab('retry')],
        reconnectionTargets: {
          ...withoutLive.reconnectionTargets,
          'second': 'retry',
        },
      );
      expect(retried.liveReconnectionFor('first'), 'retry');
      expect(retried.copyWith(tabs: []).reconnectionTargets, isEmpty);
    });

    test(
      'title and read-only metadata updates preserve reconnection targets',
      () {
        const integration = TerminalShellIntegrationSnapshot(
          currentDirectory: '/remote/work',
          lastCommand: 'deploy',
          lastExitCode: 255,
        );
        const runtimeError = TerminalPaneRuntimeErrorState(
          operation: 'ssh',
          message: 'Transport disconnected',
        );
        final original = chain().copyWith(
          tabs: [
            first.copyWith(
              exitCode: 255,
              shellIntegration: integration,
              runtimeError: runtimeError,
            ),
            second,
            live,
          ],
        );

        final renamed = original.withPaneTitle(
          'first',
          'Deployment diagnostics',
        );
        final updated = renamed.copyWith(
          tabs: [
            renamed.tabs.first.copyWith(oscBadge: 'Disconnected'),
            ...renamed.tabs.skip(1),
          ],
        );

        expect(renamed.reconnectionTargets, same(original.reconnectionTargets));
        expect(renamed.layoutIdentity, same(original.layoutIdentity));
        expect(updated.reconnectionTargets, original.reconnectionTargets);
        expect(updated.liveReconnectionFor('first'), 'live');
        final diagnostic = updated.tabs.first.activePane;
        expect(diagnostic.title, 'Deployment diagnostics');
        expect(diagnostic.isExited, isTrue);
        expect(diagnostic.exitCode, 255);
        expect(diagnostic.shellIntegration, same(integration));
        expect(diagnostic.runtimeError, same(runtimeError));
        expect(diagnostic.oscBadge, 'Disconnected');
        expect(original.tabs.first.title, 'first');
      },
    );

    test(
      'broken and cyclic chains do not resolve to an unrelated live pane',
      () {
        final state = chain().copyWith(
          reconnectionTargets: {'first': 'second', 'second': 'first'},
        );
        expect(state.liveReconnectionFor('first'), isNull);
        expect(state.liveReconnectionFor('second'), isNull);
        final removed = state.copyWith(tabs: [first, live]);
        expect(removed.reconnectionTargets, isEmpty);
        expect(removed.liveReconnectionFor('first'), isNull);
      },
    );
  });

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

    test('pane and tab copyWith can clear nullable state', () {
      final profile = defaultTerminalProfile();
      final pane = TerminalPane(
        sessionId: 'pane',
        title: 'pane',
        profileId: profile.id,
        profileSnapshot: profile,
        exitCode: 7,
      );
      final tab = TerminalTab(
        sessionId: 'tab',
        title: 'tab',
        profileId: profile.id,
        profileSnapshot: profile,
        exitCode: 9,
      );

      expect(pane.copyWith().profileSnapshot, profile);
      expect(pane.copyWith().exitCode, 7);
      expect(pane.copyWith(profileSnapshot: null).profileSnapshot, isNull);
      expect(pane.copyWith(exitCode: null).exitCode, isNull);
      expect(tab.copyWith().profileSnapshot, profile);
      expect(tab.copyWith().exitCode, 9);
      expect(tab.copyWith(profileSnapshot: null).profileSnapshot, isNull);
      expect(tab.copyWith(exitCode: null).exitCode, isNull);
    });

    test('session state copyWith normalizes terminal viewport padding', () {
      final state = SessionState.initial().copyWith(
        terminalViewportPadding: double.nan,
      );

      expect(
        state.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
    });

    test('replacing split root pane keeps tab root metadata synchronized', () {
      const oldProgress = TerminalPaneProgressState(
        source: 'osc9;4',
        named: false,
        action: 'set',
        state: 'normal',
        percent: 25,
        label: 'Old',
      );
      const newProgress = TerminalPaneProgressState(
        source: 'osc9;4',
        named: false,
        action: 'set',
        state: 'normal',
        percent: 80,
        label: 'Deploy',
      );
      final namedProgress = <String, TerminalPaneProgressState>{
        'build': const TerminalPaneProgressState(
          source: 'osc934',
          named: true,
          action: 'set',
          id: 'build',
          state: 'normal',
          percent: 60,
          label: 'Compile',
        ),
      };
      const notification = TerminalPaneNotificationState(
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

TerminalTab _reconnectionTab(String id, {bool isExited = false}) {
  return TerminalTab(
    sessionId: id,
    title: id,
    profileId: 'same-profile',
    isExited: isExited,
  );
}

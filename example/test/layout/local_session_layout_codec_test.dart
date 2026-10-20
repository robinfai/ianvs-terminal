import 'dart:convert';

import 'package:app/features/layout/local_session_layout_codec.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
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
        title: 'Second runtime',
        profileId: profile.id,
        profileSnapshot: profile,
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
      expect(encoded, isNot(contains('"command"')));
    });

    test('captures only live panes and collapses empty split branches', () {
      final profile = defaultTerminalProfile();
      final diagnostic = _pane('exited-root', profile, isExited: true);
      final first = _pane('live-first', profile);
      final second = _pane('live-second', profile);
      final tree = TerminalPaneLayoutNode.split(
        id: 'outer-split',
        splitAxis: TerminalSplitAxis.vertical,
        first: TerminalPaneLayoutNode.split(
          id: 'exited-split',
          splitAxis: TerminalSplitAxis.horizontal,
          first: TerminalPaneLayoutNode.leaf(diagnostic),
          second: TerminalPaneLayoutNode.leaf(
            _pane('exited-sibling', profile, isExited: true),
          ),
        ),
        second: TerminalPaneLayoutNode.split(
          id: 'surviving-split',
          splitAxis: TerminalSplitAxis.horizontal,
          ratio: 0.71,
          first: TerminalPaneLayoutNode.leaf(first),
          second: TerminalPaneLayoutNode.split(
            id: 'mixed-split',
            splitAxis: TerminalSplitAxis.vertical,
            first: TerminalPaneLayoutNode.leaf(
              _pane('exited-active', profile, isExited: true),
            ),
            second: TerminalPaneLayoutNode.leaf(second),
          ),
        ),
      );
      final tab = _tab(tree, activePaneId: 'exited-active');
      final state = _state(
        profiles: [profile],
        tabs: [tab],
        activeSessionId: 'exited-active',
      );

      final captured = LocalSessionLayoutCodec.capture(state);
      final saved = TerminalLayout.fromJson(
        jsonDecode(jsonEncode(captured.toJson())) as Map<String, dynamic>,
      );
      final launchCwds = <String?>[];
      final restored = LocalSessionLayoutCodec.restore(
        saved,
        relaunch: (spec) {
          launchCwds.add(spec.cwd);
          return _pane('new-${launchCwds.length}', profile);
        },
      );

      expect(captured.activeTabId, tab.sessionId);
      final savedTab = saved.tabs.single;
      expect(savedTab.activePaneId, first.sessionId);
      expect(savedTab.root.id, 'surviving-split');
      expect(savedTab.root.direction, TerminalPaneSplitDirection.right);
      expect(savedTab.root.ratio, 0.71);
      expect(savedTab.root.leafPaneIds, [first.sessionId, second.sessionId]);
      expect(launchCwds, ['/live-first', '/live-second']);
      expect(restored.activeSessionId, 'new-1');
      expect(restored.failures, isEmpty);

      // Saving must not dispose or replace diagnostic panes referenced by AI.
      expect(state.tabs.single, same(tab));
      expect(state.tabs.single.paneFor(diagnostic.sessionId), same(diagnostic));
      expect(state.tabs.single.effectivePanes, hasLength(5));
      expect(state.activeSessionId, 'exited-active');
    });

    test('preserves active live pane when its exited sibling is removed', () {
      final profile = defaultTerminalProfile();
      final live = _pane('active-live', profile).copyWith(
        runtimeError: const TerminalPaneRuntimeErrorState(
          operation: 'resize',
          message: 'A transient resize failure does not exit the session.',
        ),
      );
      final tab = _tab(
        TerminalPaneLayoutNode.split(
          id: 'split',
          splitAxis: TerminalSplitAxis.horizontal,
          first: TerminalPaneLayoutNode.leaf(
            _pane('exited', profile, isExited: true),
          ),
          second: TerminalPaneLayoutNode.leaf(live),
        ),
        activePaneId: live.sessionId,
      );

      final layout = LocalSessionLayoutCodec.capture(
        _state(
          profiles: [profile],
          tabs: [tab],
          activeSessionId: live.sessionId,
        ),
      );

      expect(layout.activeTabId, tab.sessionId);
      expect(layout.tabs.single.root.isLeaf, isTrue);
      expect(layout.tabs.single.root.id, live.sessionId);
      expect(layout.tabs.single.activePaneId, live.sessionId);
    });

    test('drops exited tabs and selects a surviving tab for restore', () {
      final profile = defaultTerminalProfile();
      final first = _tab(TerminalPaneLayoutNode.leaf(_pane('first', profile)));
      final last = _tab(TerminalPaneLayoutNode.leaf(_pane('last', profile)));
      final exited = TerminalTab(
        sessionId: 'exited-tab',
        title: 'Retained diagnostic output',
        profileId: profile.id,
        isExited: true,
        exitCode: 255,
      );

      final layout = LocalSessionLayoutCodec.capture(
        _state(
          profiles: [profile],
          tabs: [first, exited, last],
          activeSessionId: exited.sessionId,
        ),
      );

      expect(layout.tabs.map((tab) => tab.id), [
        first.sessionId,
        last.sessionId,
      ]);
      expect(layout.activeTabId, last.sessionId);
      expect(layout.activeTab!.activePaneId, last.activeSessionId);
      final restored = LocalSessionLayoutCodec.restore(
        TerminalLayout.fromJson(layout.toJson()),
        relaunch: (spec) => _pane('new${spec.cwd}', profile),
      );
      expect(restored.activeSessionId, 'new/last');
      expect(restored.tabs, hasLength(2));
    });

    test('an all-exited layout cannot relaunch diagnostic sessions', () {
      final profile = defaultTerminalProfile();
      final state = _state(
        profiles: [profile],
        tabs: [
          TerminalTab(
            sessionId: 'diagnostic',
            title: 'Connection refused',
            profileId: profile.id,
            isExited: true,
            exitCode: 255,
          ),
        ],
        activeSessionId: 'diagnostic',
      );

      final layout = LocalSessionLayoutCodec.capture(state);
      final encoded = layout.toJson();
      final restored = LocalSessionLayoutCodec.restore(
        TerminalLayout.fromJson(encoded),
        relaunch: (_) => fail('Exited diagnostics must not be relaunched.'),
      );

      expect(layout.tabs, isEmpty);
      expect(layout.activeTabId, isNull);
      expect(encoded['schemaVersion'], 1);
      expect(encoded['tabs'], isEmpty);
      expect(encoded['activeTabId'], isNull);
      expect(restored.tabs, isEmpty);
      expect(restored.activeSessionId, isNull);
      expect(restored.failures, isEmpty);
      expect(state.tabs.single.isExited, isTrue);
      expect(state.activeSessionId, 'diagnostic');
    });

    test('restores existing v1 layouts without runtime lifecycle fields', () {
      final profile = defaultTerminalProfile();
      final layout = TerminalLayout.fromJson({
        'schemaVersion': 1,
        'contract': 'ianvs-terminal-layout-v1',
        'activeTabId': 'saved-tab',
        'tabs': [
          {
            'id': 'saved-tab',
            'activePaneId': 'saved-pane',
            'root': {
              'id': 'saved-pane',
              'type': 'leaf',
              'relaunchSpec': {
                'schemaVersion': 1,
                'contract': 'ianvs-terminal-relaunch-spec-v1',
                'profileId': profile.id,
                'cwd': '/saved-working-directory',
              },
            },
          },
        ],
      });
      final launches = <TerminalRelaunchSpec>[];

      final restored = LocalSessionLayoutCodec.restore(
        layout,
        relaunch: (spec) {
          launches.add(spec);
          return _pane('fresh-session', profile);
        },
      );

      expect(launches, hasLength(1));
      expect(launches.single.profileId, profile.id);
      expect(launches.single.cwd, '/saved-working-directory');
      expect(restored.activeSessionId, 'fresh-session');
      expect(restored.failures, isEmpty);
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

TerminalPane _pane(
  String id,
  TerminalProfile profile, {
  bool isExited = false,
}) {
  return TerminalPane(
    sessionId: id,
    title: id,
    profileId: profile.id,
    profileSnapshot: profile,
    isExited: isExited,
    shellIntegration: TerminalShellIntegrationSnapshot(
      currentDirectory: '/$id',
    ),
  );
}

TerminalTab _tab(TerminalPaneLayoutNode tree, {String? activePaneId}) {
  final root = tree.panes.first;
  return TerminalTab(
    sessionId: root.sessionId,
    title: root.title,
    profileId: root.profileId,
    paneLayout: tree,
    activePaneSessionId: activePaneId,
  );
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
    languageMode: TerminalLanguageMode.system,
    terminalViewportPadding:
        TerminalAppAppearance.defaultTerminalViewportPadding,
    isReady: true,
  );
}

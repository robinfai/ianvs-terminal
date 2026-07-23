import 'package:app/features/workspace/local_terminal_layout_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local workspace model', () {
    test('workspace starts empty and can add an active tab', () {
      final workspace = const TerminalLayout().addTab(_tab('tab-1'));

      expect(workspace.isEmpty, isFalse);
      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.activePaneId, 'pane-1');
    });

    test('split active pane creates a pane tree and moves focus', () {
      final tab = _tab('tab-1').splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: const TerminalRelaunchSpec(
          profileId: 'default',
          cwd: '/tmp',
        ),
        direction: TerminalPaneSplitDirection.right,
      );

      expect(tab.root.isLeaf, isFalse);
      expect(tab.root.direction, TerminalPaneSplitDirection.right);
      expect(tab.activePaneId, 'pane-2');
      expect(tab.root.containsPane('pane-1'), isTrue);
      expect(tab.root.containsPane('pane-2'), isTrue);
    });

    test('close active pane falls back to remaining pane', () {
      final tab = _tab('tab-1')
          .splitActivePane(
            splitNodeId: 'split-1',
            newPaneId: 'pane-2',
            sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
            direction: TerminalPaneSplitDirection.down,
          )
          .closeActivePane();

      expect(tab.root.isLeaf, isTrue);
      expect(tab.activePaneId, 'pane-1');
      expect(tab.closedPanes, hasLength(1));
    });

    test('reopen closed pane restores the most recent closed pane', () {
      final tab = _tab('tab-1')
          .splitActivePane(
            splitNodeId: 'split-1',
            newPaneId: 'pane-2',
            sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
            direction: TerminalPaneSplitDirection.down,
          )
          .closeActivePane()
          .reopenClosedPane(splitNodeId: 'split-2');

      expect(tab.closedPanes, isEmpty);
      expect(tab.root.containsPane('pane-1'), isTrue);
      expect(tab.root.containsPane('pane-2'), isTrue);
      expect(tab.activePaneId, 'pane-2');
    });

    test('close last tab enters empty state and can reopen it', () {
      final closed = const TerminalLayout()
          .addTab(_tab('tab-1'))
          .closeActiveTab();

      expect(closed.isEmpty, isTrue);
      expect(closed.closedTabs, hasLength(1));

      final reopened = closed.reopenClosedTab();

      expect(reopened.isEmpty, isFalse);
      expect(reopened.activeTabId, 'tab-1');
      expect(reopened.closedTabs, isEmpty);
    });

    test('workspace keeps a bounded closed tab history', () {
      var workspace = const TerminalLayout();
      for (var index = 0; index < maxTerminalLayoutClosedTabs + 3; index += 1) {
        workspace = workspace.addTab(_tab('tab-$index'));
      }

      while (!workspace.isEmpty) {
        workspace = workspace.closeActiveTab();
      }

      expect(workspace.closedTabs, hasLength(maxTerminalLayoutClosedTabs));
      expect(
        workspace.closedTabs.map((tab) => tab.id).toList(growable: false),
        [
          for (var index = 0; index < maxTerminalLayoutClosedTabs; index += 1)
            'tab-$index',
        ],
      );
      expect(
        (workspace.toJson()['closedTabs'] as List<Object?>),
        hasLength(maxTerminalLayoutClosedTabs),
      );
    });

    test('workspace JSON excludes closed tabs by normalized active ids', () {
      final workspace = TerminalLayout(
        tabs: [_tab(' tab-1 ')],
        activeTabId: ' tab-1 ',
        closedTabs: [_tab('tab-1'), _tab('closed')],
      );

      final json = workspace.toJson();
      final closedTabs = json['closedTabs'] as List<Object?>;

      expect(closedTabs, hasLength(1));
      expect(closedTabs.single, containsPair('id', 'closed'));
    });

    test('workspace layout roundtrips local pane topology', () {
      final workspace = const TerminalLayout().addTab(
        _tab('tab-1').splitActivePane(
          splitNodeId: 'split-1',
          newPaneId: 'pane-2',
          sessionIntent: const TerminalRelaunchSpec(
            profileId: 'default',
            cwd: '/tmp',
          ),
          direction: TerminalPaneSplitDirection.right,
        ),
      );

      final decoded = TerminalLayout.fromJson(workspace.toJson());

      expect(decoded.activeTabId, 'tab-1');
      expect(
        decoded.activeTab!.root.direction,
        TerminalPaneSplitDirection.right,
      );
      expect(decoded.activeTab!.root.containsPane('pane-1'), isTrue);
      expect(decoded.activeTab!.root.containsPane('pane-2'), isTrue);
      expect(
        decoded.activeTab!.root.findPane('pane-2')!.sessionIntent!.cwd,
        '/tmp',
      );
    });

    test('workspace layout normalizes invalid active ids', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': 'missing-tab',
        'tabs': [
          {
            'id': 'tab-1',
            'activePaneId': 'pane-1',
            'root': {
              'id': 'pane-1',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
          {
            'id': 'tab-2',
            'activePaneId': 'missing-pane',
            'zoomedPaneId': 'missing-pane',
            'root': {
              'id': 'pane-2',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
        ],
      });

      expect(workspace.activeTabId, 'tab-2');
      expect(workspace.activeTab!.activePaneId, 'pane-2');
      expect(workspace.activeTab!.hasActivePane, isTrue);
      expect(workspace.activeTab!.zoomedPaneId, isNull);
    });

    test('workspace layout trims persisted identifiers', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': ' tab-1 ',
        'tabs': [
          {
            'id': ' tab-1 ',
            'activePaneId': ' pane-1 ',
            'zoomedPaneId': ' pane-1 ',
            'root': {
              'id': ' pane-1 ',
              'type': 'leaf',
              'sessionIntent': {'profileId': ' default ', 'cwd': ' /repo '},
            },
          },
        ],
        'closedTabs': [
          {
            'id': ' closed ',
            'activePaneId': ' closed-pane ',
            'root': {
              'id': ' closed-pane ',
              'type': 'leaf',
              'sessionIntent': {'profileId': '   ', 'cwd': '   '},
            },
          },
        ],
      });

      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.id, 'tab-1');
      expect(workspace.activeTab!.activePaneId, 'pane-1');
      expect(workspace.activeTab!.zoomedPaneId, 'pane-1');
      expect(workspace.activeTab!.root.id, 'pane-1');
      expect(workspace.activeTab!.activeSessionIntent!.profileId, 'default');
      expect(workspace.activeTab!.activeSessionIntent!.cwd, '/repo');
      expect(workspace.closedTabs.single.id, 'closed');
      expect(workspace.closedTabs.single.activeSessionIntent!.profileId, '');
      expect(workspace.closedTabs.single.activeSessionIntent!.cwd, isNull);
    });

    test('workspace compatibility intent writes descriptor fields', () {
      const intent = TerminalRelaunchSpec(
        profileId: ' default ',
        cwd: ' /repo ',
      );
      const blank = TerminalRelaunchSpec(profileId: '   ', cwd: '   ');

      expect(intent.toJson(), containsPair('profileId', 'default'));
      expect(intent.toJson(), containsPair('cwd', '/repo'));
      expect(
        intent.toJson(),
        containsPair('schemaVersion', currentTerminalRelaunchSpecVersion),
      );
      expect(blank.toJson(), containsPair('profileId', ''));
      expect(blank.toJson(), containsPair('cwd', null));
    });

    test('workspace JSON normalizes direct tab and pane identifiers', () {
      final workspace = TerminalLayout(
        activeTabId: 'tab-1',
        tabs: [
          _tab(' other '),
          TerminalLayoutTab(
            id: ' tab-1 ',
            activePaneId: ' pane-1 ',
            zoomedPaneId: ' pane-1 ',
            root: TerminalPaneNode.leaf(
              id: ' pane-1 ',
              sessionIntent: const TerminalRelaunchSpec(
                profileId: ' default ',
                cwd: ' /repo ',
              ),
            ),
            closedPanes: [
              TerminalPaneNode.leaf(
                id: '   ',
                sessionIntent: const TerminalRelaunchSpec(profileId: 'ignored'),
              ),
              TerminalPaneNode.leaf(
                id: ' closed-pane ',
                sessionIntent: const TerminalRelaunchSpec(
                  profileId: ' default ',
                ),
              ),
            ],
          ),
        ],
        closedTabs: [_tab(' tab-1 '), _tab(' closed ')],
      );

      expect(workspace.activeTab!.id, ' tab-1 ');

      final json = workspace.toJson();
      final tabs = json['tabs']! as List<Object?>;
      final activeTab = tabs.last! as Map<String, Object?>;
      final activeRoot = activeTab['root']! as Map<String, Object?>;
      final closedPanes = activeTab['closedPanes']! as List<Object?>;
      final closedTabs = json['closedTabs']! as List<Object?>;

      expect(json['activeTabId'], 'tab-1');
      expect(tabs.first, containsPair('id', 'other'));
      expect(activeTab['id'], 'tab-1');
      expect(activeTab['activePaneId'], 'pane-1');
      expect(activeTab['zoomedPaneId'], 'pane-1');
      expect(activeRoot['id'], 'pane-1');
      expect(closedPanes, hasLength(1));
      expect(closedPanes.single, containsPair('id', 'closed-pane'));
      expect(closedTabs, hasLength(1));
      expect(closedTabs.single, containsPair('id', 'closed'));
    });

    test('workspace layout skips malformed tabs and panes', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': 'missing-tab',
        'tabs': [
          {
            'id': '   ',
            'activePaneId': 'pane-ignored',
            'root': {
              'id': '   ',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
          {
            'id': 'tab-1',
            'activePaneId': 'missing-pane',
            'root': {
              'id': 'split-1',
              'type': 'split',
              'direction': 'right',
              'children': [
                {
                  'id': '   ',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'ignored'},
                },
                {
                  'id': ' pane-2 ',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': ' default '},
                },
              ],
            },
          },
        ],
        'closedTabs': [
          {
            'id': '   ',
            'root': {
              'id': '   ',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
          {
            'id': 'closed',
            'root': {
              'id': ' closed-pane ',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
        ],
      });

      expect(workspace.tabs, hasLength(1));
      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.activePaneId, 'pane-2');
      expect(workspace.activeTab!.activeSessionIntent!.profileId, 'default');
      expect(workspace.activeTab!.root.containsPane(''), isFalse);
      expect(workspace.closedTabs, hasLength(1));
      expect(workspace.closedTabs.single.id, 'closed');
    });

    test('workspace layout collapses malformed split children', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': 'tab-1',
        'tabs': [
          {
            'id': 'tab-1',
            'root': {
              'id': 'split-1',
              'type': 'split',
              'direction': 'right',
              'children': [
                {
                  'id': '   ',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'ignored'},
                },
                {
                  'id': ' pane-1 ',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': ' default '},
                },
              ],
            },
          },
        ],
      });

      final tab = workspace.activeTab!;
      expect(tab.activePaneId, 'pane-1');
      expect(tab.root.isLeaf, isTrue);
      expect(tab.root.containsPane(''), isFalse);
      expect((tab.toJson()['root']! as Map<String, Object?>)['id'], 'pane-1');
    });

    test('workspace layout skips malformed closed panes before reopen', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': 'tab-1',
        'tabs': [
          {
            'id': 'tab-1',
            'activePaneId': 'pane-1',
            'root': {
              'id': 'pane-1',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
            'closedPanes': [
              {
                'id': '   ',
                'type': 'leaf',
                'sessionIntent': {'profileId': 'ignored'},
              },
              {
                'id': ' closed-pane ',
                'type': 'leaf',
                'sessionIntent': {'profileId': ' default '},
              },
            ],
          },
        ],
      });

      final tab = workspace.activeTab!;
      expect(tab.closedPanes, hasLength(1));
      expect(tab.closedPanes.single.firstLeafId, 'closed-pane');

      final reopened = tab.reopenClosedPane(splitNodeId: 'split-1');
      expect(reopened.activePaneId, 'closed-pane');
      expect(reopened.root.containsPane(''), isFalse);
    });

    test('workspace layout limits persisted closed history scans', () {
      final tooManyMalformedClosedTabs = maxTerminalLayoutClosedTabs * 4 + 1;
      final tooManyMalformedClosedPanes = maxTerminalLayoutClosedPanes * 4 + 1;
      final workspace = TerminalLayout.fromLegacyWorkspaceJson({
        'activeTabId': 'tab-1',
        'tabs': [
          {
            'id': 'tab-1',
            'activePaneId': 'pane-1',
            'root': _leafJson('pane-1'),
            'closedPanes': [
              for (
                var index = 0;
                index < tooManyMalformedClosedPanes;
                index += 1
              )
                'malformed-pane-$index',
              _leafJson('closed-pane-too-late'),
            ],
          },
        ],
        'closedTabs': [
          for (var index = 0; index < tooManyMalformedClosedTabs; index += 1)
            'malformed-tab-$index',
          _tabJson('closed-too-late', 'closed-pane-too-late'),
        ],
      });

      expect(workspace.closedTabs, isEmpty);
      expect(workspace.activeTab!.closedPanes, isEmpty);
    });

    test('workspace layout limits persisted split child scans', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson({
        'activeTabId': 'tab-1',
        'tabs': [
          {
            'id': 'tab-1',
            'root': {
              'id': 'split-1',
              'type': 'split',
              'direction': 'right',
              'children': [
                for (var index = 0; index < 9; index += 1)
                  'malformed-child-$index',
                _leafJson('pane-too-late'),
              ],
            },
          },
        ],
      });

      expect(workspace.tabs, isEmpty);
      expect(workspace.activeTabId, isNull);
    });

    test('workspace keeps a bounded closed pane history', () {
      var tab = _tab('tab-1');
      for (
        var index = 0;
        index < maxTerminalLayoutClosedPanes + 3;
        index += 1
      ) {
        tab = tab
            .splitActivePane(
              splitNodeId: 'split-$index',
              newPaneId: 'closed-pane-$index',
              sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
              direction: TerminalPaneSplitDirection.right,
            )
            .closeActivePane();
      }

      expect(tab.closedPanes, hasLength(maxTerminalLayoutClosedPanes));
      expect(
        tab.closedPanes.map((pane) => pane.firstLeafId).toList(growable: false),
        [
          for (
            var index = maxTerminalLayoutClosedPanes + 2;
            index >= 3;
            index -= 1
          )
            'closed-pane-$index',
        ],
      );
      expect(
        (tab.toJson()['closedPanes'] as List<Object?>),
        hasLength(maxTerminalLayoutClosedPanes),
      );
    });

    test('workspace layout skips duplicate and blank tab ids', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'activeTabId': 'tab-1',
        'tabs': [
          {
            'id': 'tab-1',
            'activePaneId': 'pane-1',
            'root': {
              'id': 'pane-1',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
          {
            'id': ' tab-1 ',
            'activePaneId': 'duplicate-pane',
            'root': {
              'id': 'duplicate-pane',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'duplicate'},
            },
          },
          {
            'id': '   ',
            'activePaneId': 'blank-tab-pane',
            'root': {
              'id': 'blank-tab-pane',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'blank'},
            },
          },
          {
            'id': 'tab-2',
            'activePaneId': 'pane-2',
            'root': {
              'id': 'pane-2',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
        ],
        'closedTabs': [
          {
            'id': 'tab-1',
            'root': {
              'id': 'closed-conflict-pane',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'closed-conflict'},
            },
          },
          {
            'id': 'closed',
            'root': {
              'id': 'closed-pane',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'default'},
            },
          },
          {
            'id': ' closed ',
            'root': {
              'id': 'duplicate-closed-pane',
              'type': 'leaf',
              'sessionIntent': {'profileId': 'duplicate-closed'},
            },
          },
        ],
      });

      expect(
        workspace.tabs.map((tab) => tab.id).toList(growable: false),
        const ['tab-1', 'tab-2'],
      );
      expect(workspace.activeTab!.activeSessionIntent!.profileId, 'default');
      expect(workspace.closedTabs, hasLength(1));
      expect(workspace.closedTabs.single.id, 'closed');

      final closedActive = workspace.closeActiveTab();
      expect(
        closedActive.tabs.map((tab) => tab.id).toList(growable: false),
        const ['tab-2'],
      );
    });

    test('workspace layout rejects remote-only fields', () {
      expect(
        () => TerminalLayout.fromLegacyWorkspaceJson(const {
          'tabs': [],
          'remoteDomain': 'prod',
        }),
        throwsFormatException,
      );
    });

    test('workspace layout clamps persisted split ratios', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'tabs': [
          {
            'id': 'tab-1',
            'root': {
              'id': 'split-1',
              'type': 'split',
              'direction': 'right',
              'ratio': 2,
              'children': [
                {
                  'id': 'pane-1',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'default'},
                },
                {
                  'id': 'pane-2',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'default'},
                },
              ],
            },
          },
        ],
      });

      expect(workspace.tabs.single.root.ratio, 0.9);
    });

    test('workspace layout normalizes persisted split direction', () {
      final workspace = TerminalLayout.fromLegacyWorkspaceJson(const {
        'tabs': [
          {
            'id': 'tab-1',
            'root': {
              'id': 'split-1',
              'type': 'split',
              'direction': ' DOWN ',
              'children': [
                {
                  'id': 'pane-1',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'default'},
                },
                {
                  'id': 'pane-2',
                  'type': 'leaf',
                  'sessionIntent': {'profileId': 'default'},
                },
              ],
            },
          },
        ],
      });

      expect(
        workspace.tabs.single.root.direction,
        TerminalPaneSplitDirection.down,
      );
    });

    test('split nodes normalize direct ratio values', () {
      final first = TerminalPaneNode.leaf(
        id: 'pane-1',
        sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
      );
      final second = TerminalPaneNode.leaf(
        id: 'pane-2',
        sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
      );

      final high = TerminalPaneNode.split(
        id: 'high',
        direction: TerminalPaneSplitDirection.right,
        first: first,
        second: second,
        ratio: 2,
      );
      final low = TerminalPaneNode.split(
        id: 'low',
        direction: TerminalPaneSplitDirection.right,
        first: first,
        second: second,
        ratio: -1,
      );
      final nonFinite = TerminalPaneNode.split(
        id: 'non-finite',
        direction: TerminalPaneSplitDirection.right,
        first: first,
        second: second,
        ratio: double.infinity,
      );

      expect(high.ratio, 0.9);
      expect(low.ratio, 0.1);
      expect(nonFinite.ratio, 0.5);
    });

    test('focus, resize, swap, and zoom stay in the pane model', () {
      final splitTab = _tab('tab-1').splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
        direction: TerminalPaneSplitDirection.right,
      );

      final resized = splitTab
          .focusPane('pane-1')
          .resizeActiveSplit(0.25)
          .swapActivePaneWithSibling()
          .toggleZoomActivePane();

      expect(resized.activePaneId, 'pane-1');
      expect(resized.root.ratio, 0.75);
      expect(resized.root.children.first.id, 'pane-2');
      expect(resized.zoomedPaneId, 'pane-1');
      expect(resized.toggleZoomActivePane().isZoomed, isFalse);
    });

    test('direct tab operations recover from a stale active pane id', () {
      final staleTab = TerminalLayoutTab(
        id: 'tab-1',
        activePaneId: 'missing-pane',
        zoomedPaneId: 'missing-pane',
        root: TerminalPaneNode.leaf(
          id: 'pane-1',
          sessionIntent: const TerminalRelaunchSpec(
            profileId: 'default',
            cwd: '/project',
          ),
        ),
      );

      expect(staleTab.effectiveActivePaneId, 'pane-1');
      expect(staleTab.effectiveZoomedPaneId, isNull);
      expect(staleTab.isZoomed, isFalse);
      expect(staleTab.activeSessionIntent!.cwd, '/project');
      expect(staleTab.toJson()['activePaneId'], 'pane-1');
      expect(staleTab.toJson()['zoomedPaneId'], isNull);

      final split = staleTab.splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: staleTab.activeSessionIntent!,
        direction: TerminalPaneSplitDirection.right,
      );

      expect(split.root.containsPane('pane-1'), isTrue);
      expect(split.root.containsPane('pane-2'), isTrue);
      expect(split.activePaneId, 'pane-2');
    });

    test('resize and swap target the nearest nested split', () {
      final nestedTab = _tab('tab-1')
          .splitActivePane(
            splitNodeId: 'root-split',
            newPaneId: 'pane-2',
            sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
            direction: TerminalPaneSplitDirection.right,
          )
          .focusPane('pane-1')
          .splitActivePane(
            splitNodeId: 'nested-split',
            newPaneId: 'pane-3',
            sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
            direction: TerminalPaneSplitDirection.down,
          );

      final resized = nestedTab.resizeActiveSplit(0.75);
      final nestedSplit = resized.root.children.first;

      expect(resized.root.ratio, 0.5);
      expect(nestedSplit.ratio, 0.75);

      final swapped = resized.swapActivePaneWithSibling();
      final swappedNestedSplit = swapped.root.children.first;

      expect(swapped.root.children.last.id, 'pane-2');
      expect(swappedNestedSplit.children.first.id, 'pane-3');
      expect(swappedNestedSplit.children.last.id, 'pane-1');
    });

    test('resize active split defaults non-finite ratios', () {
      final splitTab = _tab('tab-1').splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: const TerminalRelaunchSpec(profileId: 'default'),
        direction: TerminalPaneSplitDirection.right,
      );

      expect(splitTab.resizeActiveSplit(double.nan).root.ratio, 0.5);
      expect(splitTab.resizeActiveSplit(double.infinity).root.ratio, 0.5);
    });

    test('new tab and split can inherit active cwd intent', () {
      final workspace = const TerminalLayout()
          .addTab(_tab('tab-1', cwd: '/project'))
          .addTabFromActivePane(
            tabId: 'tab-2',
            paneId: 'pane-2',
            fallbackIntent: const TerminalRelaunchSpec(
              profileId: 'fallback',
              cwd: '/fallback',
            ),
          )
          .splitActivePaneFromActiveCwd(
            splitNodeId: 'split-1',
            newPaneId: 'pane-3',
            direction: TerminalPaneSplitDirection.down,
            fallbackIntent: const TerminalRelaunchSpec(
              profileId: 'fallback',
              cwd: '/fallback',
            ),
          );

      expect(workspace.activeTabId, 'tab-2');
      expect(
        workspace.activeTab!.root.findPane('pane-2')!.sessionIntent!.cwd,
        '/project',
      );
      expect(
        workspace.activeTab!.root.findPane('pane-3')!.sessionIntent!.cwd,
        '/project',
      );
    });
  });
}

TerminalLayoutTab _tab(String id, {String? cwd}) {
  return TerminalLayoutTab(
    id: id,
    activePaneId: 'pane-1',
    root: TerminalPaneNode.leaf(
      id: 'pane-1',
      sessionIntent: TerminalRelaunchSpec(profileId: 'default', cwd: cwd),
    ),
  );
}

Map<String, Object?> _tabJson(String tabId, String paneId) {
  return {'id': tabId, 'activePaneId': paneId, 'root': _leafJson(paneId)};
}

Map<String, Object?> _leafJson(String paneId) {
  return {
    'id': paneId,
    'type': 'leaf',
    'sessionIntent': {'profileId': 'default'},
  };
}

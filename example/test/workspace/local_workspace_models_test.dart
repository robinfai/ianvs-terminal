import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local workspace model', () {
    test('workspace starts empty and can add an active tab', () {
      final workspace = const TerminalWorkspace().addTab(_tab('tab-1'));

      expect(workspace.isEmpty, isFalse);
      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.activePaneId, 'pane-1');
    });

    test('split active pane creates a pane tree and moves focus', () {
      final tab = _tab('tab-1').splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: const TerminalPaneSessionIntent(
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
            sessionIntent: const TerminalPaneSessionIntent(
              profileId: 'default',
            ),
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
            sessionIntent: const TerminalPaneSessionIntent(
              profileId: 'default',
            ),
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
      final closed = const TerminalWorkspace()
          .addTab(_tab('tab-1'))
          .closeActiveTab();

      expect(closed.isEmpty, isTrue);
      expect(closed.closedTabs, hasLength(1));

      final reopened = closed.reopenClosedTab();

      expect(reopened.isEmpty, isFalse);
      expect(reopened.activeTabId, 'tab-1');
      expect(reopened.closedTabs, isEmpty);
    });

    test('workspace layout roundtrips local pane topology', () {
      final workspace = const TerminalWorkspace().addTab(
        _tab('tab-1').splitActivePane(
          splitNodeId: 'split-1',
          newPaneId: 'pane-2',
          sessionIntent: const TerminalPaneSessionIntent(
            profileId: 'default',
            cwd: '/tmp',
          ),
          direction: TerminalPaneSplitDirection.right,
        ),
      );

      final decoded = TerminalWorkspace.fromJson(workspace.toJson());

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

    test('workspace layout rejects remote-only fields', () {
      expect(
        () => TerminalWorkspace.fromJson(const {
          'tabs': [],
          'remoteDomain': 'prod',
        }),
        throwsFormatException,
      );
    });

    test('workspace layout clamps persisted split ratios', () {
      final workspace = TerminalWorkspace.fromJson(const {
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

    test('focus, resize, swap, and zoom stay in the pane model', () {
      final splitTab = _tab('tab-1').splitActivePane(
        splitNodeId: 'split-1',
        newPaneId: 'pane-2',
        sessionIntent: const TerminalPaneSessionIntent(profileId: 'default'),
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

    test('resize and swap target the nearest nested split', () {
      final nestedTab = _tab('tab-1')
          .splitActivePane(
            splitNodeId: 'root-split',
            newPaneId: 'pane-2',
            sessionIntent: const TerminalPaneSessionIntent(
              profileId: 'default',
            ),
            direction: TerminalPaneSplitDirection.right,
          )
          .focusPane('pane-1')
          .splitActivePane(
            splitNodeId: 'nested-split',
            newPaneId: 'pane-3',
            sessionIntent: const TerminalPaneSessionIntent(
              profileId: 'default',
            ),
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

    test('new tab and split can inherit active cwd intent', () {
      final workspace = const TerminalWorkspace()
          .addTab(_tab('tab-1', cwd: '/project'))
          .addTabFromActivePane(
            tabId: 'tab-2',
            paneId: 'pane-2',
            fallbackIntent: const TerminalPaneSessionIntent(
              profileId: 'fallback',
              cwd: '/fallback',
            ),
          )
          .splitActivePaneFromActiveCwd(
            splitNodeId: 'split-1',
            newPaneId: 'pane-3',
            direction: TerminalPaneSplitDirection.down,
            fallbackIntent: const TerminalPaneSessionIntent(
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

TerminalWorkspaceTab _tab(String id, {String? cwd}) {
  return TerminalWorkspaceTab(
    id: id,
    activePaneId: 'pane-1',
    root: TerminalPaneNode.leaf(
      id: 'pane-1',
      sessionIntent: TerminalPaneSessionIntent(profileId: 'default', cwd: cwd),
    ),
  );
}

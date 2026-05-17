enum TerminalPaneSplitDirection { right, down }

class TerminalPaneSessionIntent {
  const TerminalPaneSessionIntent({required this.profileId, this.cwd});

  final String profileId;
  final String? cwd;

  Map<String, Object?> toJson() {
    return {'profileId': profileId, 'cwd': cwd};
  }

  static TerminalPaneSessionIntent fromJson(Map<Object?, Object?> json) {
    return TerminalPaneSessionIntent(
      profileId: json['profileId'] as String? ?? '',
      cwd: json['cwd'] as String?,
    );
  }
}

class TerminalWorkspace {
  const TerminalWorkspace({
    this.tabs = const <TerminalWorkspaceTab>[],
    this.activeTabId,
    this.closedTabs = const <TerminalWorkspaceTab>[],
  });

  final List<TerminalWorkspaceTab> tabs;
  final String? activeTabId;
  final List<TerminalWorkspaceTab> closedTabs;

  bool get isEmpty => tabs.isEmpty;

  Map<String, Object?> toJson() {
    return {
      'tabs': tabs.map((tab) => tab.toJson()).toList(growable: false),
      'activeTabId': activeTabId,
      'closedTabs': closedTabs
          .map((tab) => tab.toJson())
          .toList(growable: false),
    };
  }

  static TerminalWorkspace fromJson(Map<Object?, Object?> json) {
    _rejectRemoteWorkspaceKeys(json);

    final tabs = _objectList(
      json['tabs'],
    ).map(TerminalWorkspaceTab.fromJson).toList(growable: false);
    final closedTabs = _objectList(
      json['closedTabs'],
    ).map(TerminalWorkspaceTab.fromJson).toList(growable: false);

    return TerminalWorkspace(
      tabs: tabs,
      activeTabId: json['activeTabId'] as String?,
      closedTabs: closedTabs,
    );
  }

  TerminalWorkspaceTab? get activeTab {
    for (final tab in tabs) {
      if (tab.id == activeTabId) {
        return tab;
      }
    }
    return tabs.isEmpty ? null : tabs.last;
  }

  TerminalWorkspace addTab(TerminalWorkspaceTab tab) {
    return TerminalWorkspace(
      tabs: [...tabs, tab],
      activeTabId: tab.id,
      closedTabs: closedTabs,
    );
  }

  TerminalWorkspace addTabFromActivePane({
    required String tabId,
    required String paneId,
    required TerminalPaneSessionIntent fallbackIntent,
  }) {
    final intent = activeTab?.activeSessionIntent ?? fallbackIntent;
    return addTab(
      TerminalWorkspaceTab(
        id: tabId,
        activePaneId: paneId,
        root: TerminalPaneNode.leaf(id: paneId, sessionIntent: intent),
      ),
    );
  }

  TerminalWorkspace splitActivePaneFromActiveCwd({
    required String splitNodeId,
    required String newPaneId,
    required TerminalPaneSplitDirection direction,
    required TerminalPaneSessionIntent fallbackIntent,
  }) {
    final tab = activeTab;
    if (tab == null) {
      return this;
    }

    final intent = tab.activeSessionIntent ?? fallbackIntent;
    return updateActiveTab(
      (active) => active.splitActivePane(
        splitNodeId: splitNodeId,
        newPaneId: newPaneId,
        sessionIntent: intent,
        direction: direction,
      ),
    );
  }

  TerminalWorkspace closeActiveTab() {
    final tab = activeTab;
    if (tab == null) {
      return this;
    }

    final nextTabs = tabs.where((candidate) => candidate.id != tab.id).toList();
    return TerminalWorkspace(
      tabs: nextTabs,
      activeTabId: nextTabs.isEmpty ? null : nextTabs.last.id,
      closedTabs: [tab, ...closedTabs],
    );
  }

  TerminalWorkspace reopenClosedTab() {
    if (closedTabs.isEmpty) {
      return this;
    }

    final tab = closedTabs.first;
    return TerminalWorkspace(
      tabs: [...tabs, tab],
      activeTabId: tab.id,
      closedTabs: closedTabs.skip(1).toList(),
    );
  }

  TerminalWorkspace updateActiveTab(
    TerminalWorkspaceTab Function(TerminalWorkspaceTab tab) update,
  ) {
    final tab = activeTab;
    if (tab == null) {
      return this;
    }

    final updatedTab = update(tab);
    return TerminalWorkspace(
      tabs: [
        for (final candidate in tabs)
          if (candidate.id == tab.id) updatedTab else candidate,
      ],
      activeTabId: updatedTab.id,
      closedTabs: closedTabs,
    );
  }
}

class TerminalWorkspaceTab {
  const TerminalWorkspaceTab({
    required this.id,
    required this.root,
    required this.activePaneId,
    this.closedPanes = const <TerminalPaneNode>[],
    this.zoomedPaneId,
  });

  final String id;
  final TerminalPaneNode root;
  final String activePaneId;
  final List<TerminalPaneNode> closedPanes;
  final String? zoomedPaneId;

  bool get hasActivePane => root.containsPane(activePaneId);
  bool get isZoomed => zoomedPaneId != null;
  TerminalPaneSessionIntent? get activeSessionIntent {
    return root.findPane(activePaneId)?.sessionIntent;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'activePaneId': activePaneId,
      'root': root.toJson(),
      'closedPanes': closedPanes
          .map((pane) => pane.toJson())
          .toList(growable: false),
      'zoomedPaneId': zoomedPaneId,
    };
  }

  static TerminalWorkspaceTab fromJson(Map<Object?, Object?> json) {
    final root = TerminalPaneNode.fromJson(
      _objectMap(json['root']) ?? const {},
    );
    return TerminalWorkspaceTab(
      id: json['id'] as String? ?? '',
      root: root,
      activePaneId: json['activePaneId'] as String? ?? root.firstLeafId,
      closedPanes: _objectList(
        json['closedPanes'],
      ).map(TerminalPaneNode.fromJson).toList(growable: false),
      zoomedPaneId: json['zoomedPaneId'] as String?,
    );
  }

  TerminalWorkspaceTab focusPane(String paneId) {
    if (!root.containsPane(paneId)) {
      return this;
    }

    return TerminalWorkspaceTab(
      id: id,
      root: root,
      activePaneId: paneId,
      closedPanes: closedPanes,
      zoomedPaneId: zoomedPaneId,
    );
  }

  TerminalWorkspaceTab resizeActiveSplit(double ratio) {
    return TerminalWorkspaceTab(
      id: id,
      root: root.resizeSplitContainingPane(activePaneId, ratio),
      activePaneId: activePaneId,
      closedPanes: closedPanes,
      zoomedPaneId: zoomedPaneId,
    );
  }

  TerminalWorkspaceTab swapActivePaneWithSibling() {
    return TerminalWorkspaceTab(
      id: id,
      root: root.swapPaneWithSibling(activePaneId),
      activePaneId: activePaneId,
      closedPanes: closedPanes,
      zoomedPaneId: zoomedPaneId,
    );
  }

  TerminalWorkspaceTab toggleZoomActivePane() {
    return TerminalWorkspaceTab(
      id: id,
      root: root,
      activePaneId: activePaneId,
      closedPanes: closedPanes,
      zoomedPaneId: zoomedPaneId == activePaneId ? null : activePaneId,
    );
  }

  TerminalWorkspaceTab splitActivePane({
    required String splitNodeId,
    required String newPaneId,
    required TerminalPaneSessionIntent sessionIntent,
    required TerminalPaneSplitDirection direction,
  }) {
    final active = root.findPane(activePaneId);
    if (active == null || !active.isLeaf) {
      return this;
    }

    final replacement = TerminalPaneNode.split(
      id: splitNodeId,
      direction: direction,
      first: active,
      second: TerminalPaneNode.leaf(
        id: newPaneId,
        sessionIntent: sessionIntent,
      ),
    );

    return TerminalWorkspaceTab(
      id: id,
      root: root.replacePane(activePaneId, replacement),
      activePaneId: newPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: zoomedPaneId,
    );
  }

  TerminalWorkspaceTab closeActivePane() {
    if (root.isLeaf) {
      return this;
    }

    final active = root.findPane(activePaneId);
    final nextRoot = root.removePane(activePaneId);
    if (nextRoot == null) {
      return this;
    }

    return TerminalWorkspaceTab(
      id: id,
      root: nextRoot,
      activePaneId: nextRoot.firstLeafId,
      closedPanes: [?active, ...closedPanes],
      zoomedPaneId: zoomedPaneId == activePaneId ? null : zoomedPaneId,
    );
  }

  TerminalWorkspaceTab reopenClosedPane({
    required String splitNodeId,
    TerminalPaneSplitDirection direction = TerminalPaneSplitDirection.right,
  }) {
    if (closedPanes.isEmpty) {
      return this;
    }

    final pane = closedPanes.first;
    final replacement = TerminalPaneNode.split(
      id: splitNodeId,
      direction: direction,
      first: root,
      second: pane,
    );

    return TerminalWorkspaceTab(
      id: id,
      root: replacement,
      activePaneId: pane.firstLeafId,
      closedPanes: closedPanes.skip(1).toList(growable: false),
      zoomedPaneId: zoomedPaneId,
    );
  }
}

class TerminalPaneNode {
  const TerminalPaneNode._({
    required this.id,
    required this.direction,
    required this.children,
    required this.sessionIntent,
    required this.ratio,
  });

  factory TerminalPaneNode.leaf({
    required String id,
    required TerminalPaneSessionIntent sessionIntent,
  }) {
    return TerminalPaneNode._(
      id: id,
      direction: null,
      children: const <TerminalPaneNode>[],
      sessionIntent: sessionIntent,
      ratio: 0.5,
    );
  }

  factory TerminalPaneNode.split({
    required String id,
    required TerminalPaneSplitDirection direction,
    required TerminalPaneNode first,
    required TerminalPaneNode second,
    double ratio = 0.5,
  }) {
    return TerminalPaneNode._(
      id: id,
      direction: direction,
      children: [first, second],
      sessionIntent: null,
      ratio: ratio,
    );
  }

  final String id;
  final TerminalPaneSplitDirection? direction;
  final List<TerminalPaneNode> children;
  final TerminalPaneSessionIntent? sessionIntent;
  final double ratio;

  bool get isLeaf => sessionIntent != null;

  Map<String, Object?> toJson() {
    if (isLeaf) {
      return {
        'id': id,
        'type': 'leaf',
        'sessionIntent': sessionIntent!.toJson(),
      };
    }

    return {
      'id': id,
      'type': 'split',
      'direction': direction!.name,
      'ratio': ratio,
      'children': children
          .map((child) => child.toJson())
          .toList(growable: false),
    };
  }

  static TerminalPaneNode fromJson(Map<Object?, Object?> json) {
    if (json['type'] == 'split') {
      final children = _objectList(
        json['children'],
      ).map(TerminalPaneNode.fromJson).toList(growable: false);
      return TerminalPaneNode.split(
        id: json['id'] as String? ?? '',
        direction: _splitDirection(json['direction']),
        first: children.isEmpty ? _emptyLeaf() : children.first,
        second: children.length < 2 ? _emptyLeaf() : children[1],
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0.5,
      );
    }

    return TerminalPaneNode.leaf(
      id: json['id'] as String? ?? '',
      sessionIntent: TerminalPaneSessionIntent.fromJson(
        _objectMap(json['sessionIntent']) ?? const {},
      ),
    );
  }

  String get firstLeafId {
    if (isLeaf) {
      return id;
    }
    return children.first.firstLeafId;
  }

  bool containsPane(String paneId) {
    return findPane(paneId) != null;
  }

  TerminalPaneNode? findPane(String paneId) {
    if (isLeaf) {
      return id == paneId ? this : null;
    }

    for (final child in children) {
      final found = child.findPane(paneId);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  TerminalPaneNode replacePane(String paneId, TerminalPaneNode replacement) {
    if (isLeaf) {
      return id == paneId ? replacement : this;
    }

    return TerminalPaneNode.split(
      id: id,
      direction: direction!,
      first: children.first.replacePane(paneId, replacement),
      second: children.last.replacePane(paneId, replacement),
      ratio: ratio,
    );
  }

  TerminalPaneNode resizeSplitContainingPane(String paneId, double nextRatio) {
    if (isLeaf) {
      return this;
    }

    final clampedRatio = nextRatio.clamp(0.1, 0.9).toDouble();
    if (children.first.containsPane(paneId) ||
        children.last.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: children.first,
        second: children.last,
        ratio: clampedRatio,
      );
    }

    return this;
  }

  TerminalPaneNode swapPaneWithSibling(String paneId) {
    if (isLeaf) {
      return this;
    }

    if (children.first.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: children.last,
        second: children.first,
        ratio: 1 - ratio,
      );
    }

    if (children.last.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: children.last,
        second: children.first,
        ratio: 1 - ratio,
      );
    }

    return this;
  }

  TerminalPaneNode? removePane(String paneId) {
    if (isLeaf) {
      return id == paneId ? null : this;
    }

    final first = children.first.removePane(paneId);
    final second = children.last.removePane(paneId);
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }

    return TerminalPaneNode.split(
      id: id,
      direction: direction!,
      first: first,
      second: second,
      ratio: ratio,
    );
  }
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<Object?, Object?>();
  }
  return null;
}

List<Map<Object?, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }

  return value
      .map(_objectMap)
      .whereType<Map<Object?, Object?>>()
      .toList(growable: false);
}

TerminalPaneSplitDirection _splitDirection(Object? value) {
  if (value is String) {
    for (final direction in TerminalPaneSplitDirection.values) {
      if (direction.name == value) {
        return direction;
      }
    }
  }
  return TerminalPaneSplitDirection.right;
}

TerminalPaneNode _emptyLeaf() {
  return TerminalPaneNode.leaf(
    id: '',
    sessionIntent: const TerminalPaneSessionIntent(profileId: ''),
  );
}

void _rejectRemoteWorkspaceKeys(Map<Object?, Object?> json) {
  const forbidden = {
    'ssh',
    'sshSession',
    'remote',
    'remoteDomain',
    'remoteSession',
    'sftp',
    'serial',
  };
  final matches = json.keys.where(forbidden.contains).toList();
  if (matches.isEmpty) {
    return;
  }

  throw FormatException(
    'TerminalWorkspace layout does not accept remote-only fields: '
    '${matches.join(', ')}',
  );
}

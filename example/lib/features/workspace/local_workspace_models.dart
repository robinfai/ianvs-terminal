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
      profileId: _nonEmptyStringOrNull(json['profileId']) ?? '',
      cwd: _nonEmptyStringOrNull(json['cwd']),
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

    final tabs = _objectList(json['tabs'])
        .map(TerminalWorkspaceTab.fromJson)
        .where((tab) => tab.isRestorable)
        .toList(growable: false);
    final closedTabs = _objectList(json['closedTabs'])
        .map(TerminalWorkspaceTab.fromJson)
        .where((tab) => tab.isRestorable)
        .toList(growable: false);
    final rawActiveTabId = _nonEmptyStringOrNull(json['activeTabId']);
    final activeTabId =
        rawActiveTabId != null &&
            tabs.any((candidate) => candidate.id == rawActiveTabId)
        ? rawActiveTabId
        : _lastNonEmptyTabId(tabs);

    return TerminalWorkspace(
      tabs: tabs,
      activeTabId: activeTabId,
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
  bool get isRestorable => root.hasRestorablePane;

  String get effectiveActivePaneId {
    return hasActivePane ? activePaneId : root.firstLeafId;
  }

  String? get effectiveZoomedPaneId {
    final paneId = zoomedPaneId;
    if (paneId == null || !root.containsPane(paneId)) {
      return null;
    }
    return paneId;
  }

  bool get isZoomed => effectiveZoomedPaneId != null;
  TerminalPaneSessionIntent? get activeSessionIntent {
    return root.findPane(effectiveActivePaneId)?.sessionIntent;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'activePaneId': effectiveActivePaneId,
      'root': root.toJson(),
      'closedPanes': closedPanes
          .map((pane) => pane.toJson())
          .toList(growable: false),
      'zoomedPaneId': effectiveZoomedPaneId,
    };
  }

  static TerminalWorkspaceTab fromJson(Map<Object?, Object?> json) {
    final root = TerminalPaneNode.fromJson(
      _objectMap(json['root']) ?? const {},
    );
    final rawActivePaneId = _nonEmptyStringOrNull(json['activePaneId']);
    final activePaneId =
        rawActivePaneId != null && root.containsPane(rawActivePaneId)
        ? rawActivePaneId
        : root.firstLeafId;
    final rawZoomedPaneId = _nonEmptyStringOrNull(json['zoomedPaneId']);
    final zoomedPaneId =
        rawZoomedPaneId != null && root.containsPane(rawZoomedPaneId)
        ? rawZoomedPaneId
        : null;
    return TerminalWorkspaceTab(
      id: _nonEmptyStringOrNull(json['id']) ?? '',
      root: root,
      activePaneId: activePaneId,
      closedPanes: _objectList(
        json['closedPanes'],
      ).map(TerminalPaneNode.fromJson).toList(growable: false),
      zoomedPaneId: zoomedPaneId,
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
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalWorkspaceTab focusRelativePane(int delta) {
    final paneIds = root.leafPaneIds;
    if (paneIds.length < 2) {
      return this;
    }
    final activeIndex = paneIds.indexOf(effectiveActivePaneId);
    if (activeIndex < 0) {
      return focusPane(paneIds.first);
    }
    final nextIndex = (activeIndex + delta) % paneIds.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + paneIds.length
        : nextIndex;
    return focusPane(paneIds[normalizedIndex]);
  }

  TerminalWorkspaceTab growActivePane(double delta) {
    final targetPaneId = effectiveActivePaneId;
    return TerminalWorkspaceTab(
      id: id,
      root: root.growPane(targetPaneId, delta),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalWorkspaceTab resizeActiveSplit(double ratio) {
    final targetPaneId = effectiveActivePaneId;
    return TerminalWorkspaceTab(
      id: id,
      root: root.resizeSplitContainingPane(targetPaneId, ratio),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalWorkspaceTab swapActivePaneWithSibling() {
    final targetPaneId = effectiveActivePaneId;
    return TerminalWorkspaceTab(
      id: id,
      root: root.swapPaneWithSibling(targetPaneId),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalWorkspaceTab toggleZoomActivePane() {
    final targetPaneId = effectiveActivePaneId;
    final currentZoomedPaneId = effectiveZoomedPaneId;
    return TerminalWorkspaceTab(
      id: id,
      root: root,
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: currentZoomedPaneId == targetPaneId ? null : targetPaneId,
    );
  }

  TerminalWorkspaceTab splitActivePane({
    required String splitNodeId,
    required String newPaneId,
    required TerminalPaneSessionIntent sessionIntent,
    required TerminalPaneSplitDirection direction,
  }) {
    final targetPaneId = effectiveActivePaneId;
    final active = root.findPane(targetPaneId);
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
      root: root.replacePane(targetPaneId, replacement),
      activePaneId: newPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalWorkspaceTab closeActivePane() {
    final targetPaneId = effectiveActivePaneId;
    final currentZoomedPaneId = effectiveZoomedPaneId;
    if (root.isLeaf) {
      if (targetPaneId == activePaneId) {
        return this;
      }
      return TerminalWorkspaceTab(
        id: id,
        root: root,
        activePaneId: targetPaneId,
        closedPanes: closedPanes,
        zoomedPaneId: currentZoomedPaneId,
      );
    }

    final active = root.findPane(targetPaneId);
    final nextRoot = root.removePane(targetPaneId);
    if (nextRoot == null) {
      return this;
    }

    return TerminalWorkspaceTab(
      id: id,
      root: nextRoot,
      activePaneId: nextRoot.firstLeafId,
      closedPanes: [?active, ...closedPanes],
      zoomedPaneId: currentZoomedPaneId == targetPaneId
          ? null
          : currentZoomedPaneId,
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
      zoomedPaneId: effectiveZoomedPaneId,
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
      ratio: _normalizeSplitRatio(ratio, 0.5),
    );
  }

  final String id;
  final TerminalPaneSplitDirection? direction;
  final List<TerminalPaneNode> children;
  final TerminalPaneSessionIntent? sessionIntent;
  final double ratio;

  bool get isLeaf => sessionIntent != null;
  bool get hasRestorablePane {
    if (isLeaf) {
      return id.isNotEmpty;
    }
    return children.any((child) => child.hasRestorablePane);
  }

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
        id: _nonEmptyStringOrNull(json['id']) ?? '',
        direction: _splitDirection(json['direction']),
        first: children.isEmpty ? _emptyLeaf() : children.first,
        second: children.length < 2 ? _emptyLeaf() : children[1],
        ratio: _splitRatioFromJson(json['ratio'], 0.5),
      );
    }

    return TerminalPaneNode.leaf(
      id: _nonEmptyStringOrNull(json['id']) ?? '',
      sessionIntent: TerminalPaneSessionIntent.fromJson(
        _objectMap(json['sessionIntent']) ?? const {},
      ),
    );
  }

  String get firstLeafId {
    if (isLeaf) {
      return id;
    }
    for (final child in children) {
      final leafId = child.firstLeafId;
      if (leafId.isNotEmpty) {
        return leafId;
      }
    }
    return '';
  }

  List<String> get leafPaneIds {
    if (isLeaf) {
      return id.isEmpty ? const <String>[] : <String>[id];
    }
    return [for (final child in children) ...child.leafPaneIds];
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

  TerminalPaneNode growPane(String paneId, double delta) {
    if (isLeaf) {
      return this;
    }

    final first = children.first;
    final second = children.last;
    if (first.containsPane(paneId)) {
      if (!first.isLeaf) {
        return TerminalPaneNode.split(
          id: id,
          direction: direction!,
          first: first.growPane(paneId, delta),
          second: second,
          ratio: ratio,
        );
      }
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first,
        second: second,
        ratio: ratio + delta,
      );
    }
    if (second.containsPane(paneId)) {
      if (!second.isLeaf) {
        return TerminalPaneNode.split(
          id: id,
          direction: direction!,
          first: first,
          second: second.growPane(paneId, delta),
          ratio: ratio,
        );
      }
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first,
        second: second,
        ratio: ratio - delta,
      );
    }

    return this;
  }

  TerminalPaneNode resizeSplitContainingPane(String paneId, double nextRatio) {
    if (isLeaf) {
      return this;
    }

    final first = children.first;
    final second = children.last;
    if (!first.containsPane(paneId) && !second.containsPane(paneId)) {
      return this;
    }
    if (!first.isLeaf && first.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first.resizeSplitContainingPane(paneId, nextRatio),
        second: second,
        ratio: ratio,
      );
    }
    if (!second.isLeaf && second.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first,
        second: second.resizeSplitContainingPane(paneId, nextRatio),
        ratio: ratio,
      );
    }

    return TerminalPaneNode.split(
      id: id,
      direction: direction!,
      first: first,
      second: second,
      ratio: _normalizeSplitRatio(nextRatio, 0.5),
    );
  }

  TerminalPaneNode swapPaneWithSibling(String paneId) {
    if (isLeaf) {
      return this;
    }

    final first = children.first;
    final second = children.last;
    if (!first.containsPane(paneId) && !second.containsPane(paneId)) {
      return this;
    }
    if (!first.isLeaf && first.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first.swapPaneWithSibling(paneId),
        second: second,
        ratio: ratio,
      );
    }
    if (!second.isLeaf && second.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: first,
        second: second.swapPaneWithSibling(paneId),
        ratio: ratio,
      );
    }

    if (first.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: second,
        second: first,
        ratio: 1 - ratio,
      );
    }

    if (second.containsPane(paneId)) {
      return TerminalPaneNode.split(
        id: id,
        direction: direction!,
        first: second,
        second: first,
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

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

String? _nonEmptyStringOrNull(Object? value) {
  final text = _stringOrNull(value)?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _lastNonEmptyTabId(List<TerminalWorkspaceTab> tabs) {
  for (final tab in tabs.reversed) {
    if (tab.id.isNotEmpty) {
      return tab.id;
    }
  }
  return null;
}

double _splitRatioFromJson(Object? value, double fallback) {
  if (value is num) {
    return _normalizeSplitRatio(value.toDouble(), fallback);
  }
  return fallback;
}

double _normalizeSplitRatio(double value, double fallback) {
  if (!value.isFinite) {
    return fallback;
  }
  return value.clamp(0.1, 0.9).toDouble();
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
    final normalized = value.trim().toLowerCase();
    for (final direction in TerminalPaneSplitDirection.values) {
      if (direction.name == normalized) {
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

import 'local_terminal_relaunch_spec.dart';

export 'local_terminal_relaunch_spec.dart';

enum TerminalPaneSplitDirection { right, down }

const int currentTerminalLayoutSchemaVersion = 1;
const String terminalLayoutContract = 'ianvs-terminal-layout-v1';

final class UnsupportedTerminalLayoutSchemaVersion implements Exception {
  const UnsupportedTerminalLayoutSchemaVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal layout schema version: $version '
        '(current: $currentTerminalLayoutSchemaVersion)';
  }
}

const int maxTerminalLayoutClosedTabs = 10;
const int maxTerminalLayoutClosedPanes = 10;
const int _maxTerminalLayoutClosedTabsToScan = maxTerminalLayoutClosedTabs * 4;
const int _maxTerminalLayoutClosedPanesToScan =
    maxTerminalLayoutClosedPanes * 4;
const int _maxTerminalLayoutSplitChildrenToScan = 8;

class TerminalLayout {
  const TerminalLayout({
    this.tabs = const <TerminalLayoutTab>[],
    this.activeTabId,
    this.closedTabs = const <TerminalLayoutTab>[],
  });

  final List<TerminalLayoutTab> tabs;
  final String? activeTabId;
  final List<TerminalLayoutTab> closedTabs;

  int get schemaVersion => currentTerminalLayoutSchemaVersion;

  bool get isEmpty => tabs.isEmpty;

  Map<String, Object?> toJson() {
    final restorableTabs = _uniqueRestorableTabs(tabs);
    final activeTabId = _activeTabFrom(restorableTabs, this.activeTabId)?.id;
    final activeIds = _normalizedIds(restorableTabs.map((tab) => tab.id));
    return {
      'schemaVersion': schemaVersion,
      'contract': terminalLayoutContract,
      'tabs': restorableTabs.map((tab) => tab.toJson()).toList(growable: false),
      'activeTabId': activeTabId?.trim(),
      'closedTabs': _boundedClosedTabs(
        closedTabs,
        excludedIds: activeIds,
      ).map((tab) => tab.toJson()).toList(growable: false),
    };
  }

  static TerminalLayout fromJson(Map<Object?, Object?> json) {
    _validateTerminalLayoutSchemaVersion(json);
    return _fromShape(json, legacy: false);
  }

  /// Reads the former unversioned/Workspace v1-v3 shapes during migration.
  static TerminalLayout fromLegacyWorkspaceJson(Map<Object?, Object?> json) {
    _validateLegacyWorkspaceSchemaVersion(json['schemaVersion']);
    return _fromShape(json, legacy: true);
  }

  static TerminalLayout _fromShape(
    Map<Object?, Object?> json, {
    required bool legacy,
  }) {
    _rejectRemoteWorkspaceKeys(json);

    final tabs = _uniqueRestorableTabs(
      _terminalLayoutTabsFromJson(
        json['tabs'],
        fallbackPrefix: 'tab',
        legacy: legacy,
      ),
    );
    final closedTabs = _boundedClosedTabs(
      _terminalLayoutTabsFromJson(
        json['closedTabs'],
        fallbackPrefix: 'closed-tab',
        maxEntries: _maxTerminalLayoutClosedTabsToScan,
        legacy: legacy,
      ),
      excludedIds: {for (final tab in tabs) tab.id},
    );
    final rawActiveTabId = _nonEmptyStringOrNull(json['activeTabId']);
    final activeTabId =
        rawActiveTabId != null &&
            tabs.any((candidate) => candidate.id == rawActiveTabId)
        ? rawActiveTabId
        : _lastNonEmptyTabId(tabs);

    return TerminalLayout(
      tabs: tabs,
      activeTabId: activeTabId,
      closedTabs: closedTabs,
    );
  }

  TerminalLayoutTab? get activeTab {
    return _activeTabFrom(tabs, activeTabId);
  }

  TerminalLayout addTab(TerminalLayoutTab tab) {
    return TerminalLayout(
      tabs: [...tabs, tab],
      activeTabId: tab.id,
      closedTabs: closedTabs,
    );
  }

  TerminalLayout addTabFromActivePane({
    required String tabId,
    required String paneId,
    required TerminalRelaunchSpec fallbackIntent,
  }) {
    final intent = activeTab?.activeSessionIntent ?? fallbackIntent;
    return addTab(
      TerminalLayoutTab(
        id: tabId,
        activePaneId: paneId,
        root: TerminalPaneNode.leaf(id: paneId, sessionIntent: intent),
      ),
    );
  }

  TerminalLayout splitActivePaneFromActiveCwd({
    required String splitNodeId,
    required String newPaneId,
    required TerminalPaneSplitDirection direction,
    required TerminalRelaunchSpec fallbackIntent,
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

  TerminalLayout closeActiveTab() {
    final tab = activeTab;
    if (tab == null) {
      return this;
    }

    final nextTabs = tabs.where((candidate) => candidate.id != tab.id).toList();
    return TerminalLayout(
      tabs: nextTabs,
      activeTabId: nextTabs.isEmpty ? null : nextTabs.last.id,
      closedTabs: _boundedClosedTabs([tab, ...closedTabs]),
    );
  }

  TerminalLayout reopenClosedTab() {
    if (closedTabs.isEmpty) {
      return this;
    }

    final tab = closedTabs.first;
    return TerminalLayout(
      tabs: [...tabs, tab],
      activeTabId: tab.id,
      closedTabs: closedTabs.skip(1).toList(),
    );
  }

  TerminalLayout updateActiveTab(
    TerminalLayoutTab Function(TerminalLayoutTab tab) update,
  ) {
    final tab = activeTab;
    if (tab == null) {
      return this;
    }

    final updatedTab = update(tab);
    return TerminalLayout(
      tabs: [
        for (final candidate in tabs)
          if (candidate.id == tab.id) updatedTab else candidate,
      ],
      activeTabId: updatedTab.id,
      closedTabs: closedTabs,
    );
  }
}

void _validateTerminalLayoutSchemaVersion(Map<Object?, Object?> json) {
  final value = json['schemaVersion'];
  if (value is! int) {
    throw const FormatException(
      'Terminal layout schemaVersion must be an integer.',
    );
  }
  if (value != currentTerminalLayoutSchemaVersion) {
    throw UnsupportedTerminalLayoutSchemaVersion(value);
  }
  if (json['contract'] != terminalLayoutContract) {
    throw const FormatException('Unsupported terminal layout contract.');
  }
}

void _validateLegacyWorkspaceSchemaVersion(Object? value) {
  if (value == null) {
    return;
  }
  if (value is! int) {
    throw const FormatException(
      'Workspace layout schemaVersion must be an integer.',
    );
  }
  if (value != 1 && value != 2 && value != 3) {
    throw UnsupportedTerminalLayoutSchemaVersion(value);
  }
}

class TerminalLayoutTab {
  const TerminalLayoutTab({
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
  bool get isRestorable => id.trim().isNotEmpty && root.hasRestorablePane;

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
  TerminalRelaunchSpec? get activeSessionIntent {
    return root.findPane(effectiveActivePaneId)?.relaunchSpec;
  }

  TerminalRelaunchSpec? get activeRelaunchSpec {
    return root.findPane(effectiveActivePaneId)?.relaunchSpec;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id.trim(),
      'activePaneId': effectiveActivePaneId.trim(),
      'root': root.toJson(),
      'closedPanes': _boundedClosedPanes(
        closedPanes,
      ).map((pane) => pane.toJson()).toList(growable: false),
      'zoomedPaneId': effectiveZoomedPaneId?.trim(),
    };
  }

  static TerminalLayoutTab fromJson(
    Map<Object?, Object?> json, {
    String? fallbackId,
    bool legacy = false,
  }) {
    final root = TerminalPaneNode.fromJson(
      _objectMap(json['root']) ?? const {},
      legacy: legacy,
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
    final rawId = json['id'];
    final id =
        _nonEmptyStringOrNull(rawId) ??
        (rawId is String ? '' : fallbackId ?? '');
    return TerminalLayoutTab(
      id: id,
      root: root,
      activePaneId: activePaneId,
      closedPanes:
          _objectList(
                json['closedPanes'],
                maxEntries: _maxTerminalLayoutClosedPanesToScan,
              )
              .map((value) => TerminalPaneNode.fromJson(value, legacy: legacy))
              .where((pane) => pane.hasRestorablePane)
              .take(maxTerminalLayoutClosedPanes)
              .toList(growable: false),
      zoomedPaneId: zoomedPaneId,
    );
  }

  TerminalLayoutTab focusPane(String paneId) {
    if (!root.containsPane(paneId)) {
      return this;
    }

    return TerminalLayoutTab(
      id: id,
      root: root,
      activePaneId: paneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalLayoutTab focusRelativePane(int delta) {
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

  TerminalLayoutTab growActivePane(double delta) {
    final targetPaneId = effectiveActivePaneId;
    return TerminalLayoutTab(
      id: id,
      root: root.growPane(targetPaneId, delta),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalLayoutTab resizeActiveSplit(double ratio) {
    final targetPaneId = effectiveActivePaneId;
    return TerminalLayoutTab(
      id: id,
      root: root.resizeSplitContainingPane(targetPaneId, ratio),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalLayoutTab swapActivePaneWithSibling() {
    final targetPaneId = effectiveActivePaneId;
    return TerminalLayoutTab(
      id: id,
      root: root.swapPaneWithSibling(targetPaneId),
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalLayoutTab toggleZoomActivePane() {
    final targetPaneId = effectiveActivePaneId;
    final currentZoomedPaneId = effectiveZoomedPaneId;
    return TerminalLayoutTab(
      id: id,
      root: root,
      activePaneId: targetPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: currentZoomedPaneId == targetPaneId ? null : targetPaneId,
    );
  }

  TerminalLayoutTab splitActivePane({
    required String splitNodeId,
    required String newPaneId,
    required TerminalRelaunchSpec sessionIntent,
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

    return TerminalLayoutTab(
      id: id,
      root: root.replacePane(targetPaneId, replacement),
      activePaneId: newPaneId,
      closedPanes: closedPanes,
      zoomedPaneId: effectiveZoomedPaneId,
    );
  }

  TerminalLayoutTab closeActivePane() {
    final targetPaneId = effectiveActivePaneId;
    final currentZoomedPaneId = effectiveZoomedPaneId;
    if (root.isLeaf) {
      if (targetPaneId == activePaneId) {
        return this;
      }
      return TerminalLayoutTab(
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

    return TerminalLayoutTab(
      id: id,
      root: nextRoot,
      activePaneId: nextRoot.firstLeafId,
      closedPanes: _boundedClosedPanes([?active, ...closedPanes]),
      zoomedPaneId: currentZoomedPaneId == targetPaneId
          ? null
          : currentZoomedPaneId,
    );
  }

  TerminalLayoutTab reopenClosedPane({
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

    return TerminalLayoutTab(
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
    required this.relaunchSpec,
    required this.ratio,
  });

  factory TerminalPaneNode.leaf({
    required String id,
    TerminalRelaunchSpec? relaunchSpec,
    TerminalRelaunchSpec? sessionIntent,
  }) {
    final intent = relaunchSpec ?? sessionIntent;
    if (intent == null) {
      throw ArgumentError.notNull('relaunchSpec');
    }
    return TerminalPaneNode._(
      id: id,
      direction: null,
      children: const <TerminalPaneNode>[],
      relaunchSpec: intent,
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
      relaunchSpec: null,
      ratio: _normalizeSplitRatio(ratio, 0.5),
    );
  }

  final String id;
  final TerminalPaneSplitDirection? direction;
  final List<TerminalPaneNode> children;
  final TerminalRelaunchSpec? relaunchSpec;
  final double ratio;

  TerminalRelaunchSpec? get sessionIntent => relaunchSpec;

  bool get isLeaf => relaunchSpec != null;
  bool get hasRestorablePane {
    if (isLeaf) {
      return id.trim().isNotEmpty;
    }
    return children.any((child) => child.hasRestorablePane);
  }

  Map<String, Object?> toJson() {
    if (isLeaf) {
      return {
        'id': id.trim(),
        'type': 'leaf',
        'relaunchSpec': relaunchSpec!.toJson(),
      };
    }

    return {
      'id': id.trim(),
      'type': 'split',
      'direction': direction!.name,
      'ratio': ratio,
      'children': children
          .map((child) => child.toJson())
          .toList(growable: false),
    };
  }

  static TerminalPaneNode fromJson(
    Map<Object?, Object?> json, {
    bool legacy = false,
  }) {
    if (json['type'] == 'split') {
      final children =
          _objectList(
                json['children'],
                maxEntries: _maxTerminalLayoutSplitChildrenToScan,
              )
              .map((value) => TerminalPaneNode.fromJson(value, legacy: legacy))
              .where((child) => child.hasRestorablePane)
              .toList(growable: false);
      if (children.isEmpty) {
        return _emptyLeaf();
      }
      if (children.length == 1) {
        return children.first;
      }
      return TerminalPaneNode.split(
        id: _nonEmptyStringOrNull(json['id']) ?? '',
        direction: _splitDirection(json['direction']),
        first: children.first,
        second: children[1],
        ratio: _splitRatioFromJson(json['ratio'], 0.5),
      );
    }

    final id = _nonEmptyStringOrNull(json['id']) ?? '';
    final relaunchJson = legacy
        ? _objectMap(json['sessionDescriptor']) ??
              _objectMap(json['sessionIntent']) ??
              const <Object?, Object?>{}
        : _objectMap(json['relaunchSpec']);
    if (relaunchJson == null) {
      throw const FormatException(
        'Terminal layout leaf requires relaunchSpec.',
      );
    }
    return TerminalPaneNode.leaf(
      id: id,
      relaunchSpec: legacy
          ? TerminalRelaunchSpec.fromLegacyJson(relaunchJson)
          : TerminalRelaunchSpec.fromJson(relaunchJson),
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

List<TerminalLayoutTab> _terminalLayoutTabsFromJson(
  Object? value, {
  required String fallbackPrefix,
  int? maxEntries,
  required bool legacy,
}) {
  final tabJson = _objectList(value, maxEntries: maxEntries);
  return [
    for (var index = 0; index < tabJson.length; index += 1)
      TerminalLayoutTab.fromJson(
        tabJson[index],
        fallbackId: '$fallbackPrefix-${index + 1}',
        legacy: legacy,
      ),
  ];
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

String? _lastNonEmptyTabId(List<TerminalLayoutTab> tabs) {
  for (final tab in tabs.reversed) {
    if (tab.id.isNotEmpty) {
      return tab.id;
    }
  }
  return null;
}

TerminalLayoutTab? _activeTabFrom(
  List<TerminalLayoutTab> tabs,
  String? activeTabId,
) {
  final normalizedActiveTabId = activeTabId?.trim();
  if (normalizedActiveTabId != null && normalizedActiveTabId.isNotEmpty) {
    for (final tab in tabs) {
      if (tab.id.trim() == normalizedActiveTabId) {
        return tab;
      }
    }
  }
  return tabs.isEmpty ? null : tabs.last;
}

List<TerminalLayoutTab> _uniqueRestorableTabs(
  Iterable<TerminalLayoutTab> tabs, {
  Set<String> excludedIds = const <String>{},
}) {
  final seenIds = _normalizedIds(excludedIds);
  final unique = <TerminalLayoutTab>[];
  for (final tab in tabs) {
    final id = tab.id.trim();
    if (!tab.isRestorable || !seenIds.add(id)) {
      continue;
    }
    unique.add(tab);
  }
  return unique;
}

List<TerminalLayoutTab> _boundedClosedTabs(
  Iterable<TerminalLayoutTab> tabs, {
  Set<String> excludedIds = const <String>{},
}) {
  final seenIds = _normalizedIds(excludedIds);
  final bounded = <TerminalLayoutTab>[];
  for (final tab in tabs) {
    final id = tab.id.trim();
    if (!tab.isRestorable || !seenIds.add(id)) {
      continue;
    }
    bounded.add(tab);
    if (bounded.length == maxTerminalLayoutClosedTabs) {
      break;
    }
  }
  return bounded;
}

Set<String> _normalizedIds(Iterable<String> ids) {
  return {
    for (final id in ids)
      if (id.trim().isNotEmpty) id.trim(),
  };
}

List<TerminalPaneNode> _boundedClosedPanes(Iterable<TerminalPaneNode> panes) {
  final bounded = <TerminalPaneNode>[];
  for (final pane in panes) {
    if (!pane.hasRestorablePane) {
      continue;
    }
    bounded.add(pane);
    if (bounded.length >= maxTerminalLayoutClosedPanes) {
      break;
    }
  }
  return bounded;
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

List<Map<Object?, Object?>> _objectList(Object? value, {int? maxEntries}) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }

  final entries = maxEntries == null ? value : value.take(maxEntries);
  return entries
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
    sessionIntent: const TerminalRelaunchSpec(profileId: ''),
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
    'Terminal layout does not accept remote-only fields: '
    '${matches.join(', ')}',
  );
}

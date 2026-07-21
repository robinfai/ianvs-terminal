import 'local_session_descriptor.dart';
import 'local_workspace_identity.dart';

export 'local_session_descriptor.dart';
export 'local_workspace_identity.dart';

enum TerminalPaneSplitDirection { right, down }

const int currentTerminalWorkspaceSchemaVersion = 3;

final class UnsupportedTerminalWorkspaceSchemaVersion implements Exception {
  const UnsupportedTerminalWorkspaceSchemaVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal workspace schema version: $version '
        '(current: $currentTerminalWorkspaceSchemaVersion)';
  }
}

const int maxWorkspaceClosedTabs = 10;
const int maxWorkspaceClosedPanes = 10;
const int _maxWorkspaceClosedTabsToScan = maxWorkspaceClosedTabs * 4;
const int _maxWorkspaceClosedPanesToScan = maxWorkspaceClosedPanes * 4;
const int _maxWorkspaceSplitChildrenToScan = 8;

@Deprecated('Use TerminalSessionDescriptor for versioned persistence.')
class TerminalPaneSessionIntent extends TerminalSessionDescriptor {
  const TerminalPaneSessionIntent({required super.profileId, super.cwd});
}

class TerminalWorkspace {
  const TerminalWorkspace({
    this.identity = TerminalWorkspaceIdentity.defaultWorkspace,
    this.tabs = const <TerminalWorkspaceTab>[],
    this.activeTabId,
    this.closedTabs = const <TerminalWorkspaceTab>[],
  });

  final TerminalWorkspaceIdentity identity;
  final List<TerminalWorkspaceTab> tabs;
  final String? activeTabId;
  final List<TerminalWorkspaceTab> closedTabs;

  int get schemaVersion => currentTerminalWorkspaceSchemaVersion;

  bool get isEmpty => tabs.isEmpty;

  Map<String, Object?> toJson() {
    final identity = this.identity.normalized();
    final restorableTabs = _uniqueRestorableTabs(tabs);
    final activeTabId = _activeTabFrom(restorableTabs, this.activeTabId)?.id;
    final activeIds = _normalizedIds(restorableTabs.map((tab) => tab.id));
    return {
      'schemaVersion': schemaVersion,
      'id': identity.id,
      'name': identity.name,
      'projectPath': identity.projectPath,
      'tabs': restorableTabs.map((tab) => tab.toJson()).toList(growable: false),
      'activeTabId': activeTabId?.trim(),
      'closedTabs': _boundedClosedTabs(
        closedTabs,
        excludedIds: activeIds,
      ).map((tab) => tab.toJson()).toList(growable: false),
    };
  }

  static TerminalWorkspace fromJson(Map<Object?, Object?> json) {
    final schemaVersion = _validateTerminalWorkspaceSchemaVersion(
      json['schemaVersion'],
    );
    _rejectRemoteWorkspaceKeys(json);

    final tabs = _uniqueRestorableTabs(
      _workspaceTabsFromJson(json['tabs'], fallbackPrefix: 'tab'),
    );
    final closedTabs = _boundedClosedTabs(
      _workspaceTabsFromJson(
        json['closedTabs'],
        fallbackPrefix: 'closed-tab',
        maxEntries: _maxWorkspaceClosedTabsToScan,
      ),
      excludedIds: {for (final tab in tabs) tab.id},
    );
    final rawActiveTabId = _nonEmptyStringOrNull(json['activeTabId']);
    final activeTabId =
        rawActiveTabId != null &&
            tabs.any((candidate) => candidate.id == rawActiveTabId)
        ? rawActiveTabId
        : _lastNonEmptyTabId(tabs);

    return TerminalWorkspace(
      identity: schemaVersion == currentTerminalWorkspaceSchemaVersion
          ? _terminalWorkspaceIdentityFromJson(json)
          : TerminalWorkspaceIdentity.defaultWorkspace,
      tabs: tabs,
      activeTabId: activeTabId,
      closedTabs: closedTabs,
    );
  }

  TerminalWorkspaceTab? get activeTab {
    return _activeTabFrom(tabs, activeTabId);
  }

  TerminalWorkspace addTab(TerminalWorkspaceTab tab) {
    return TerminalWorkspace(
      identity: identity,
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
      identity: identity,
      tabs: nextTabs,
      activeTabId: nextTabs.isEmpty ? null : nextTabs.last.id,
      closedTabs: _boundedClosedTabs([tab, ...closedTabs]),
    );
  }

  TerminalWorkspace reopenClosedTab() {
    if (closedTabs.isEmpty) {
      return this;
    }

    final tab = closedTabs.first;
    return TerminalWorkspace(
      identity: identity,
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
      identity: identity,
      tabs: [
        for (final candidate in tabs)
          if (candidate.id == tab.id) updatedTab else candidate,
      ],
      activeTabId: updatedTab.id,
      closedTabs: closedTabs,
    );
  }

  TerminalWorkspace withIdentity(TerminalWorkspaceIdentity identity) {
    return TerminalWorkspace(
      identity: identity.normalized(),
      tabs: tabs,
      activeTabId: activeTabId,
      closedTabs: closedTabs,
    );
  }
}

TerminalWorkspaceIdentity _terminalWorkspaceIdentityFromJson(
  Map<Object?, Object?> json,
) {
  final id = _nonEmptyStringOrNull(json['id']);
  final name = _nonEmptyStringOrNull(json['name']);
  if (id == null || name == null) {
    throw const FormatException(
      'Workspace schema v3 requires non-empty id and name fields.',
    );
  }
  return TerminalWorkspaceIdentity(
    id: id,
    name: name,
    projectPath: normalizeTerminalWorkspaceProjectPath(json['projectPath']),
  ).normalized();
}

int? _validateTerminalWorkspaceSchemaVersion(Object? value) {
  if (value == null) {
    // Layouts written before v1 were unversioned and have the same field shape.
    return null;
  }
  if (value is! int) {
    throw const FormatException(
      'Workspace layout schemaVersion must be an integer.',
    );
  }
  if (value != 1 &&
      value != 2 &&
      value != currentTerminalWorkspaceSchemaVersion) {
    throw UnsupportedTerminalWorkspaceSchemaVersion(value);
  }
  return value;
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
  TerminalSessionDescriptor? get activeSessionIntent {
    return root.findPane(effectiveActivePaneId)?.sessionIntent;
  }

  TerminalSessionDescriptor? get activeSessionDescriptor {
    return root.findPane(effectiveActivePaneId)?.sessionDescriptor;
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

  static TerminalWorkspaceTab fromJson(
    Map<Object?, Object?> json, {
    String? fallbackId,
  }) {
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
    final rawId = json['id'];
    final id =
        _nonEmptyStringOrNull(rawId) ??
        (rawId is String ? '' : fallbackId ?? '');
    return TerminalWorkspaceTab(
      id: id,
      root: root,
      activePaneId: activePaneId,
      closedPanes:
          _objectList(
                json['closedPanes'],
                maxEntries: _maxWorkspaceClosedPanesToScan,
              )
              .map(TerminalPaneNode.fromJson)
              .where((pane) => pane.hasRestorablePane)
              .take(maxWorkspaceClosedPanes)
              .toList(growable: false),
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
    required TerminalSessionDescriptor sessionIntent,
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
      closedPanes: _boundedClosedPanes([?active, ...closedPanes]),
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
    required this.sessionDescriptor,
    required this.ratio,
  });

  factory TerminalPaneNode.leaf({
    required String id,
    TerminalSessionDescriptor? sessionDescriptor,
    TerminalSessionDescriptor? sessionIntent,
  }) {
    final descriptor = sessionDescriptor ?? sessionIntent;
    if (descriptor == null) {
      throw ArgumentError.notNull('sessionDescriptor');
    }
    final normalizedDescriptor = descriptor.id.trim().isEmpty
        ? descriptor.copyWith(id: id)
        : descriptor;
    return TerminalPaneNode._(
      id: id,
      direction: null,
      children: const <TerminalPaneNode>[],
      sessionDescriptor: normalizedDescriptor,
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
      sessionDescriptor: null,
      ratio: _normalizeSplitRatio(ratio, 0.5),
    );
  }

  final String id;
  final TerminalPaneSplitDirection? direction;
  final List<TerminalPaneNode> children;
  final TerminalSessionDescriptor? sessionDescriptor;
  final double ratio;

  @Deprecated('Use sessionDescriptor.')
  TerminalSessionDescriptor? get sessionIntent => sessionDescriptor;

  bool get isLeaf => sessionDescriptor != null;
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
        'sessionDescriptor': sessionDescriptor!.toJson(fallbackId: id),
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

  static TerminalPaneNode fromJson(Map<Object?, Object?> json) {
    if (json['type'] == 'split') {
      final children =
          _objectList(
                json['children'],
                maxEntries: _maxWorkspaceSplitChildrenToScan,
              )
              .map(TerminalPaneNode.fromJson)
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
    final descriptorJson = _objectMap(json['sessionDescriptor']);
    return TerminalPaneNode.leaf(
      id: id,
      sessionDescriptor: descriptorJson == null
          ? TerminalSessionDescriptor.fromLegacyIntent(
              _objectMap(json['sessionIntent']) ?? const {},
              fallbackId: id,
            )
          : TerminalSessionDescriptor.fromJson(descriptorJson),
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

List<TerminalWorkspaceTab> _workspaceTabsFromJson(
  Object? value, {
  required String fallbackPrefix,
  int? maxEntries,
}) {
  final tabJson = _objectList(value, maxEntries: maxEntries);
  return [
    for (var index = 0; index < tabJson.length; index += 1)
      TerminalWorkspaceTab.fromJson(
        tabJson[index],
        fallbackId: '$fallbackPrefix-${index + 1}',
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

String? _lastNonEmptyTabId(List<TerminalWorkspaceTab> tabs) {
  for (final tab in tabs.reversed) {
    if (tab.id.isNotEmpty) {
      return tab.id;
    }
  }
  return null;
}

TerminalWorkspaceTab? _activeTabFrom(
  List<TerminalWorkspaceTab> tabs,
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

List<TerminalWorkspaceTab> _uniqueRestorableTabs(
  Iterable<TerminalWorkspaceTab> tabs, {
  Set<String> excludedIds = const <String>{},
}) {
  final seenIds = _normalizedIds(excludedIds);
  final unique = <TerminalWorkspaceTab>[];
  for (final tab in tabs) {
    final id = tab.id.trim();
    if (!tab.isRestorable || !seenIds.add(id)) {
      continue;
    }
    unique.add(tab);
  }
  return unique;
}

List<TerminalWorkspaceTab> _boundedClosedTabs(
  Iterable<TerminalWorkspaceTab> tabs, {
  Set<String> excludedIds = const <String>{},
}) {
  final seenIds = _normalizedIds(excludedIds);
  final bounded = <TerminalWorkspaceTab>[];
  for (final tab in tabs) {
    final id = tab.id.trim();
    if (!tab.isRestorable || !seenIds.add(id)) {
      continue;
    }
    bounded.add(tab);
    if (bounded.length == maxWorkspaceClosedTabs) {
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
    if (bounded.length >= maxWorkspaceClosedPanes) {
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

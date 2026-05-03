import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'platform_paths.dart';
import 'session_launch.dart';
import 'session_metadata.dart';
import 'terminal_blocks.dart';
import 'terminal_panes.dart';

class TerminalSessionRestoreState {
  const TerminalSessionRestoreState({
    this.version = 3,
    this.activeWindowIndex = 0,
    this.windows = const <TerminalSessionRestoreWindow>[],
  });

  factory TerminalSessionRestoreState.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalSessionRestoreState();
    }
    final windows = _restoreWindowsFromJson(map);
    if (windows.isEmpty) {
      return const TerminalSessionRestoreState();
    }
    return TerminalSessionRestoreState(
      version: _positiveIntOrDefault(map['version'], 3),
      activeWindowIndex: _intInRange(
        map['activeWindowIndex'],
        0,
        windows.length - 1,
      ),
      windows: windows,
    ).withUniquePaneIds();
  }

  final int version;
  final int activeWindowIndex;
  final List<TerminalSessionRestoreWindow> windows;

  bool get hasWindows => windows.isNotEmpty;
  bool get hasTabs => tabs.isNotEmpty;

  TerminalSessionRestoreWindow? get activeWindow {
    if (windows.isEmpty) {
      return null;
    }
    return windows[activeWindowIndex.clamp(0, windows.length - 1)];
  }

  int get activeTabIndex => activeWindow?.activeTabIndex ?? 0;
  List<TerminalSessionRestoreTab> get tabs =>
      activeWindow?.tabs ?? const <TerminalSessionRestoreTab>[];

  TerminalSessionRestoreState withUniquePaneIds() {
    if (windows.isEmpty) {
      return this;
    }
    final usedPaneIds = <int>{};
    final maxPaneId = windows
        .expand((window) => window.tabs)
        .expand((tab) => tab.rootPane.leaves)
        .fold<int>(0, (max, leaf) => leaf.id > max ? leaf.id : max);
    var nextPaneId = maxPaneId + 1;
    var changed = false;
    final uniqueWindows = <TerminalSessionRestoreWindow>[];

    for (final window in windows) {
      final uniqueTabs = <TerminalSessionRestoreTab>[];
      var windowChanged = false;
      for (final tab in window.tabs) {
        final remappedIds = <int, int>{};
        final acceptedOriginalIds = <int>{};
        final uniqueRootPane = _paneNodeWithUniqueIds(
          tab.rootPane,
          usedPaneIds,
          acceptedOriginalIds,
          remappedIds,
          () => nextPaneId++,
        );
        windowChanged =
            windowChanged || !identical(uniqueRootPane, tab.rootPane);
        uniqueTabs.add(
          TerminalSessionRestoreTab(
            fallbackTitle: tab.fallbackTitle,
            activePaneId: remappedIds[tab.activePaneId] ?? tab.activePaneId,
            rootPane: uniqueRootPane,
          ),
        );
      }
      changed = changed || windowChanged;
      uniqueWindows.add(
        TerminalSessionRestoreWindow(
          fallbackTitle: window.fallbackTitle,
          activeTabIndex: window.activeTabIndex,
          tabs: uniqueTabs,
        ),
      );
    }

    if (!changed) {
      return this;
    }
    return TerminalSessionRestoreState(
      version: version,
      activeWindowIndex: activeWindowIndex,
      windows: uniqueWindows,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'version': version,
      'activeWindowIndex': activeWindowIndex,
      'windows': windows
          .map((window) => window.toJson())
          .toList(growable: false),
    };
    if (windows.length == 1) {
      final window = windows.single;
      json['activeTabIndex'] = window.activeTabIndex;
      json['tabs'] = window.tabs
          .map((tab) => tab.toJson())
          .toList(growable: false);
    }
    return json;
  }
}

class TerminalSessionRestoreWindow {
  const TerminalSessionRestoreWindow({
    required this.fallbackTitle,
    this.activeTabIndex = 0,
    this.tabs = const <TerminalSessionRestoreTab>[],
  });

  static TerminalSessionRestoreWindow? fromJson(Object? json, int index) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    final rawTabs = map['tabs'];
    if (rawTabs is! List || rawTabs.isEmpty) {
      return null;
    }
    final tabs = <TerminalSessionRestoreTab>[];
    for (var tabIndex = 0; tabIndex < rawTabs.length; tabIndex += 1) {
      final tab = TerminalSessionRestoreTab.fromJson(
        rawTabs[tabIndex],
        tabIndex,
      );
      if (tab != null) {
        tabs.add(tab);
      }
    }
    if (tabs.isEmpty) {
      return null;
    }
    return TerminalSessionRestoreWindow(
      fallbackTitle: _stringOrDefault(
        map['fallbackTitle'],
        'Window ${index + 1}',
      ),
      activeTabIndex: _intInRange(map['activeTabIndex'], 0, tabs.length - 1),
      tabs: tabs,
    );
  }

  final String fallbackTitle;
  final int activeTabIndex;
  final List<TerminalSessionRestoreTab> tabs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fallbackTitle': fallbackTitle,
      'activeTabIndex': activeTabIndex,
      'tabs': tabs.map((tab) => tab.toJson()).toList(growable: false),
    };
  }
}

class TerminalSessionRestoreTab {
  const TerminalSessionRestoreTab({
    required this.fallbackTitle,
    required this.activePaneId,
    required this.rootPane,
  });

  static TerminalSessionRestoreTab? fromJson(Object? json, int index) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    final rootPane = TerminalSessionRestorePaneNode.fromJson(map['rootPane']);
    if (rootPane == null) {
      return null;
    }
    final leaves = rootPane.leaves;
    final requestedActivePaneId = _intOrNull(map['activePaneId']);
    final activePaneId =
        requestedActivePaneId != null &&
            leaves.any((leaf) => leaf.id == requestedActivePaneId)
        ? requestedActivePaneId
        : leaves.first.id;
    return TerminalSessionRestoreTab(
      fallbackTitle: _stringOrDefault(
        map['fallbackTitle'],
        'Local ${index + 1}',
      ),
      activePaneId: activePaneId,
      rootPane: rootPane,
    );
  }

  final String fallbackTitle;
  final int activePaneId;
  final TerminalSessionRestorePaneNode rootPane;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fallbackTitle': fallbackTitle,
      'activePaneId': activePaneId,
      'rootPane': rootPane.toJson(),
    };
  }
}

abstract class TerminalSessionRestorePaneNode {
  const TerminalSessionRestorePaneNode();

  static TerminalSessionRestorePaneNode? fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    return switch (map['type']) {
      'leaf' => TerminalSessionRestorePaneLeaf.fromJson(map),
      'split' => TerminalSessionRestorePaneSplit.fromJson(map),
      _ => null,
    };
  }

  List<TerminalSessionRestorePaneLeaf> get leaves;
  Map<String, Object?> toJson();
}

class TerminalSessionRestorePaneLeaf extends TerminalSessionRestorePaneNode {
  const TerminalSessionRestorePaneLeaf({
    required this.id,
    required this.cwd,
    this.blocks = const <TerminalBlock>[],
    this.sessionMetadata = const TerminalSessionMetadata(),
    this.launchProfile = const TerminalSessionLaunchProfile.localShell(),
  });

  factory TerminalSessionRestorePaneLeaf.fromJson(Map<String, Object?> map) {
    final paneId = _positiveIntOrDefault(map['id'], 1);
    return TerminalSessionRestorePaneLeaf(
      id: paneId,
      cwd: _stringOrDefault(map['cwd'], ''),
      blocks: _restoreBlocksFromJson(map['blocks'], paneId: paneId),
      sessionMetadata: TerminalSessionMetadata.fromJson(map['sessionMetadata']),
      launchProfile: TerminalSessionLaunchProfile.fromJson(
        map['launchProfile'],
      ),
    );
  }

  final int id;
  final String cwd;
  final List<TerminalBlock> blocks;
  final TerminalSessionMetadata sessionMetadata;
  final TerminalSessionLaunchProfile launchProfile;

  @override
  List<TerminalSessionRestorePaneLeaf> get leaves =>
      <TerminalSessionRestorePaneLeaf>[this];

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'leaf',
      'id': id,
      'cwd': cwd,
      if (blocks.isNotEmpty)
        'blocks': blocks
            .map((block) => _restoreBlockToJson(block))
            .toList(growable: false),
      if (!sessionMetadata.isDefaultLocal)
        'sessionMetadata': sessionMetadata.toJson(),
      if (!launchProfile.isDefaultLocal)
        'launchProfile': launchProfile.toJson(),
    };
  }
}

class TerminalSessionRestorePaneSplit extends TerminalSessionRestorePaneNode {
  TerminalSessionRestorePaneSplit({
    required this.direction,
    required this.first,
    required this.second,
    double ratio = 0.5,
  }) : ratio = _validRatioOrDefault(ratio);

  static TerminalSessionRestorePaneSplit? fromJson(Map<String, Object?> map) {
    final first = TerminalSessionRestorePaneNode.fromJson(map['first']);
    final second = TerminalSessionRestorePaneNode.fromJson(map['second']);
    if (first == null || second == null) {
      return null;
    }
    return TerminalSessionRestorePaneSplit(
      direction: _directionFromJson(map['direction']),
      ratio: _ratioFromJson(map['ratio']),
      first: first,
      second: second,
    );
  }

  final TerminalPaneSplitDirection direction;
  final TerminalSessionRestorePaneNode first;
  final TerminalSessionRestorePaneNode second;
  final double ratio;

  @override
  List<TerminalSessionRestorePaneLeaf> get leaves =>
      <TerminalSessionRestorePaneLeaf>[...first.leaves, ...second.leaves];

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'split',
      'direction': direction.name,
      'ratio': ratio,
      'first': first.toJson(),
      'second': second.toJson(),
    };
  }
}

List<TerminalSessionRestoreWindow> _restoreWindowsFromJson(
  Map<String, Object?> map,
) {
  final rawWindows = map['windows'];
  if (rawWindows is List && rawWindows.isNotEmpty) {
    final windows = <TerminalSessionRestoreWindow>[];
    for (var index = 0; index < rawWindows.length; index += 1) {
      final window = TerminalSessionRestoreWindow.fromJson(
        rawWindows[index],
        index,
      );
      if (window != null) {
        windows.add(window);
      }
    }
    return windows;
  }

  final rawTabs = map['tabs'];
  if (rawTabs is! List || rawTabs.isEmpty) {
    return const <TerminalSessionRestoreWindow>[];
  }
  final legacyWindow = TerminalSessionRestoreWindow.fromJson(<String, Object?>{
    'fallbackTitle': map['fallbackTitle'] ?? 'Window 1',
    'activeTabIndex': map['activeTabIndex'],
    'tabs': rawTabs,
  }, 0);
  if (legacyWindow == null) {
    return const <TerminalSessionRestoreWindow>[];
  }
  return <TerminalSessionRestoreWindow>[legacyWindow];
}

class TerminalSessionRestoreStore {
  TerminalSessionRestoreStore({File? file})
    : file = file ?? defaultSessionRestoreFile(),
      _memoryState = null;

  TerminalSessionRestoreStore.memory([TerminalSessionRestoreState? state])
    : file = null,
      _memoryState = state ?? const TerminalSessionRestoreState();

  final File? file;
  TerminalSessionRestoreState? _memoryState;
  int saveCount = 0;

  static File defaultSessionRestoreFile() {
    return File(defaultSessionRestoreFilePath());
  }

  TerminalSessionRestoreState load() {
    final memoryState = _memoryState;
    if (memoryState != null) {
      return memoryState;
    }
    final target = file;
    if (target == null || !target.existsSync()) {
      return const TerminalSessionRestoreState();
    }
    try {
      return TerminalSessionRestoreState.fromJson(
        jsonDecode(target.readAsStringSync()),
      );
    } catch (_) {
      return const TerminalSessionRestoreState();
    }
  }

  void save(TerminalSessionRestoreState state) {
    saveCount += 1;
    if (_memoryState != null) {
      _memoryState = state;
      return;
    }
    final target = file;
    if (target == null) {
      return;
    }
    target.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    target.writeAsStringSync('${encoder.convert(state.toJson())}\n');
  }
}

class TerminalSessionRestoreController {
  TerminalSessionRestoreController({
    required this.store,
    this.debounceDuration = const Duration(milliseconds: 250),
  });

  final TerminalSessionRestoreStore store;
  final Duration debounceDuration;
  Timer? _saveTimer;
  TerminalSessionRestoreState? _pendingState;

  TerminalSessionRestoreState load() => store.load().withUniquePaneIds();

  void saveNow(TerminalSessionRestoreState state) {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingState = null;
    store.save(state);
  }

  void scheduleSave(TerminalSessionRestoreState state) {
    if (debounceDuration == Duration.zero) {
      saveNow(state);
      return;
    }
    _pendingState = state;
    _saveTimer?.cancel();
    _saveTimer = Timer(debounceDuration, flush);
  }

  void flush() {
    final pendingState = _pendingState;
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingState = null;
    if (pendingState != null) {
      store.save(pendingState);
    }
  }

  void dispose() {
    flush();
  }
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

String _stringOrDefault(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String _stringValueOrDefault(Object? value, String fallback) {
  if (value is String) {
    return value;
  }
  return fallback;
}

String? _stringOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int _positiveIntOrDefault(Object? value, int fallback) {
  final candidate = _intOrNull(value);
  if (candidate == null || candidate <= 0) {
    return fallback;
  }
  return candidate;
}

int _nonNegativeIntOrDefault(Object? value, int fallback) {
  final candidate = _intOrNull(value);
  if (candidate == null || candidate < 0) {
    return fallback;
  }
  return candidate;
}

int _intInRange(Object? value, int min, int max) {
  final candidate = _intOrNull(value);
  if (candidate == null) {
    return min;
  }
  return candidate.clamp(min, max).toInt();
}

TerminalPaneSplitDirection _directionFromJson(Object? value) {
  return switch (value) {
    'down' => TerminalPaneSplitDirection.down,
    _ => TerminalPaneSplitDirection.right,
  };
}

double _ratioFromJson(Object? value) {
  if (value is num) {
    return _validRatioOrDefault(value.toDouble());
  }
  return 0.5;
}

TerminalBlockStatus _blockStatusFromJson(Object? value) {
  return switch (value) {
    'succeeded' => TerminalBlockStatus.succeeded,
    'failed' => TerminalBlockStatus.failed,
    'interrupted' => TerminalBlockStatus.interrupted,
    'unknown' => TerminalBlockStatus.unknown,
    _ => TerminalBlockStatus.running,
  };
}

List<TerminalBlock> _restoreBlocksFromJson(
  Object? value, {
  required int paneId,
}) {
  if (value is! List) {
    return const <TerminalBlock>[];
  }
  final blocks = <TerminalBlock>[];
  for (var index = 0; index < value.length; index += 1) {
    final map = _objectMap(value[index]);
    if (map == null) {
      continue;
    }
    blocks.add(
      TerminalBlock(
        id: _stringOrDefault(map['id'], 'pane-$paneId-block-${index + 1}'),
        sessionId: _stringOrDefault(map['sessionId'], 'restored-pane-$paneId'),
        commandText: _stringValueOrDefault(map['commandText'], ''),
        outputText: _stringValueOrDefault(map['outputText'], ''),
        status: _blockStatusFromJson(map['status']),
        scrollbackOffset: _nonNegativeIntOrDefault(map['scrollbackOffset'], 0),
        recordedAt: _stringOrNull(map['recordedAt']),
        targetEnvironment: _stringOrNull(map['targetEnvironment']),
      ),
    );
  }
  return blocks;
}

Map<String, Object?> _restoreBlockToJson(TerminalBlock block) {
  return <String, Object?>{
    'id': block.id,
    'sessionId': block.sessionId,
    'commandText': block.commandText,
    'outputText': block.outputText,
    'status': block.status.name,
    'scrollbackOffset': block.scrollbackOffset,
    if (block.recordedAt != null) 'recordedAt': block.recordedAt,
    if (block.targetEnvironment != null)
      'targetEnvironment': block.targetEnvironment,
  };
}

TerminalSessionRestorePaneNode _paneNodeWithUniqueIds(
  TerminalSessionRestorePaneNode node,
  Set<int> usedPaneIds,
  Set<int> acceptedOriginalIds,
  Map<int, int> remappedIds,
  int Function() allocatePaneId,
) {
  if (node is TerminalSessionRestorePaneLeaf) {
    if (usedPaneIds.add(node.id)) {
      acceptedOriginalIds.add(node.id);
      return node;
    }
    final nextId = allocatePaneId();
    usedPaneIds.add(nextId);
    if (!acceptedOriginalIds.contains(node.id)) {
      remappedIds[node.id] = nextId;
    }
    return TerminalSessionRestorePaneLeaf(
      id: nextId,
      cwd: node.cwd,
      blocks: node.blocks,
      sessionMetadata: node.sessionMetadata,
      launchProfile: node.launchProfile,
    );
  }

  final split = node as TerminalSessionRestorePaneSplit;
  final first = _paneNodeWithUniqueIds(
    split.first,
    usedPaneIds,
    acceptedOriginalIds,
    remappedIds,
    allocatePaneId,
  );
  final second = _paneNodeWithUniqueIds(
    split.second,
    usedPaneIds,
    acceptedOriginalIds,
    remappedIds,
    allocatePaneId,
  );
  if (identical(first, split.first) && identical(second, split.second)) {
    return split;
  }
  return TerminalSessionRestorePaneSplit(
    direction: split.direction,
    ratio: split.ratio,
    first: first,
    second: second,
  );
}

String defaultSessionRestoreFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  return defaultTerminalSessionRestoreFilePath(
    environment: environment,
    operatingSystem: operatingSystem,
    currentPath: currentPath,
  );
}

double _validRatioOrDefault(double value) {
  if (value >= TerminalPaneSplit.minRatio &&
      value <= TerminalPaneSplit.maxRatio) {
    return value;
  }
  return 0.5;
}

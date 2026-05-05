import 'dart:convert';
import 'dart:io';

import 'platform_paths.dart';
import 'session_launch.dart';
import 'session_metadata.dart';
import 'terminal_panes.dart';

enum TerminalLaunchConfigurationScope {
  app,
  tab;

  static TerminalLaunchConfigurationScope fromJson(Object? value) {
    return switch (value) {
      'tab' => TerminalLaunchConfigurationScope.tab,
      _ => TerminalLaunchConfigurationScope.app,
    };
  }
}

class TerminalLaunchConfiguration {
  const TerminalLaunchConfiguration({
    this.version = 2,
    this.scope = TerminalLaunchConfigurationScope.app,
    this.activeWindowIndex = 0,
    this.windows = const <TerminalLaunchConfigurationWindow>[],
  });

  factory TerminalLaunchConfiguration.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalLaunchConfiguration();
    }
    final windows = _windowsFromJson(map);
    if (windows.isEmpty) {
      return const TerminalLaunchConfiguration();
    }
    return TerminalLaunchConfiguration(
      version: _positiveIntOrDefault(map['version'], 2),
      scope: TerminalLaunchConfigurationScope.fromJson(map['scope']),
      activeWindowIndex: _intInRange(
        map['activeWindowIndex'],
        0,
        windows.length - 1,
      ),
      windows: windows,
    ).withUniquePaneIds();
  }

  final int version;
  final TerminalLaunchConfigurationScope scope;
  final int activeWindowIndex;
  final List<TerminalLaunchConfigurationWindow> windows;

  bool get hasWindows => windows.isNotEmpty;
  bool get hasTabs => tabs.isNotEmpty;

  TerminalLaunchConfigurationWindow? get activeWindow {
    if (windows.isEmpty) {
      return null;
    }
    return windows[activeWindowIndex.clamp(0, windows.length - 1)];
  }

  int get activeTabIndex => activeWindow?.activeTabIndex ?? 0;
  List<TerminalLaunchConfigurationTab> get tabs =>
      activeWindow?.tabs ?? const <TerminalLaunchConfigurationTab>[];

  TerminalLaunchConfiguration withUniquePaneIds() {
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
    final uniqueWindows = <TerminalLaunchConfigurationWindow>[];

    for (final window in windows) {
      final uniqueTabs = <TerminalLaunchConfigurationTab>[];
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
          TerminalLaunchConfigurationTab(
            fallbackTitle: tab.fallbackTitle,
            activePaneId: remappedIds[tab.activePaneId] ?? tab.activePaneId,
            rootPane: uniqueRootPane,
          ),
        );
      }
      changed = changed || windowChanged;
      uniqueWindows.add(
        TerminalLaunchConfigurationWindow(
          fallbackTitle: window.fallbackTitle,
          activeTabIndex: window.activeTabIndex,
          tabs: uniqueTabs,
        ),
      );
    }

    if (!changed) {
      return this;
    }
    return TerminalLaunchConfiguration(
      version: version,
      scope: scope,
      activeWindowIndex: activeWindowIndex,
      windows: uniqueWindows,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'version': version,
      'scope': scope.name,
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

class TerminalLaunchConfigurationWindow {
  const TerminalLaunchConfigurationWindow({
    required this.fallbackTitle,
    this.activeTabIndex = 0,
    this.tabs = const <TerminalLaunchConfigurationTab>[],
  });

  static TerminalLaunchConfigurationWindow? fromJson(Object? json, int index) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    final rawTabs = map['tabs'];
    if (rawTabs is! List || rawTabs.isEmpty) {
      return null;
    }
    final tabs = <TerminalLaunchConfigurationTab>[];
    for (var tabIndex = 0; tabIndex < rawTabs.length; tabIndex += 1) {
      final tab = TerminalLaunchConfigurationTab.fromJson(
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
    return TerminalLaunchConfigurationWindow(
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
  final List<TerminalLaunchConfigurationTab> tabs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fallbackTitle': fallbackTitle,
      'activeTabIndex': activeTabIndex,
      'tabs': tabs.map((tab) => tab.toJson()).toList(growable: false),
    };
  }
}

class TerminalLaunchConfigurationTab {
  const TerminalLaunchConfigurationTab({
    required this.fallbackTitle,
    required this.activePaneId,
    required this.rootPane,
  });

  static TerminalLaunchConfigurationTab? fromJson(Object? json, int index) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    final rootPane = TerminalLaunchConfigurationPaneNode.fromJson(
      map['rootPane'],
    );
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
    return TerminalLaunchConfigurationTab(
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
  final TerminalLaunchConfigurationPaneNode rootPane;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fallbackTitle': fallbackTitle,
      'activePaneId': activePaneId,
      'rootPane': rootPane.toJson(),
    };
  }
}

abstract class TerminalLaunchConfigurationPaneNode {
  const TerminalLaunchConfigurationPaneNode();

  static TerminalLaunchConfigurationPaneNode? fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return null;
    }
    return switch (map['type']) {
      'leaf' => TerminalLaunchConfigurationPaneLeaf.fromJson(map),
      'split' => TerminalLaunchConfigurationPaneSplit.fromJson(map),
      _ => null,
    };
  }

  List<TerminalLaunchConfigurationPaneLeaf> get leaves;
  Map<String, Object?> toJson();
}

class TerminalLaunchConfigurationPaneLeaf
    extends TerminalLaunchConfigurationPaneNode {
  const TerminalLaunchConfigurationPaneLeaf({
    required this.id,
    required this.cwd,
    this.startupCommand = '',
    this.sessionMetadata = const TerminalSessionMetadata(),
    this.launchProfile = const TerminalSessionLaunchProfile.localShell(),
  });

  factory TerminalLaunchConfigurationPaneLeaf.fromJson(
    Map<String, Object?> map,
  ) {
    return TerminalLaunchConfigurationPaneLeaf(
      id: _positiveIntOrDefault(map['id'], 1),
      cwd: _stringOrDefault(map['cwd'], ''),
      startupCommand: _stringOrDefault(map['startupCommand'], ''),
      sessionMetadata: TerminalSessionMetadata.fromJson(map['sessionMetadata']),
      launchProfile: TerminalSessionLaunchProfile.fromJson(
        map['launchProfile'],
      ),
    );
  }

  final int id;
  final String cwd;
  final String startupCommand;
  final TerminalSessionMetadata sessionMetadata;
  final TerminalSessionLaunchProfile launchProfile;

  @override
  List<TerminalLaunchConfigurationPaneLeaf> get leaves =>
      <TerminalLaunchConfigurationPaneLeaf>[this];

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'leaf',
      'id': id,
      'cwd': cwd,
      'startupCommand': startupCommand,
      if (!sessionMetadata.isDefaultLocal)
        'sessionMetadata': sessionMetadata.toJson(),
      if (!launchProfile.isDefaultLocal)
        'launchProfile': launchProfile.toJson(),
    };
  }
}

class TerminalLaunchConfigurationPaneSplit
    extends TerminalLaunchConfigurationPaneNode {
  TerminalLaunchConfigurationPaneSplit({
    required this.direction,
    required this.first,
    required this.second,
    double ratio = 0.5,
  }) : ratio = _validRatioOrDefault(ratio);

  static TerminalLaunchConfigurationPaneSplit? fromJson(
    Map<String, Object?> map,
  ) {
    final first = TerminalLaunchConfigurationPaneNode.fromJson(map['first']);
    final second = TerminalLaunchConfigurationPaneNode.fromJson(map['second']);
    if (first == null || second == null) {
      return null;
    }
    return TerminalLaunchConfigurationPaneSplit(
      direction: _directionFromJson(map['direction']),
      ratio: _ratioFromJson(map['ratio']),
      first: first,
      second: second,
    );
  }

  final TerminalPaneSplitDirection direction;
  final TerminalLaunchConfigurationPaneNode first;
  final TerminalLaunchConfigurationPaneNode second;
  final double ratio;

  @override
  List<TerminalLaunchConfigurationPaneLeaf> get leaves =>
      <TerminalLaunchConfigurationPaneLeaf>[...first.leaves, ...second.leaves];

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

class TerminalSavedLaunchConfiguration {
  const TerminalSavedLaunchConfiguration({
    required this.file,
    required this.configuration,
    this.modifiedAt,
  });

  final File file;
  final TerminalLaunchConfiguration configuration;
  final DateTime? modifiedAt;

  String get path => file.path;
  String get name => launchConfigDisplayNameFromPath(path);
  int get windowCount => configuration.windows.length;
  int get tabCount => configuration.windows.fold<int>(
    0,
    (count, window) => count + window.tabs.length,
  );
  int get paneCount => configuration.windows
      .expand((window) => window.tabs)
      .fold<int>(0, (count, tab) => count + tab.rootPane.leaves.length);
  String get scopeLabel =>
      configuration.scope == TerminalLaunchConfigurationScope.tab
      ? 'Tab'
      : 'App';
  String get activeWindowLabel => windowCount == 0
      ? 'None'
      : 'Window ${configuration.activeWindowIndex + 1}';
}

class TerminalLaunchConfigurationStore {
  const TerminalLaunchConfigurationStore({this.directory});

  final Directory? directory;

  Directory defaultDirectory() {
    return directory ?? Directory(defaultLaunchConfigsDirectoryPath());
  }

  String suggestedNamedPath(String name) {
    final targetDirectory = defaultDirectory();
    return joinPlatformPath(
      targetDirectory.path,
      <String>['${sanitizeLaunchConfigFileStem(name)}.json'],
      separator: pathSeparatorForOperatingSystem(Platform.operatingSystem),
    );
  }

  TerminalLaunchConfiguration load(File file) {
    if (!file.existsSync()) {
      return const TerminalLaunchConfiguration();
    }
    try {
      return TerminalLaunchConfiguration.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
    } catch (_) {
      return const TerminalLaunchConfiguration();
    }
  }

  void save(File file, TerminalLaunchConfiguration configuration) {
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(configuration.toJson())}\n');
  }

  List<TerminalSavedLaunchConfiguration> listSaved() {
    final targetDirectory = defaultDirectory();
    if (!targetDirectory.existsSync()) {
      return const <TerminalSavedLaunchConfiguration>[];
    }
    final entries = <TerminalSavedLaunchConfiguration>[];
    for (final entity in targetDirectory.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final configuration = load(entity);
      if (!configuration.hasTabs) {
        continue;
      }
      DateTime? modifiedAt;
      try {
        modifiedAt = entity.lastModifiedSync();
      } catch (_) {
        modifiedAt = null;
      }
      entries.add(
        TerminalSavedLaunchConfiguration(
          file: entity,
          configuration: configuration,
          modifiedAt: modifiedAt,
        ),
      );
    }
    entries.sort((left, right) {
      final modifiedComparison = (right.modifiedAt ?? DateTime(0)).compareTo(
        left.modifiedAt ?? DateTime(0),
      );
      if (modifiedComparison != 0) {
        return modifiedComparison;
      }
      return left.name.compareTo(right.name);
    });
    return entries;
  }

  void remove(File file) {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

String defaultLaunchConfigsDirectoryPath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return joinPlatformPath(
    defaultTerminalStateDirectoryPath(
      environment: environment,
      operatingSystem: os,
      currentPath: currentPath,
    ),
    <String>['launch_configs'],
    separator: pathSeparatorForOperatingSystem(os),
  );
}

String suggestedLaunchConfigPath({
  String? cwd,
  String? currentPath,
  String? operatingSystem,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final separator = pathSeparatorForOperatingSystem(os);
  final baseDirectory = _nonEmpty(cwd) ?? currentPath ?? Directory.current.path;
  return joinPlatformPath(baseDirectory, <String>[
    'ianvs-terminal.launch.json',
  ], separator: separator);
}

String suggestedNamedLaunchConfigPath({
  required String name,
  String? currentPath,
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final separator = pathSeparatorForOperatingSystem(os);
  final directory = defaultLaunchConfigsDirectoryPath(
    environment: environment,
    operatingSystem: os,
    currentPath: currentPath,
  );
  return joinPlatformPath(directory, <String>[
    '${sanitizeLaunchConfigFileStem(name)}.json',
  ], separator: separator);
}

String sanitizeLaunchConfigFileStem(String name) {
  final collapsedWhitespace = name.trim().replaceAll(RegExp(r'\s+'), '-');
  final cleaned = collapsedWhitespace
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[.-]+|[.-]+$'), '')
      .toLowerCase();
  return cleaned.isEmpty ? 'ianvs-terminal-app' : cleaned;
}

String launchConfigDisplayNameFromPath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return '';
  }
  final separatorIndex = normalized.lastIndexOf(RegExp(r'[\\/]'));
  final fileName = separatorIndex >= 0
      ? normalized.substring(separatorIndex + 1)
      : normalized;
  if (fileName.toLowerCase().endsWith('.json') && fileName.length > 5) {
    return fileName.substring(0, fileName.length - 5);
  }
  return fileName;
}

List<TerminalLaunchConfigurationWindow> _windowsFromJson(
  Map<String, Object?> map,
) {
  final rawWindows = map['windows'];
  if (rawWindows is List && rawWindows.isNotEmpty) {
    final windows = <TerminalLaunchConfigurationWindow>[];
    for (var index = 0; index < rawWindows.length; index += 1) {
      final window = TerminalLaunchConfigurationWindow.fromJson(
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
    return const <TerminalLaunchConfigurationWindow>[];
  }
  final legacyWindow =
      TerminalLaunchConfigurationWindow.fromJson(<String, Object?>{
        'fallbackTitle': map['fallbackTitle'] ?? 'Window 1',
        'activeTabIndex': map['activeTabIndex'],
        'tabs': rawTabs,
      }, 0);
  if (legacyWindow == null) {
    return const <TerminalLaunchConfigurationWindow>[];
  }
  return <TerminalLaunchConfigurationWindow>[legacyWindow];
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
    return value.trimRight();
  }
  return fallback;
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

TerminalLaunchConfigurationPaneNode _paneNodeWithUniqueIds(
  TerminalLaunchConfigurationPaneNode node,
  Set<int> usedPaneIds,
  Set<int> acceptedOriginalIds,
  Map<int, int> remappedIds,
  int Function() allocatePaneId,
) {
  if (node is TerminalLaunchConfigurationPaneLeaf) {
    if (usedPaneIds.add(node.id)) {
      acceptedOriginalIds.add(node.id);
      return node;
    }
    final nextId = allocatePaneId();
    usedPaneIds.add(nextId);
    if (!acceptedOriginalIds.contains(node.id)) {
      remappedIds[node.id] = nextId;
    }
    return TerminalLaunchConfigurationPaneLeaf(
      id: nextId,
      cwd: node.cwd,
      startupCommand: node.startupCommand,
      sessionMetadata: node.sessionMetadata,
      launchProfile: node.launchProfile,
    );
  }

  final split = node as TerminalLaunchConfigurationPaneSplit;
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
  return TerminalLaunchConfigurationPaneSplit(
    direction: split.direction,
    ratio: split.ratio,
    first: first,
    second: second,
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

double _validRatioOrDefault(double value) {
  if (value >= TerminalPaneSplit.minRatio &&
      value <= TerminalPaneSplit.maxRatio) {
    return value;
  }
  return 0.5;
}

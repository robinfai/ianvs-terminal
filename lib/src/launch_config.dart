import 'dart:convert';
import 'dart:io';

import 'platform_paths.dart';
import 'session_launch.dart';
import 'session_metadata.dart';
import 'terminal_panes.dart';

class TerminalLaunchConfiguration {
  const TerminalLaunchConfiguration({
    this.version = 1,
    this.activeTabIndex = 0,
    this.tabs = const <TerminalLaunchConfigurationTab>[],
  });

  factory TerminalLaunchConfiguration.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalLaunchConfiguration();
    }
    final rawTabs = map['tabs'];
    if (rawTabs is! List || rawTabs.isEmpty) {
      return const TerminalLaunchConfiguration();
    }
    final tabs = <TerminalLaunchConfigurationTab>[];
    for (var index = 0; index < rawTabs.length; index += 1) {
      final tab = TerminalLaunchConfigurationTab.fromJson(
        rawTabs[index],
        index,
      );
      if (tab != null) {
        tabs.add(tab);
      }
    }
    if (tabs.isEmpty) {
      return const TerminalLaunchConfiguration();
    }
    return TerminalLaunchConfiguration(
      activeTabIndex: _intInRange(map['activeTabIndex'], 0, tabs.length - 1),
      tabs: tabs,
    ).withUniquePaneIds();
  }

  final int version;
  final int activeTabIndex;
  final List<TerminalLaunchConfigurationTab> tabs;

  bool get hasTabs => tabs.isNotEmpty;

  TerminalLaunchConfiguration withUniquePaneIds() {
    if (tabs.isEmpty) {
      return this;
    }
    final usedPaneIds = <int>{};
    final maxPaneId = tabs
        .expand((tab) => tab.rootPane.leaves)
        .fold<int>(0, (max, leaf) => leaf.id > max ? leaf.id : max);
    var nextPaneId = maxPaneId + 1;
    var changed = false;
    final uniqueTabs = <TerminalLaunchConfigurationTab>[];

    for (final tab in tabs) {
      final remappedIds = <int, int>{};
      final acceptedOriginalIds = <int>{};
      final uniqueRootPane = _paneNodeWithUniqueIds(
        tab.rootPane,
        usedPaneIds,
        acceptedOriginalIds,
        remappedIds,
        () => nextPaneId++,
      );
      changed = changed || !identical(uniqueRootPane, tab.rootPane);
      uniqueTabs.add(
        TerminalLaunchConfigurationTab(
          fallbackTitle: tab.fallbackTitle,
          activePaneId: remappedIds[tab.activePaneId] ?? tab.activePaneId,
          rootPane: uniqueRootPane,
        ),
      );
    }

    if (!changed) {
      return this;
    }
    return TerminalLaunchConfiguration(
      version: version,
      activeTabIndex: activeTabIndex,
      tabs: uniqueTabs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
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

class TerminalLaunchConfigurationStore {
  const TerminalLaunchConfigurationStore();

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

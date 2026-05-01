import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'terminal_panes.dart';

class TerminalSessionRestoreState {
  const TerminalSessionRestoreState({
    this.version = 1,
    this.activeTabIndex = 0,
    this.tabs = const <TerminalSessionRestoreTab>[],
  });

  factory TerminalSessionRestoreState.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalSessionRestoreState();
    }
    final rawTabs = map['tabs'];
    if (rawTabs is! List || rawTabs.isEmpty) {
      return const TerminalSessionRestoreState();
    }
    final tabs = <TerminalSessionRestoreTab>[];
    for (var index = 0; index < rawTabs.length; index += 1) {
      final tab = TerminalSessionRestoreTab.fromJson(rawTabs[index], index);
      if (tab != null) {
        tabs.add(tab);
      }
    }
    if (tabs.isEmpty) {
      return const TerminalSessionRestoreState();
    }
    return TerminalSessionRestoreState(
      activeTabIndex: _intInRange(map['activeTabIndex'], 0, tabs.length - 1),
      tabs: tabs,
    );
  }

  final int version;
  final int activeTabIndex;
  final List<TerminalSessionRestoreTab> tabs;

  bool get hasTabs => tabs.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
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
  const TerminalSessionRestorePaneLeaf({required this.id, required this.cwd});

  factory TerminalSessionRestorePaneLeaf.fromJson(Map<String, Object?> map) {
    return TerminalSessionRestorePaneLeaf(
      id: _positiveIntOrDefault(map['id'], 1),
      cwd: _stringOrDefault(map['cwd'], ''),
    );
  }

  final int id;
  final String cwd;

  @override
  List<TerminalSessionRestorePaneLeaf> get leaves =>
      <TerminalSessionRestorePaneLeaf>[this];

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{'type': 'leaf', 'id': id, 'cwd': cwd};
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
    return File(
      defaultSessionRestoreFilePath(
        environment: Platform.environment,
        operatingSystem: Platform.operatingSystem,
        currentPath: Directory.current.path,
      ),
    );
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

  TerminalSessionRestoreState load() => store.load();

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

String defaultSessionRestoreFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
  String? currentPath,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final fallbackCurrentPath = currentPath ?? Directory.current.path;
  final separator = _pathSeparatorFor(os);
  final baseDirectory = switch (os) {
    'macos' => _joinPath(
      _nonEmpty(env['HOME']) ?? fallbackCurrentPath,
      <String>['Library', 'Application Support', 'Ianvs', 'ianvs-terminal'],
      separator: separator,
    ),
    'windows' => _joinPath(
      _nonEmpty(env['APPDATA']) ??
          _nonEmpty(env['USERPROFILE']) ??
          fallbackCurrentPath,
      <String>['Ianvs', 'ianvs-terminal'],
      separator: separator,
    ),
    'linux' => _joinPath(
      _nonEmpty(env['XDG_STATE_HOME']) ??
          _linuxStateHome(
            home: _nonEmpty(env['HOME']),
            currentPath: fallbackCurrentPath,
          ),
      <String>['ianvs-terminal'],
      separator: separator,
    ),
    _ => _joinPath(_nonEmpty(env['HOME']) ?? fallbackCurrentPath, <String>[
      '.ianvs-terminal',
    ], separator: separator),
  };
  return _joinPath(baseDirectory, <String>[
    'session_restore.json',
  ], separator: separator);
}

String _linuxStateHome({required String? home, required String currentPath}) {
  if (home == null || home.isEmpty) {
    return currentPath;
  }
  return '$home/.local/state';
}

String _joinPath(
  String base,
  List<String> segments, {
  required String separator,
}) {
  final normalizedBase = base.trim();
  final normalizedSegments = segments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (normalizedSegments.isEmpty) {
    return normalizedBase;
  }
  final trimmedBase = normalizedBase.endsWith(separator)
      ? normalizedBase.substring(0, normalizedBase.length - separator.length)
      : normalizedBase;
  return <String>[trimmedBase, ...normalizedSegments].join(separator);
}

String _pathSeparatorFor(String operatingSystem) {
  return operatingSystem == 'windows' ? '\\' : '/';
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

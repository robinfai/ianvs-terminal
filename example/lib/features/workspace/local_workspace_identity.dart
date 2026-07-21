import 'dart:convert';

const int currentTerminalWorkspaceIndexSchemaVersion = 1;
const int maxRecentTerminalWorkspaces = 10;
const String defaultTerminalWorkspaceId = 'default';
const String defaultTerminalWorkspaceName = 'Default Workspace';

final class UnsupportedTerminalWorkspaceIndexSchemaVersion
    implements Exception {
  const UnsupportedTerminalWorkspaceIndexSchemaVersion(this.version);

  final int version;

  @override
  String toString() {
    return 'Unsupported terminal workspace index schema version: $version '
        '(current: $currentTerminalWorkspaceIndexSchemaVersion)';
  }
}

final class TerminalWorkspaceIdentity {
  const TerminalWorkspaceIdentity({
    required this.id,
    required this.name,
    this.projectPath,
  });

  static const defaultWorkspace = TerminalWorkspaceIdentity(
    id: defaultTerminalWorkspaceId,
    name: defaultTerminalWorkspaceName,
  );

  factory TerminalWorkspaceIdentity.forProject(
    String projectPath, {
    String? name,
  }) {
    final normalizedPath = normalizeTerminalWorkspaceProjectPath(projectPath);
    if (normalizedPath == null) {
      throw ArgumentError.value(
        projectPath,
        'projectPath',
        'Project path must not be empty.',
      );
    }
    if (!_isAbsoluteLocalProjectPath(normalizedPath)) {
      throw ArgumentError.value(
        projectPath,
        'projectPath',
        'Project path must be absolute.',
      );
    }
    return TerminalWorkspaceIdentity(
      id: 'project-${_stableWorkspaceToken(normalizedPath)}',
      name:
          _trimmedStringOrNull(name) ??
          _terminalWorkspaceProjectBasename(normalizedPath),
      projectPath: normalizedPath,
    );
  }

  final String id;
  final String name;
  final String? projectPath;

  TerminalWorkspaceIdentity normalized() {
    final normalizedPath = normalizeTerminalWorkspaceProjectPath(projectPath);
    final normalizedId = _trimmedStringOrNull(id);
    if (normalizedId == null && normalizedPath != null) {
      return TerminalWorkspaceIdentity.forProject(normalizedPath, name: name);
    }
    final effectiveId = normalizedId ?? defaultTerminalWorkspaceId;
    final effectiveName =
        _trimmedStringOrNull(name) ??
        (normalizedPath == null
            ? defaultTerminalWorkspaceName
            : _terminalWorkspaceProjectBasename(normalizedPath));
    return TerminalWorkspaceIdentity(
      id: effectiveId,
      name: effectiveName,
      projectPath: normalizedPath,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalWorkspaceIdentity &&
        other.id == id &&
        other.name == name &&
        other.projectPath == projectPath;
  }

  @override
  int get hashCode => Object.hash(id, name, projectPath);
}

final class TerminalWorkspaceRecentEntry {
  const TerminalWorkspaceRecentEntry({
    required this.identity,
    required this.lastOpenedAtUtc,
  });

  final TerminalWorkspaceIdentity identity;
  final DateTime lastOpenedAtUtc;

  Map<String, Object?> toJson() {
    final normalizedIdentity = identity.normalized();
    return {
      'id': normalizedIdentity.id,
      'name': normalizedIdentity.name,
      'projectPath': normalizedIdentity.projectPath,
      'lastOpenedAtUtc': lastOpenedAtUtc.toUtc().toIso8601String(),
    };
  }

  static TerminalWorkspaceRecentEntry? fromJson(Map<Object?, Object?> json) {
    final id = _trimmedStringOrNull(json['id']);
    final name = _trimmedStringOrNull(json['name']);
    final projectPath = normalizeTerminalWorkspaceProjectPath(
      json['projectPath'],
    );
    final lastOpenedAtUtc = _utcDateTimeOrNull(json['lastOpenedAtUtc']);
    if (id == null || name == null || lastOpenedAtUtc == null) {
      return null;
    }
    return TerminalWorkspaceRecentEntry(
      identity: TerminalWorkspaceIdentity(
        id: id,
        name: name,
        projectPath: projectPath,
      ).normalized(),
      lastOpenedAtUtc: lastOpenedAtUtc,
    );
  }
}

final class TerminalWorkspaceIndex {
  const TerminalWorkspaceIndex({
    this.currentWorkspaceId,
    this.recent = const <TerminalWorkspaceRecentEntry>[],
  });

  final String? currentWorkspaceId;
  final List<TerminalWorkspaceRecentEntry> recent;

  TerminalWorkspaceIndex markOpened(
    TerminalWorkspaceIdentity identity, {
    required DateTime openedAtUtc,
  }) {
    final normalizedIdentity = identity.normalized();
    return TerminalWorkspaceIndex(
      currentWorkspaceId: normalizedIdentity.id,
      recent: [
        TerminalWorkspaceRecentEntry(
          identity: normalizedIdentity,
          lastOpenedAtUtc: openedAtUtc.toUtc(),
        ),
        for (final entry in recent)
          if (!_sameTerminalWorkspace(entry.identity, normalizedIdentity))
            entry,
      ],
    ).normalized();
  }

  TerminalWorkspaceIndex upsert(
    TerminalWorkspaceIdentity identity, {
    required DateTime openedAtUtcIfMissing,
    bool makeCurrent = true,
  }) {
    final normalizedIdentity = identity.normalized();
    TerminalWorkspaceRecentEntry? existing;
    for (final entry in recent) {
      if (_sameTerminalWorkspace(entry.identity, normalizedIdentity)) {
        existing = entry;
        break;
      }
    }
    final updated = TerminalWorkspaceRecentEntry(
      identity: normalizedIdentity,
      lastOpenedAtUtc:
          existing?.lastOpenedAtUtc ?? openedAtUtcIfMissing.toUtc(),
    );
    final hasExisting = existing != null;
    return TerminalWorkspaceIndex(
      currentWorkspaceId: makeCurrent
          ? normalizedIdentity.id
          : currentWorkspaceId,
      recent: [
        for (final entry in recent)
          if (_sameTerminalWorkspace(entry.identity, normalizedIdentity))
            updated
          else
            entry,
        if (!hasExisting) updated,
      ],
    ).normalized();
  }

  TerminalWorkspaceIndex normalized() {
    final normalizedRecent = <TerminalWorkspaceRecentEntry>[];
    final seenIds = <String>{};
    final seenProjectPaths = <String>{};
    for (final entry in recent.take(maxRecentTerminalWorkspaces * 4)) {
      final identity = entry.identity.normalized();
      final projectPath = identity.projectPath;
      if (!seenIds.add(identity.id) ||
          (projectPath != null && !seenProjectPaths.add(projectPath))) {
        continue;
      }
      normalizedRecent.add(
        TerminalWorkspaceRecentEntry(
          identity: identity,
          lastOpenedAtUtc: entry.lastOpenedAtUtc.toUtc(),
        ),
      );
      if (normalizedRecent.length >= maxRecentTerminalWorkspaces) {
        break;
      }
    }
    final requestedCurrent = _trimmedStringOrNull(currentWorkspaceId);
    final effectiveCurrent =
        requestedCurrent != null &&
            normalizedRecent.any(
              (entry) => entry.identity.id == requestedCurrent,
            )
        ? requestedCurrent
        : normalizedRecent.firstOrNull?.identity.id;
    return TerminalWorkspaceIndex(
      currentWorkspaceId: effectiveCurrent,
      recent: List.unmodifiable(normalizedRecent),
    );
  }

  Map<String, Object?> toJson() {
    final normalizedIndex = normalized();
    return {
      'schemaVersion': currentTerminalWorkspaceIndexSchemaVersion,
      'currentWorkspaceId': normalizedIndex.currentWorkspaceId,
      'recent': normalizedIndex.recent
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  static TerminalWorkspaceIndex fromJson(Map<Object?, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const FormatException(
        'Workspace index schemaVersion must be an integer.',
      );
    }
    if (schemaVersion != currentTerminalWorkspaceIndexSchemaVersion) {
      throw UnsupportedTerminalWorkspaceIndexSchemaVersion(schemaVersion);
    }
    final recent = <TerminalWorkspaceRecentEntry>[];
    final rawRecent = json['recent'];
    if (rawRecent is List) {
      for (final value in rawRecent.take(maxRecentTerminalWorkspaces * 4)) {
        final object = _objectMap(value);
        if (object == null) {
          continue;
        }
        final entry = TerminalWorkspaceRecentEntry.fromJson(object);
        if (entry != null) {
          recent.add(entry);
        }
      }
    }
    return TerminalWorkspaceIndex(
      currentWorkspaceId: _trimmedStringOrNull(json['currentWorkspaceId']),
      recent: recent,
    ).normalized();
  }
}

String? normalizeTerminalWorkspaceProjectPath(Object? value) {
  final path = _trimmedStringOrNull(value);
  if (path == null) {
    return null;
  }
  if (path == '/' || RegExp(r'^[A-Za-z]:[\\/]$').hasMatch(path)) {
    return path;
  }
  return path.replaceFirst(RegExp(r'[\\/]+$'), '');
}

bool _sameTerminalWorkspace(
  TerminalWorkspaceIdentity first,
  TerminalWorkspaceIdentity second,
) {
  return first.id == second.id ||
      (first.projectPath != null && first.projectPath == second.projectPath);
}

String _terminalWorkspaceProjectBasename(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  for (final part in parts.reversed) {
    final normalized = part.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return path;
}

bool _isAbsoluteLocalProjectPath(String path) {
  return path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _stableWorkspaceToken(String value) {
  final bytes = utf8.encode(value);
  final first = _fnv1a64(bytes, 0xcbf29ce484222325);
  final second = _fnv1a64(bytes.reversed, 0x84222325cbf29ce4);
  return '${first.toRadixString(16).padLeft(16, '0')}'
      '${second.toRadixString(16).padLeft(16, '0')}';
}

int _fnv1a64(Iterable<int> bytes, int offset) {
  const mask = 0xffffffffffffffff;
  const prime = 0x100000001b3;
  var hash = offset;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return hash;
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

String? _trimmedStringOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _utcDateTimeOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

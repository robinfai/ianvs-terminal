/// The policy applied when both sides changed the same JSON value differently.
enum JsonConflictResolution { unresolved, preferLocal, preferRemote }

/// A conflicting edit. Presence flags distinguish a missing value from JSON
/// `null`; the values themselves are retained in memory only.
final class JsonMergeConflict {
  const JsonMergeConflict({
    required this.path,
    required this.basePresent,
    required this.base,
    required this.localPresent,
    required this.local,
    required this.remotePresent,
    required this.remote,
  });

  /// JSON Pointer-like path. Profile ids occupy the array segment so paths stay
  /// stable when profile ordering changes.
  final String path;
  final bool basePresent;
  final Object? base;
  final bool localPresent;
  final Object? local;
  final bool remotePresent;
  final Object? remote;
}

final class JsonThreeWayMergeResult {
  const JsonThreeWayMergeResult({
    required this.document,
    required this.conflicts,
  });

  final Map<String, Object?>? document;
  final List<JsonMergeConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Merges two JSON object snapshots relative to their last synchronized base.
///
/// A null [base] means that synchronization has not happened before. Null
/// [local] or [remote] represents an absent document. Callers must not upload
/// [JsonThreeWayMergeResult.document] while unresolved conflicts are present.
JsonThreeWayMergeResult mergeJsonDocuments({
  required Map<String, Object?>? base,
  required Map<String, Object?>? local,
  required Map<String, Object?>? remote,
  JsonConflictResolution conflictResolution = JsonConflictResolution.unresolved,
}) {
  final merger = _JsonMerger(conflictResolution);
  final merged = merger.merge(
    '',
    _Value(base != null, base),
    _Value(local != null, local),
    _Value(remote != null, remote),
  );
  return JsonThreeWayMergeResult(
    document: merged.present
        ? Map<String, Object?>.from(merged.value! as Map)
        : null,
    conflicts: List.unmodifiable(merger.conflicts),
  );
}

final class _JsonMerger {
  _JsonMerger(this.resolution);

  final JsonConflictResolution resolution;
  final conflicts = <JsonMergeConflict>[];

  _Value merge(String path, _Value base, _Value local, _Value remote) {
    if (_same(local, remote)) return _copy(local);
    if (_same(base, local)) return _copy(remote);
    if (_same(base, remote)) return _copy(local);

    if (local.present &&
        remote.present &&
        local.value is Map &&
        remote.value is Map &&
        (!base.present || base.value is Map)) {
      return _mergeMaps(path, base, local, remote);
    }
    if (_isProfilesPath(path) &&
        local.present &&
        remote.present &&
        local.value is List &&
        remote.value is List &&
        (!base.present || base.value is List)) {
      final profileMerge = _mergeProfiles(path, base, local, remote);
      if (profileMerge != null) return profileMerge;
    }

    if (resolution == JsonConflictResolution.unresolved) {
      conflicts.add(
        JsonMergeConflict(
          path: path.isEmpty ? '/' : path,
          basePresent: base.present,
          base: _clone(base.value),
          localPresent: local.present,
          local: _clone(local.value),
          remotePresent: remote.present,
          remote: _clone(remote.value),
        ),
      );
    }
    return switch (resolution) {
      JsonConflictResolution.preferRemote => _copy(remote),
      JsonConflictResolution.unresolved ||
      JsonConflictResolution.preferLocal => _copy(local),
    };
  }

  _Value _mergeMaps(String path, _Value base, _Value local, _Value remote) {
    final baseMap = base.present
        ? Map<String, Object?>.from(base.value! as Map)
        : const <String, Object?>{};
    final localMap = Map<String, Object?>.from(local.value! as Map);
    final remoteMap = Map<String, Object?>.from(remote.value! as Map);
    final keys = <String>{...baseMap.keys, ...localMap.keys, ...remoteMap.keys};
    final result = <String, Object?>{};
    for (final key in keys) {
      final merged = merge(
        '$path/${_escape(key)}',
        _Value(baseMap.containsKey(key), baseMap[key]),
        _Value(localMap.containsKey(key), localMap[key]),
        _Value(remoteMap.containsKey(key), remoteMap[key]),
      );
      if (merged.present) result[key] = merged.value;
    }
    return _Value(true, result);
  }

  _Value? _mergeProfiles(
    String path,
    _Value base,
    _Value local,
    _Value remote,
  ) {
    final baseProfiles = _profilesById(
      base.present ? base.value! as List : const [],
    );
    final localProfiles = _profilesById(local.value! as List);
    final remoteProfiles = _profilesById(remote.value! as List);
    if (baseProfiles == null ||
        localProfiles == null ||
        remoteProfiles == null) {
      return null;
    }
    final ids = <String>{
      ...baseProfiles.keys,
      ...localProfiles.keys,
      ...remoteProfiles.keys,
    };
    final result = <Object?>[];
    for (final id in ids) {
      final merged = merge(
        '$path/${_escape(id)}',
        _Value(baseProfiles.containsKey(id), baseProfiles[id]),
        _Value(localProfiles.containsKey(id), localProfiles[id]),
        _Value(remoteProfiles.containsKey(id), remoteProfiles[id]),
      );
      if (merged.present) result.add(merged.value);
    }
    return _Value(true, result);
  }
}

Map<String, Object?>? _profilesById(List<Object?> profiles) {
  final result = <String, Object?>{};
  for (final profile in profiles) {
    if (profile is! Map || profile['id'] is! String) return null;
    final id = profile['id']! as String;
    if (result.containsKey(id)) return null;
    result[id] = Map<String, Object?>.from(profile);
  }
  return result;
}

bool _isProfilesPath(String path) => path.split('/').last == 'profiles';

String _escape(String segment) =>
    segment.replaceAll('~', '~0').replaceAll('/', '~1');

final class _Value {
  const _Value(this.present, this.value);

  final bool present;
  final Object? value;
}

_Value _copy(_Value value) => _Value(value.present, _clone(value.value));

bool _same(_Value left, _Value right) =>
    left.present == right.present &&
    (!left.present || _deepEquals(left.value, right.value));

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _deepEquals(left[index], right[index]));
  }
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _deepEquals(left[key], right[key]),
        );
  }
  return left == right;
}

Object? _clone(Object? value) {
  if (value is List) return value.map(_clone).toList();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _clone(entry.value),
    };
  }
  return value;
}

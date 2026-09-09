import 'dart:io';

import '../../features/config/data_api_terminal_config_repository.dart';
import '../../features/config/local_terminal_config_models.dart';
import '../../features/config/local_terminal_config_repository.dart';
import '../../features/persistence/versioned_document.dart';
import '../../features/preferences/app_preferences_models.dart';
import '../../features/preferences/app_preferences_repository.dart';
import '../../features/preferences/data_api_app_preferences_repository.dart';
import '../../features/profiles/data_api_profile_repository.dart';
import '../../features/profiles/profile_models.dart';
import '../../features/profiles/profile_repository.dart';
import '../../features/shell/paste_history_repository.dart';
import '../repositories/data_api_repository_helpers.dart';
import '../services/data_api_client.dart';
import 'json_three_way_merge.dart';
import 'local_first_sync.dart';

final class LocalSyncEditConflict implements Exception {
  const LocalSyncEditConflict(this.paths);

  final List<String> paths;

  @override
  String toString() =>
      'The local document changed since it was loaded at: ${paths.join(', ')}';
}

/// Owns the JSON bindings for local repositories and creates typed decorators
/// which notify a [LocalFirstSyncCoordinator] after durable local writes.
final class SyncRepositoryBindings {
  SyncRepositoryBindings({
    required ProfileRepositoryPort profiles,
    required AppPreferencesRepositoryPort preferences,
    required TerminalConfigRepository terminalConfig,
    required PasteHistoryRepositoryPort pasteHistory,
  }) : _profiles = profiles,
       _preferences = preferences,
       _terminalConfig = terminalConfig,
       _pasteHistory = pasteHistory {
    profileBinding = _profileBinding(profiles);
    preferencesBinding = _preferencesBinding(preferences);
    terminalConfigBinding = _terminalConfigBinding(terminalConfig);
  }

  final ProfileRepositoryPort _profiles;
  final AppPreferencesRepositoryPort _preferences;
  final TerminalConfigRepository _terminalConfig;
  final PasteHistoryRepositoryPort _pasteHistory;

  late final SyncDocumentBinding profileBinding;
  late final SyncDocumentBinding preferencesBinding;
  late final SyncDocumentBinding terminalConfigBinding;

  List<SyncDocumentBinding> get bindings => List.unmodifiable([
    profileBinding,
    preferencesBinding,
    terminalConfigBinding,
  ]);

  LocalFirstRepositories wrap(LocalFirstSyncCoordinator coordinator) {
    return LocalFirstRepositories(
      profiles: LocalFirstProfileRepository(
        local: _profiles,
        binding: profileBinding,
        coordinator: coordinator,
      ),
      preferences: LocalFirstAppPreferencesRepository(
        local: _preferences,
        binding: preferencesBinding,
        coordinator: coordinator,
      ),
      terminalConfig: LocalFirstTerminalConfigRepository(
        local: _terminalConfig,
        binding: terminalConfigBinding,
        coordinator: coordinator,
      ),
      pasteHistory: _pasteHistory,
    );
  }
}

final class LocalFirstRepositories {
  const LocalFirstRepositories({
    required this.profiles,
    required this.preferences,
    required this.terminalConfig,
    required this.pasteHistory,
  });

  final ProfileRepositoryPort profiles;
  final AppPreferencesRepositoryPort preferences;
  final TerminalConfigRepository terminalConfig;
  final PasteHistoryRepositoryPort pasteHistory;
}

final class LocalFirstProfileRepository extends ProfileRepositoryPort {
  LocalFirstProfileRepository({
    required ProfileRepositoryPort local,
    required SyncDocumentBinding binding,
    required LocalFirstSyncCoordinator coordinator,
  }) : _local = local,
       _binding = binding,
       _coordinator = coordinator;

  final ProfileRepositoryPort _local;
  final SyncDocumentBinding _binding;
  final LocalFirstSyncCoordinator _coordinator;
  final _versions = _LocalVersionTracker();

  @override
  Future<TerminalProfilesDocument> load() => _binding.local(_local.load);

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> loadVersioned() =>
      _binding.local(() async {
        final value = await _local.load();
        return VersionedDocument(
          value: value,
          revision: _versions.capture(_versionedProfilesJson(value)),
        );
      });

  @override
  Future<void> save(TerminalProfilesDocument document) {
    return _binding.local(() async {
      await _local.save(document);
      _coordinator.changed();
    });
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> saveVersioned(
    VersionedDocument<TerminalProfilesDocument> document,
  ) {
    return _binding.local(() async {
      final latest = await _local.load();
      final merged = _mergeVersionedEdit(
        tracker: _versions,
        revision: document.revision,
        latest: _versionedProfilesJson(latest),
        submitted: _versionedProfilesJson(document.value),
      );
      final decoded = _decodeProfilesJson(merged);
      final value = TerminalProfilesDocument(
        schemaVersion: decoded.schemaVersion,
        profiles: decoded.profiles,
        loadWarnings: decoded.loadWarnings,
        secretClearIntents: document.value.secretClearIntents,
      );
      await _local.save(value);
      _coordinator.changed();
      return VersionedDocument(
        value: value,
        revision: _versions.capture(merged),
      );
    });
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> updateVersioned(
    TerminalProfilesDocumentUpdate update, {
    VersionedDocument<TerminalProfilesDocument>? base,
  }) {
    return _binding.local(() async {
      final current = await _local.load();
      final next = update(current);
      await _local.save(next);
      _coordinator.changed();
      return VersionedDocument(
        value: next,
        revision: _versions.capture(_versionedProfilesJson(next)),
      );
    });
  }

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) =>
      _binding.local(() => _local.exportDocument(document, basename: basename));
}

final class LocalFirstAppPreferencesRepository
    extends AppPreferencesRepositoryPort {
  LocalFirstAppPreferencesRepository({
    required AppPreferencesRepositoryPort local,
    required SyncDocumentBinding binding,
    required LocalFirstSyncCoordinator coordinator,
  }) : _local = local,
       _binding = binding,
       _coordinator = coordinator;

  final AppPreferencesRepositoryPort _local;
  final SyncDocumentBinding _binding;
  final LocalFirstSyncCoordinator _coordinator;
  final _versions = _LocalVersionTracker();

  @override
  Future<TerminalAppPreferencesDocument?> load() => _binding.local(_local.load);

  @override
  Future<VersionedDocument<TerminalAppPreferencesDocument?>> loadVersioned() =>
      _binding.local(() async {
        final value = await _local.load();
        final json = (value ?? const TerminalAppPreferencesDocument()).toJson();
        return VersionedDocument(
          value: value,
          revision: _versions.capture(json),
        );
      });

  @override
  Future<void> save(TerminalAppPreferencesDocument document) {
    return _binding.local(() async {
      await _local.save(document);
      _coordinator.changed();
    });
  }

  @override
  Future<VersionedDocument<TerminalAppPreferencesDocument>> saveVersioned(
    VersionedDocument<TerminalAppPreferencesDocument> document,
  ) {
    return _binding.local(() async {
      final latest =
          (await _local.load() ?? const TerminalAppPreferencesDocument())
              .toJson();
      final merged = _mergeVersionedEdit(
        tracker: _versions,
        revision: document.revision,
        latest: latest,
        submitted: document.value.toJson(),
      );
      final value = _decodePreferencesJson(merged);
      await _local.save(value);
      _coordinator.changed();
      return VersionedDocument(
        value: value,
        revision: _versions.capture(merged),
      );
    });
  }
}

final class LocalFirstTerminalConfigRepository
    extends TerminalConfigRepository {
  LocalFirstTerminalConfigRepository({
    required TerminalConfigRepository local,
    required SyncDocumentBinding binding,
    required LocalFirstSyncCoordinator coordinator,
  }) : _local = local,
       _binding = binding,
       _coordinator = coordinator;

  final TerminalConfigRepository _local;
  final SyncDocumentBinding _binding;
  final LocalFirstSyncCoordinator _coordinator;
  final _versions = _LocalVersionTracker();

  @override
  Future<LocalTerminalConfigDocument?> load() => _binding.local(_local.load);

  @override
  Future<VersionedDocument<LocalTerminalConfigDocument?>> loadVersioned() =>
      _binding.local(() async {
        final value = await _local.load();
        final json = (value ?? const LocalTerminalConfigDocument()).toJson();
        return VersionedDocument(
          value: value,
          revision: _versions.capture(json),
        );
      });

  @override
  Future<void> save(LocalTerminalConfigDocument document) {
    return _binding.local(() async {
      await _local.save(document);
      _coordinator.changed();
    });
  }

  @override
  Future<VersionedDocument<LocalTerminalConfigDocument>> saveVersioned(
    VersionedDocument<LocalTerminalConfigDocument> document,
  ) {
    return _binding.local(() async {
      final latest =
          (await _local.load() ?? const LocalTerminalConfigDocument()).toJson();
      final merged = _mergeVersionedEdit(
        tracker: _versions,
        revision: document.revision,
        latest: latest,
        submitted: document.value.toJson(),
      );
      final value = _decodeTerminalConfigJson(merged);
      await _local.save(value);
      _coordinator.changed();
      return VersionedDocument(
        value: value,
        revision: _versions.capture(merged),
      );
    });
  }

  @override
  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) {
    return _binding.local(() async {
      final current = await _local.load() ?? fallback;
      final next = transform(current);
      await _local.save(next);
      _coordinator.changed();
      return next;
    });
  }
}

SyncDocumentBinding _profileBinding(ProfileRepositoryPort local) {
  return SyncDocumentBinding(
    kind: DataApiProfileRepository.resourceKind,
    id: DataApiProfileRepository.resourceId,
    readLocal: () async => _completeProfilesJson(await local.load()),
    writeLocal: (json) => local.save(
      json == null
          ? const TerminalProfilesDocument(profiles: <TerminalProfile>[])
          : _decodeProfilesJson(json),
    ),
    decodeRemote: _decodeRemoteProfiles,
    encodeRemote: (json) {
      final payload = encodeDataApiProfilesDocument(_decodeProfilesJson(json));
      return (
        data: payload.data,
        sensitive: payload.sensitive.isEmpty ? null : payload.sensitive,
      );
    },
    validate: (json) {
      if (json != null) _decodeProfilesJson(json);
    },
  );
}

SyncDocumentBinding _preferencesBinding(AppPreferencesRepositoryPort local) {
  return SyncDocumentBinding(
    kind: DataApiAppPreferencesRepository.resourceKind,
    id: DataApiAppPreferencesRepository.resourceId,
    readLocal: () async => (await local.load())?.toJson(),
    writeLocal: (json) => local.save(
      json == null
          ? const TerminalAppPreferencesDocument()
          : _decodePreferencesJson(json),
    ),
    decodeRemote: _decodeRemotePreferences,
    encodeRemote: (json) =>
        (data: _decodePreferencesJson(json).toJson(), sensitive: null),
    validate: (json) {
      if (json != null) _decodePreferencesJson(json);
    },
  );
}

SyncDocumentBinding _terminalConfigBinding(TerminalConfigRepository local) {
  return SyncDocumentBinding(
    kind: DataApiTerminalConfigRepository.resourceKind,
    id: DataApiTerminalConfigRepository.resourceId,
    readLocal: () async => (await local.load())?.toJson(),
    writeLocal: (json) => local.save(
      json == null
          ? const LocalTerminalConfigDocument()
          : _decodeTerminalConfigJson(json),
    ),
    decodeRemote: _decodeRemoteTerminalConfig,
    encodeRemote: (json) =>
        (data: _decodeTerminalConfigJson(json).toJson(), sensitive: null),
    validate: (json) {
      if (json != null) _decodeTerminalConfigJson(json);
    },
  );
}

SyncJson _decodeRemoteProfiles(DataApiResource resource) {
  return _completeProfilesJson(
    DataApiProfileRepository.decodeResource(resource),
  );
}

SyncJson _decodeRemotePreferences(DataApiResource resource) {
  final data = _ordinaryRemoteData(
    resource,
    kind: DataApiAppPreferencesRepository.resourceKind,
    id: DataApiAppPreferencesRepository.resourceId,
    name: 'App preferences',
  );
  return _decodePreferencesJson(data).toJson();
}

SyncJson _decodeRemoteTerminalConfig(DataApiResource resource) {
  final data = _ordinaryRemoteData(
    resource,
    kind: DataApiTerminalConfigRepository.resourceKind,
    id: DataApiTerminalConfigRepository.resourceId,
    name: 'Terminal config',
  );
  return _decodeTerminalConfigJson(data).toJson();
}

SyncJson _ordinaryRemoteData(
  DataApiResource resource, {
  required String kind,
  required String id,
  required String name,
}) {
  final validated = requireDataApiResourceIdentity(
    resource,
    kind: kind,
    id: id,
  );
  if (validated.hasSensitive || validated.sensitive != null) {
    throw FormatException('$name must not contain a sensitive payload.');
  }
  return dataApiObject(validated.data, documentName: name);
}

TerminalProfilesDocument _decodeProfilesJson(SyncJson json) {
  final decoded = TerminalProfilesDocument.fromJson(json);
  if (decoded.schemaVersion != TerminalProfilesDocument.currentSchemaVersion ||
      decoded.loadWarnings.isNotEmpty ||
      !dataApiJsonEquivalent(_completeProfilesJson(decoded), json)) {
    throw const FormatException(
      'Profiles are not a canonical current-schema document.',
    );
  }
  return decoded;
}

SyncJson _completeProfilesJson(TerminalProfilesDocument document) {
  if (document.schemaVersion != TerminalProfilesDocument.currentSchemaVersion) {
    throw UnsupportedTerminalProfilesSchemaVersion(document.schemaVersion);
  }
  if (document.loadWarnings.isNotEmpty) {
    throw const FormatException(
      'Profiles with load warnings cannot be synchronized.',
    );
  }
  if (document.profiles.length > maxTerminalProfiles) {
    throw const FormatException(
      'Profiles document exceeds the limit of $maxTerminalProfiles.',
    );
  }
  final payload = encodeDataApiProfilesDocument(document);
  return mergeDataApiObjects(payload.data, payload.sensitive);
}

SyncJson _versionedProfilesJson(TerminalProfilesDocument document) {
  if (document.loadWarnings.isNotEmpty) return document.toJson();
  return _completeProfilesJson(document);
}

final class _LocalVersionTracker {
  var _nextRevision = 1;
  final Map<int, SyncJson> _snapshots = {};

  int capture(SyncJson json) {
    final revision = _nextRevision++;
    _snapshots[revision] = deepCopyDataApiObject(json);
    if (_snapshots.length > 64) _snapshots.remove(_snapshots.keys.first);
    return revision;
  }

  SyncJson requireBase(int? revision) {
    final base = revision == null ? null : _snapshots[revision];
    if (base == null) {
      throw StateError(
        'The local version token is missing or expired; reload before saving.',
      );
    }
    return base;
  }
}

SyncJson _mergeVersionedEdit({
  required _LocalVersionTracker tracker,
  required int? revision,
  required SyncJson latest,
  required SyncJson submitted,
}) {
  final result = mergeJsonDocuments(
    base: tracker.requireBase(revision),
    local: latest,
    remote: submitted,
  );
  if (result.hasConflicts) {
    throw LocalSyncEditConflict(
      List.unmodifiable(result.conflicts.map((conflict) => conflict.path)),
    );
  }
  return result.document!;
}

TerminalAppPreferencesDocument _decodePreferencesJson(SyncJson json) {
  final decoded = TerminalAppPreferencesDocument.fromJson(json);
  if (decoded.schemaVersion !=
          TerminalAppPreferencesDocument.currentSchemaVersion ||
      !dataApiJsonEquivalent(decoded.toJson(), json)) {
    throw const FormatException(
      'App preferences are not a canonical current-schema document.',
    );
  }
  return decoded;
}

LocalTerminalConfigDocument _decodeTerminalConfigJson(SyncJson json) {
  final decoded = LocalTerminalConfigDocument.fromJson(json);
  if (!dataApiJsonEquivalent(decoded.toJson(), json)) {
    throw const NonCanonicalCurrentTerminalConfigException();
  }
  return decoded;
}

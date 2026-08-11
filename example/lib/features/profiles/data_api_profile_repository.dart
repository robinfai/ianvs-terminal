import 'dart:io';

import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

typedef DataApiProfilePayload = ({
  Map<String, Object?> data,
  Map<String, Object?> sensitive,
});

DataApiProfilePayload encodeDataApiProfile(TerminalProfile profile) {
  final plain = profile.toJson();
  final complete = <String, Object?>{
    'id': profile.id,
    'name': profile.name,
    if (profile.tags.isNotEmpty) 'tags': profile.tags,
    if (profile.triggers.isNotEmpty)
      'triggers': profile.triggers
          .map((trigger) => trigger.toJson())
          .toList(growable: false),
    if (profile.switchRules.isNotEmpty)
      'automaticProfileSwitching': profile.switchRules
          .map((rule) => rule.toJson())
          .toList(growable: false),
    ...profile.sessionConfig.toJson(includeSensitiveFields: true),
  };
  return (data: plain, sensitive: dataApiJsonDifference(complete, plain));
}

DataApiProfilePayload encodeDataApiProfilesDocument(
  TerminalProfilesDocument document,
) {
  final boundedProfiles = document.profiles
      .take(maxTerminalProfiles)
      .toList(growable: false);
  final plain = <String, Object?>{
    'schemaVersion': document.schemaVersion,
    'profiles': boundedProfiles
        .map((profile) => encodeDataApiProfile(profile).data)
        .toList(growable: false),
  };
  final complete = <String, Object?>{
    'schemaVersion': document.schemaVersion,
    'profiles': boundedProfiles
        .map((profile) {
          final payload = encodeDataApiProfile(profile);
          return mergeDataApiObjects(payload.data, payload.sensitive);
        })
        .toList(growable: false),
  };
  return (data: plain, sensitive: dataApiJsonDifference(complete, plain));
}

final class DataApiProfileRepository extends ProfileRepositoryPort {
  DataApiProfileRepository({
    required DataApiResourceClient client,
    DirectoryResolver? exportDirectoryResolver,
  }) : _client = client,
       _exportDirectoryResolver = exportDirectoryResolver;

  static const resourceKind = 'profile';
  static const resourceId = 'default';

  final DataApiResourceClient _client;
  final DirectoryResolver? _exportDirectoryResolver;
  @override
  Future<TerminalProfilesDocument> load() async {
    return (await loadVersioned()).value;
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> loadVersioned() async {
    final resource = await _client.getResource(
      kind: resourceKind,
      id: resourceId,
      includeSensitive: true,
    );
    if (resource == null) {
      final fallback = TerminalProfilesDocument(
        profiles: <TerminalProfile>[
          defaultTerminalProfile(),
          vt220TerminalProfile(),
        ],
      );
      try {
        final saved = await _put(
          fallback,
          expectedRevision: 0,
          clearSensitive: false,
        );
        return VersionedDocument<TerminalProfilesDocument>(
          value: fallback,
          revision: saved.revision,
        );
      } on DataApiRevisionConflictException {
        // Another client may have initialized the single document after our
        // 404. The winner is authoritative; bounded recovery performs one
        // fresh read instead of overwriting it or failing bootstrap.
        final winner = await _client.getResource(
          kind: resourceKind,
          id: resourceId,
          includeSensitive: true,
        );
        if (winner == null) {
          rethrow;
        }
        return VersionedDocument<TerminalProfilesDocument>(
          value: _decode(winner),
          revision: winner.revision,
        );
      }
    }
    return VersionedDocument<TerminalProfilesDocument>(
      value: _decode(resource),
      revision: resource.revision,
    );
  }

  TerminalProfilesDocument _decode(DataApiResource resource) {
    final validated = requireDataApiResourceIdentity(
      resource,
      kind: resourceKind,
      id: resourceId,
    );
    if (validated.hasSensitive != (validated.sensitive != null)) {
      throw const FormatException(
        'Profiles sensitive envelope is inconsistent.',
      );
    }
    final data = dataApiObject(
      validated.data,
      documentName: 'Profiles document',
    );
    if (validated.sensitive != null) {
      dataApiObject(
        validated.sensitive,
        documentName: 'Sensitive profiles document',
      );
    }
    final decoded = TerminalProfilesDocument.fromJson(
      mergeDataApiObjects(data, validated.sensitive),
    );
    final canonical = encodeDataApiProfilesDocument(decoded);
    final canonicalSensitive = canonical.sensitive.isEmpty
        ? null
        : canonical.sensitive;
    if (decoded.schemaVersion !=
            TerminalProfilesDocument.currentSchemaVersion ||
        decoded.loadWarnings.isNotEmpty ||
        !dataApiJsonEquivalent(canonical.data, data) ||
        !dataApiJsonEquivalent(canonicalSensitive, validated.sensitive) ||
        validated.hasSensitive != (canonicalSensitive != null)) {
      throw const FormatException(
        'Profiles are not a canonical current-schema document.',
      );
    }
    return decoded;
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    throw StateError(
      'Data API profile writes require the VersionedDocument returned by '
      'loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> saveVersioned(
    VersionedDocument<TerminalProfilesDocument> document,
  ) async {
    final expectedRevision = requireDataApiRevision(document);
    final saved = await _put(
      document.value,
      expectedRevision: expectedRevision,
      clearSensitive: true,
    );
    return VersionedDocument<TerminalProfilesDocument>(
      value: document.value,
      revision: saved.revision,
    );
  }

  Future<DataApiResource> _put(
    TerminalProfilesDocument document, {
    required int expectedRevision,
    required bool clearSensitive,
  }) async {
    final payload = encodeDataApiProfilesDocument(document);
    final saved = await _client.putResource(
      kind: resourceKind,
      id: resourceId,
      data: payload.data,
      sensitive: payload.sensitive.isEmpty ? null : payload.sensitive,
      clearSensitive: payload.sensitive.isEmpty && clearSensitive,
      expectedRevision: expectedRevision,
    );
    return requireDataApiResourceIdentity(
      saved,
      kind: resourceKind,
      id: resourceId,
    );
  }

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) async {
    final resolver = _exportDirectoryResolver;
    if (resolver == null) {
      throw UnsupportedError(
        'Profile export requires an explicit local export directory.',
      );
    }
    final directory = await resolver();
    await directory.create(recursive: true);
    final safeBasename = _safeBasename(basename);
    final file = File(
      '${directory.path}/$safeBasename.ianvs-terminal-profiles.json',
    );
    await writeStringAtomically(file, document.encode());
    return file;
  }
}

String _safeBasename(String basename) {
  final safe = basename
      .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (safe.isEmpty || RegExp(r'^\.+$').hasMatch(safe)) {
    return 'ianvs-profiles';
  }
  return safe.length <= 120 ? safe : safe.substring(0, 120);
}

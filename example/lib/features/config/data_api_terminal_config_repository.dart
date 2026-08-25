import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../persistence/versioned_document.dart';
import 'local_terminal_config_models.dart';
import 'local_terminal_config_repository.dart';

final class DataApiTerminalConfigRepository extends TerminalConfigRepository
    implements TerminalConfigRecoveryRepository {
  DataApiTerminalConfigRepository({required DataApiResourceClient client})
    : _client = client;

  static const resourceKind = 'config';
  static const resourceId = 'local-terminal';
  static const recoveryResourceKind = 'recovery';
  static const recoveryDocumentFormat = 'ianvs-terminal-config-recovery-v1';
  static const _maximumUpdateAttempts = 3;

  final DataApiResourceClient _client;
  Future<void> _updateQueue = Future<void>.value();
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return (await loadVersioned()).value;
  }

  @override
  Future<VersionedDocument<LocalTerminalConfigDocument?>>
  loadVersioned() async {
    final resource = await _client.getResource(
      kind: resourceKind,
      id: resourceId,
    );
    if (resource == null) {
      return const VersionedDocument<LocalTerminalConfigDocument?>(
        value: null,
        revision: 0,
      );
    }
    return VersionedDocument<LocalTerminalConfigDocument?>(
      value: _decode(resource),
      revision: resource.revision,
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    throw StateError(
      'Data API terminal config writes require the VersionedDocument returned '
      'by loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<LocalTerminalConfigDocument>> saveVersioned(
    VersionedDocument<LocalTerminalConfigDocument> document,
  ) async {
    final expectedRevision = requireDataApiRevision(document);
    final saved = await _client.putResource(
      kind: resourceKind,
      id: resourceId,
      data: document.value.toJson(),
      expectedRevision: expectedRevision,
    );
    return VersionedDocument<LocalTerminalConfigDocument>(
      value: document.value,
      revision: saved.revision,
    );
  }

  @override
  Future<LocalTerminalConfigDocument> update(
    // The transform can be replayed after a remote revision conflict and must
    // therefore be pure (no I/O or externally visible side effects).
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) {
    final operation = _updateQueue.then((_) async {
      for (var attempt = 0; attempt < _maximumUpdateAttempts; attempt += 1) {
        final existing = await _client.getResource(
          kind: resourceKind,
          id: resourceId,
        );
        final current = existing == null ? fallback : _decode(existing);
        final next = transform(current);
        try {
          await _client.putResource(
            kind: resourceKind,
            id: resourceId,
            data: next.toJson(),
            expectedRevision: existing?.revision ?? 0,
          );
          return next;
        } on DataApiRevisionConflictException {
          if (attempt == _maximumUpdateAttempts - 1) {
            rethrow;
          }
        }
      }
      throw StateError('Unreachable terminal config update state.');
    });
    _updateQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<VersionedDocument<LocalTerminalConfigDocument>>
  repairNonCanonicalCurrentDocument() {
    final operation = _updateQueue.then((_) async {
      final existing = await _client.getResource(
        kind: resourceKind,
        id: resourceId,
      );
      if (existing == null) {
        throw StateError('There is no terminal config document to repair.');
      }
      final validated = requireDataApiResourceIdentity(
        existing,
        kind: resourceKind,
        id: resourceId,
      );
      if (validated.hasSensitive || validated.sensitive != null) {
        throw const FormatException(
          'Terminal config must not contain a sensitive payload.',
        );
      }
      final data = dataApiObject(
        validated.data,
        documentName: 'Terminal config',
      );
      final decoded = LocalTerminalConfigDocument.fromJson(data);
      final canonical = decoded.toJson();
      if (dataApiJsonEquivalent(canonical, data)) {
        throw StateError('The terminal config document is already canonical.');
      }

      final backupId = recoveryResourceIdForRevision(validated.revision);
      final backupData = <String, Object?>{
        'format': recoveryDocumentFormat,
        'resourceKind': resourceKind,
        'resourceId': resourceId,
        'resourceRevision': validated.revision,
        'sourceId': validated.sourceId,
        'sourceRevision': validated.sourceRevision,
        'sourceUpdatedAt': validated.sourceUpdatedAt.toIso8601String(),
        'data': deepCopyDataApiObject(data),
      };
      final existingBackup = await _client.getResource(
        kind: recoveryResourceKind,
        id: backupId,
      );
      if (existingBackup == null) {
        final savedBackup = await _client.putResource(
          kind: recoveryResourceKind,
          id: backupId,
          data: backupData,
          expectedRevision: 0,
        );
        requireDataApiResourceIdentity(
          savedBackup,
          kind: recoveryResourceKind,
          id: backupId,
        );
      } else {
        final validatedBackup = requireDataApiResourceIdentity(
          existingBackup,
          kind: recoveryResourceKind,
          id: backupId,
        );
        if (validatedBackup.hasSensitive ||
            validatedBackup.sensitive != null ||
            !dataApiJsonEquivalent(validatedBackup.data, backupData)) {
          throw const FormatException(
            'The terminal config recovery backup does not match the original '
            'document.',
          );
        }
      }

      final saved = await _client.putResource(
        kind: resourceKind,
        id: resourceId,
        data: canonical,
        expectedRevision: validated.revision,
      );
      requireDataApiResourceIdentity(saved, kind: resourceKind, id: resourceId);
      return VersionedDocument<LocalTerminalConfigDocument>(
        value: decoded,
        revision: saved.revision,
      );
    });
    _updateQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static String recoveryResourceIdForRevision(int revision) {
    if (revision <= 0) {
      throw RangeError.value(revision, 'revision', 'must be positive');
    }
    return 'terminal-config-local-terminal-r$revision';
  }

  LocalTerminalConfigDocument _decode(DataApiResource resource) {
    final validated = requireDataApiResourceIdentity(
      resource,
      kind: resourceKind,
      id: resourceId,
    );
    if (validated.hasSensitive || validated.sensitive != null) {
      throw const FormatException(
        'Terminal config must not contain a sensitive payload.',
      );
    }
    final data = dataApiObject(validated.data, documentName: 'Terminal config');
    final decoded = LocalTerminalConfigDocument.fromJson(data);
    if (!dataApiJsonEquivalent(decoded.toJson(), data)) {
      throw const NonCanonicalCurrentTerminalConfigException();
    }
    return decoded;
  }
}

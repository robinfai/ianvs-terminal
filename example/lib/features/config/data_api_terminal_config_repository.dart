import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../persistence/versioned_document.dart';
import 'local_terminal_config_models.dart';
import 'local_terminal_config_repository.dart';

final class DataApiTerminalConfigRepository extends TerminalConfigRepository {
  DataApiTerminalConfigRepository({required DataApiResourceClient client})
    : _client = client;

  static const resourceKind = 'config';
  static const resourceId = 'local-terminal';
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

  LocalTerminalConfigDocument _decode(DataApiResource resource) {
    return LocalTerminalConfigDocument.fromJson(
      dataApiObject(resource.data, documentName: 'Terminal config'),
    );
  }
}

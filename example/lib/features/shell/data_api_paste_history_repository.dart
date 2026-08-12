import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../persistence/versioned_document.dart';
import 'paste_history_repository.dart';

final class DataApiPasteHistoryRepository extends PasteHistoryRepositoryPort {
  DataApiPasteHistoryRepository({required DataApiResourceClient client})
    : _client = client;

  static const resourceKind = 'paste_history';
  static const resourceId = 'default';

  final DataApiResourceClient _client;
  @override
  Future<PasteHistoryDocument?> load() async {
    return (await loadVersioned()).value;
  }

  @override
  Future<VersionedDocument<PasteHistoryDocument?>> loadVersioned() async {
    final response = await _client.getResource(
      kind: resourceKind,
      id: resourceId,
      includeSensitive: true,
    );
    if (response == null) {
      return const VersionedDocument<PasteHistoryDocument?>(
        value: null,
        revision: 0,
      );
    }
    final resource = requireDataApiResourceIdentity(
      response,
      kind: resourceKind,
      id: resourceId,
    );
    final data = dataApiObject(
      resource.data,
      documentName: 'Paste history metadata',
    );
    if (!dataApiJsonEquivalent(data, const <String, Object?>{
      'format': 'ianvs-paste-history-v1',
    })) {
      throw const FormatException(
        'Paste history resource metadata is invalid.',
      );
    }
    if (!resource.hasSensitive || resource.sensitive == null) {
      if (resource.hasSensitive || resource.sensitive != null) {
        throw const FormatException(
          'Paste history sensitive envelope is inconsistent.',
        );
      }
      return VersionedDocument<PasteHistoryDocument?>(
        value: const PasteHistoryDocument(),
        revision: resource.revision,
      );
    }
    final sensitive = dataApiObject(
      resource.sensitive,
      documentName: 'Paste history',
    );
    final history = PasteHistoryDocument.fromJson(sensitive);
    if (!dataApiJsonEquivalent(history.toJson(), sensitive)) {
      throw const FormatException(
        'Paste history is not a canonical current-schema document.',
      );
    }
    return VersionedDocument<PasteHistoryDocument?>(
      value: history,
      revision: resource.revision,
    );
  }

  @override
  Future<void> save(PasteHistoryDocument document) async {
    throw StateError(
      'Data API paste-history writes require the VersionedDocument returned '
      'by loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<PasteHistoryDocument>> saveVersioned(
    VersionedDocument<PasteHistoryDocument> document,
  ) async {
    final expectedRevision = requireDataApiRevision(document);
    final saved = requireDataApiResourceIdentity(
      await _client.putResource(
        kind: resourceKind,
        id: resourceId,
        data: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
        sensitive: document.value.toJson(),
        expectedRevision: expectedRevision,
      ),
      kind: resourceKind,
      id: resourceId,
    );
    return VersionedDocument<PasteHistoryDocument>(
      value: document.value,
      revision: saved.revision,
    );
  }

  @override
  Future<void> clearDiskHistory() async {
    throw StateError(
      'Data API paste-history clears require the VersionedDocument returned '
      'by loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<PasteHistoryDocument>> clearDiskHistoryVersioned(
    VersionedDocument<PasteHistoryDocument?> document,
  ) async {
    final expectedRevision = requireDataApiRevision(document);
    final saved = requireDataApiResourceIdentity(
      await _client.putResource(
        kind: resourceKind,
        id: resourceId,
        data: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
        clearSensitive: true,
        expectedRevision: expectedRevision,
      ),
      kind: resourceKind,
      id: resourceId,
    );
    return VersionedDocument<PasteHistoryDocument>(
      value: const PasteHistoryDocument(),
      revision: saved.revision,
    );
  }
}

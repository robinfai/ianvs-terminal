import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../persistence/versioned_document.dart';
import 'app_preferences_models.dart';
import 'app_preferences_repository.dart';

final class DataApiAppPreferencesRepository
    extends AppPreferencesRepositoryPort {
  DataApiAppPreferencesRepository({required DataApiResourceClient client})
    : _client = client;

  static const resourceKind = 'config';
  static const resourceId = 'preferences';

  final DataApiResourceClient _client;
  @override
  Future<TerminalAppPreferencesDocument?> load() async {
    return (await loadVersioned()).value;
  }

  @override
  Future<VersionedDocument<TerminalAppPreferencesDocument?>>
  loadVersioned() async {
    final response = await _client.getResource(
      kind: resourceKind,
      id: resourceId,
    );
    if (response == null) {
      return const VersionedDocument<TerminalAppPreferencesDocument?>(
        value: null,
        revision: 0,
      );
    }
    final resource = requireDataApiResourceIdentity(
      response,
      kind: resourceKind,
      id: resourceId,
    );
    if (resource.hasSensitive || resource.sensitive != null) {
      throw const FormatException(
        'App preferences must not contain a sensitive payload.',
      );
    }
    final data = dataApiObject(resource.data, documentName: 'App preferences');
    final preferences = TerminalAppPreferencesDocument.fromJson(data);
    if (preferences.schemaVersion !=
            TerminalAppPreferencesDocument.currentSchemaVersion ||
        !dataApiJsonEquivalent(preferences.toJson(), data)) {
      throw const FormatException(
        'App preferences are not a canonical current-schema document.',
      );
    }
    return VersionedDocument<TerminalAppPreferencesDocument?>(
      value: preferences,
      revision: resource.revision,
    );
  }

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    throw StateError(
      'Data API preference writes require the VersionedDocument returned by '
      'loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<TerminalAppPreferencesDocument>> saveVersioned(
    VersionedDocument<TerminalAppPreferencesDocument> document,
  ) async {
    final expectedRevision = requireDataApiRevision(document);
    final saved = requireDataApiResourceIdentity(
      await _client.putResource(
        kind: resourceKind,
        id: resourceId,
        data: document.value.toJson(),
        expectedRevision: expectedRevision,
      ),
      kind: resourceKind,
      id: resourceId,
    );
    return VersionedDocument<TerminalAppPreferencesDocument>(
      value: document.value,
      revision: saved.revision,
    );
  }
}

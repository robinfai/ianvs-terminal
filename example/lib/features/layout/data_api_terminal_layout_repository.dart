import '../../data/repositories/data_api_repository_helpers.dart';
import '../../data/services/data_api_client.dart';
import '../persistence/versioned_document.dart';
import 'local_terminal_layout_models.dart';
import 'local_terminal_layout_repository.dart';

final class DataApiTerminalLayoutRepository extends TerminalLayoutRepository {
  DataApiTerminalLayoutRepository({required DataApiResourceClient client})
    : _client = client;

  static const resourceKind = 'session';
  static const resourceId = 'layout';

  final DataApiResourceClient _client;
  @override
  Future<TerminalLayout?> load() async {
    return (await loadVersioned()).value;
  }

  @override
  Future<VersionedDocument<TerminalLayout?>> loadVersioned() async {
    final response = await _client.getResource(
      kind: resourceKind,
      id: resourceId,
      includeSensitive: true,
    );
    if (response == null) {
      return const VersionedDocument<TerminalLayout?>(value: null, revision: 0);
    }
    final resource = requireDataApiResourceIdentity(
      response,
      kind: resourceKind,
      id: resourceId,
    );
    final data = dataApiObject(
      resource.data,
      documentName: 'Terminal layout metadata',
    );
    if (!dataApiJsonEquivalent(data, const <String, Object?>{
          'format': 'ianvs-terminal-layout-v1',
        }) ||
        !resource.hasSensitive ||
        resource.sensitive == null) {
      throw const FormatException(
        'Terminal layout resource envelope is invalid.',
      );
    }
    final sensitive = dataApiObject(
      resource.sensitive,
      documentName: 'Terminal layout',
    );
    final layout = TerminalLayout.fromJson(sensitive);
    if (!dataApiJsonEquivalent(layout.toJson(), sensitive)) {
      throw const FormatException(
        'Terminal layout is not a canonical current-schema document.',
      );
    }
    return VersionedDocument<TerminalLayout?>(
      value: layout,
      revision: resource.revision,
    );
  }

  @override
  Future<void> save(TerminalLayout layout) async {
    throw StateError(
      'Data API layout writes require the VersionedDocument returned by '
      'loadVersioned().',
    );
  }

  @override
  Future<VersionedDocument<TerminalLayout>> saveVersioned(
    VersionedDocument<TerminalLayout> layout,
  ) async {
    final expectedRevision = requireDataApiRevision(layout);
    try {
      final saved = requireDataApiResourceIdentity(
        await _client.putResource(
          kind: resourceKind,
          id: resourceId,
          data: const <String, Object?>{'format': 'ianvs-terminal-layout-v1'},
          sensitive: layout.value.toJson(),
          expectedRevision: expectedRevision,
        ),
        kind: resourceKind,
        id: resourceId,
      );
      return VersionedDocument<TerminalLayout>(
        value: layout.value,
        revision: saved.revision,
      );
    } on DataApiTimeoutException catch (error) {
      try {
        final observed = await loadVersioned();
        final observedLayout = observed.value;
        if (observedLayout != null &&
            dataApiJsonEquivalent(
              observedLayout.toJson(),
              layout.value.toJson(),
            )) {
          return VersionedDocument<TerminalLayout>(
            value: observedLayout,
            revision: observed.revision,
          );
        }
      } on DataApiTimeoutException {
        // The verification request also timed out. The latest layout remains
        // queued by the controller for retry.
      }
      throw TerminalLayoutSaveUnavailableException(error);
    } on DataApiRevisionConflictException {
      final observed = await loadVersioned();
      final observedLayout = observed.value;
      if (observedLayout != null &&
          dataApiJsonEquivalent(
            observedLayout.toJson(),
            layout.value.toJson(),
          )) {
        return VersionedDocument<TerminalLayout>(
          value: observedLayout,
          revision: observed.revision,
        );
      }
      rethrow;
    }
  }
}

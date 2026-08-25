import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../configuration/data_api_configuration.dart';
import 'data_api_auth_contract.dart';
import 'data_api_runtime.dart';
import 'data_api_sensitive_cipher.dart';

abstract interface class DataApiResourceClient {
  bool get canAccessResources;

  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = DataApiClient.maximumPageSize,
    String? cursor,
  });

  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  });

  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  });

  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  });

  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  });
}

enum DataApiMigrationConflictPolicy {
  preserveDestination('preserve_destination'),
  sourceWins('source_wins');

  const DataApiMigrationConflictPolicy(this.wireValue);

  final String wireValue;
}

abstract interface class DataApiMigrationClient {
  Future<DataApiMigrationExportPage> exportMigrationPage({String? cursor});

  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  });
}

final class DataApiResourcePage {
  const DataApiResourcePage({
    required this.resources,
    required this.nextCursor,
  });

  final List<DataApiResource> resources;
  final String? nextCursor;
}

final class DataApiMigrationExportPage {
  const DataApiMigrationExportPage({
    required this.sourceId,
    required this.resources,
    required this.nextCursor,
  });

  final String sourceId;
  final List<DataApiMigrationResource> resources;
  final String? nextCursor;
}

final class DataApiResource {
  factory DataApiResource({
    required String id,
    required String kind,
    required Object? data,
    required Object? sensitive,
    required bool hasSensitive,
    required int revision,
    required String sourceId,
    required int sourceRevision,
    required DateTime sourceUpdatedAt,
    required bool deleted,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    if (id.isEmpty || kind.isEmpty || revision <= 0 || sourceRevision <= 0) {
      throw ArgumentError('Invalid Data API resource model.');
    }
    return DataApiResource._(
      id: id,
      kind: kind,
      data: data,
      sensitive: sensitive,
      hasSensitive: hasSensitive,
      revision: revision,
      sourceId: sourceId,
      sourceRevision: sourceRevision,
      sourceUpdatedAt: sourceUpdatedAt.toUtc(),
      deleted: deleted,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  const DataApiResource._({
    required this.id,
    required this.kind,
    required this.data,
    required this.sensitive,
    required this.hasSensitive,
    required this.revision,
    required this.sourceId,
    required this.sourceRevision,
    required this.sourceUpdatedAt,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DataApiResource.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final kind = json['kind'];
    final revision = json['revision'];
    final sourceId = json['source_id'];
    final sourceRevision = json['source_revision'];
    final sourceUpdatedAt = _parseRfc3339(json['source_updated_at']);
    final deleted = json['deleted'];
    final hasSensitive = json['has_sensitive'];
    final createdAt = _parseRfc3339(json['created_at']);
    final updatedAt = _parseRfc3339(json['updated_at']);
    if (id is! String ||
        id.isEmpty ||
        kind is! String ||
        kind.isEmpty ||
        !json.containsKey('data') ||
        revision is! num ||
        revision <= 0 ||
        revision.toInt() != revision ||
        sourceId is! String ||
        sourceRevision is! num ||
        sourceRevision <= 0 ||
        sourceRevision.toInt() != sourceRevision ||
        sourceUpdatedAt == null ||
        hasSensitive is! bool ||
        deleted is! bool ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Invalid Data API resource response.');
    }
    return DataApiResource(
      id: id,
      kind: kind,
      data: json['data'],
      sensitive: json['sensitive'],
      hasSensitive: hasSensitive,
      revision: revision.toInt(),
      sourceId: sourceId,
      sourceRevision: sourceRevision.toInt(),
      sourceUpdatedAt: sourceUpdatedAt,
      deleted: deleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  final String id;
  final String kind;
  final Object? data;
  final Object? sensitive;
  final bool hasSensitive;
  final int revision;
  final String sourceId;
  final int sourceRevision;
  final DateTime sourceUpdatedAt;
  final bool deleted;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class DataApiMigrationResource {
  const DataApiMigrationResource({
    required this.id,
    required this.kind,
    required this.data,
    required this.sourceRevision,
    required this.sourceUpdatedAt,
    this.sensitive,
  });

  final String id;
  final String kind;
  final Object? data;
  final Object? sensitive;
  final int sourceRevision;
  final DateTime sourceUpdatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'data': data,
    if (sensitive != null) 'sensitive': sensitive,
    'has_sensitive': sensitive != null,
    'revision': 1,
    'source_id': '',
    'source_revision': sourceRevision,
    'source_updated_at': sourceUpdatedAt.toUtc().toIso8601String(),
    'deleted': false,
    'created_at': sourceUpdatedAt.toUtc().toIso8601String(),
    'updated_at': sourceUpdatedAt.toUtc().toIso8601String(),
  };
}

final class DataApiMigrationMergeItem {
  const DataApiMigrationMergeItem({
    required this.kind,
    required this.id,
    required this.status,
    this.reason,
  });

  final String kind;
  final String id;
  final String status;
  final String? reason;
}

final class DataApiMigrationMergeReport {
  const DataApiMigrationMergeReport({required this.results});

  final List<DataApiMigrationMergeItem> results;
}

final class DataApiLoginResult {
  const DataApiLoginResult({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;
}

final class DataApiPreparedAuthOperation {
  const DataApiPreparedAuthOperation({
    required this.operationId,
    required this.expiresAt,
  });

  final String operationId;
  final DateTime expiresAt;
}

final class DataApiAuthenticationRequiredException implements Exception {
  const DataApiAuthenticationRequiredException();

  @override
  String toString() {
    return 'The selected remote Data API requires an authenticated session. '
        'Local JSON persistence is intentionally not used as a fallback.';
  }
}

final class DataApiProtocolException implements Exception {
  const DataApiProtocolException(this.message);

  final String message;

  @override
  String toString() => 'Invalid Data API response: $message';
}

final class DataApiResponseTooLargeException implements Exception {
  const DataApiResponseTooLargeException(this.maximumBytes);

  final int maximumBytes;

  @override
  String toString() {
    return 'The Data API response exceeded the $maximumBytes byte limit.';
  }
}

final class DataApiRequestTooLargeException implements Exception {
  const DataApiRequestTooLargeException(this.maximumBytes);

  final int maximumBytes;

  @override
  String toString() {
    return 'The Data API request exceeded the $maximumBytes byte limit.';
  }
}

final class DataApiTimeoutException implements Exception {
  const DataApiTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'The Data API request timed out after $timeout.';
}

class DataApiRequestException implements Exception {
  const DataApiRequestException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'Data API request failed ($statusCode/$code): $message';
}

final class DataApiRevisionConflictException extends DataApiRequestException {
  const DataApiRevisionConflictException({required super.message})
    : super(statusCode: HttpStatus.conflict, code: 'revision_conflict');
}

typedef DataApiHttpClientFactory = HttpClient Function();

final class DataApiClient
    implements DataApiResourceClient, DataApiMigrationClient {
  DataApiClient({
    required Uri baseUri,
    required String? accessToken,
    required String? encryptionKey,
    DataApiHttpClientFactory? httpClientFactory,
    DataApiSensitiveCipher? sensitiveCipher,
    Uri? handshakeFallbackBaseUri,
    this.connectionTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 15),
    this.maximumResponseBytes = maximumJsonResponseBytes,
    this.maximumRequestBytes = maximumJsonRequestBytes,
  }) : baseUri = _normalizeBaseUri(baseUri),
       _accessToken = _nonEmpty(accessToken),
       _encryptionKey = _nonEmpty(encryptionKey),
       _sensitiveCipher = sensitiveCipher ?? DataApiSensitiveCipher(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _handshakeFallbackBaseUri = _resolveHandshakeFallbackBaseUri(
         baseUri,
         handshakeFallbackBaseUri,
       ) {
    if (connectionTimeout <= Duration.zero ||
        requestTimeout <= Duration.zero ||
        maximumResponseBytes <= 0 ||
        maximumRequestBytes <= 0) {
      throw ArgumentError(
        'Data API timeout and response limits must be positive.',
      );
    }
  }

  factory DataApiClient.fromRuntime(
    DataApiRuntime runtime, {
    DataApiHttpClientFactory? httpClientFactory,
  }) {
    return DataApiClient(
      baseUri: runtime.baseUri,
      accessToken: runtime.resourceAccessToken,
      encryptionKey: runtime.encryptionKey,
      httpClientFactory: httpClientFactory,
    );
  }

  final Uri baseUri;
  final String? _accessToken;
  final String? _encryptionKey;
  final DataApiSensitiveCipher _sensitiveCipher;
  final DataApiHttpClientFactory _httpClientFactory;
  final Uri? _handshakeFallbackBaseUri;
  final Duration connectionTimeout;
  final Duration requestTimeout;
  final int maximumResponseBytes;
  final int maximumRequestBytes;
  Future<String>? _ownerIdFuture;

  static const int maximumPageSize = 100;
  static const int maximumCursorBytes = 1024;
  static const int maximumJsonResponseBytes = 12 * 1024 * 1024;
  static const int maximumJsonRequestBytes = 12 * 1024 * 1024;

  @override
  bool get canAccessResources => _accessToken != null;

  Future<void> validateAccess() async {
    await _authenticatedOwnerId();
  }

  Future<void> logout() async {
    await _request(
      'POST',
      _resourceUri('v1/auth/logout'),
      acceptedStatusCodes: const <int>{HttpStatus.noContent},
    );
  }

  /// Verifies bearer authentication only. Encryption keys are never sent to
  /// or verified by the Data API.
  Future<void> validateSession() => validateAccess();

  /// Verifies ephemeral credentials and creates a short-lived server-side
  /// operation without issuing an access token.
  Future<DataApiPreparedAuthOperation> beginLogin({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = normalizeDataApiUsername(username);
    final validatedPassword = validateDataApiPassword(password);
    final response = await _request(
      'POST',
      _resourceUri('v1/auth/login/begin'),
      requireAuthentication: false,
      jsonBody: <String, String>{
        'username': normalizedUsername,
        'password': validatedPassword,
      },
    );
    final root = _jsonObject(
      response.body,
      documentName: 'login begin response',
    );
    final operationId = _stringValue(root['operation_id']);
    final rawExpiresAt = _stringValue(root['expires_at']);
    final expiresAt = rawExpiresAt == null
        ? null
        : DateTime.tryParse(rawExpiresAt);
    if (operationId == null || expiresAt == null || root['kind'] != 'login') {
      throw const DataApiProtocolException(
        'login begin response is missing operation_id, expires_at, or kind.',
      );
    }
    return DataApiPreparedAuthOperation(
      operationId: validateDataApiAuthOperationId(operationId),
      expiresAt: expiresAt.toUtc(),
    );
  }

  /// Completes a previously persisted server-issued login operation and
  /// returns the newly issued access token.
  Future<DataApiLoginResult> completeLogin(String operationId) async {
    final response = await _request(
      'POST',
      _resourceUri('v1/auth/login/complete'),
      requireAuthentication: false,
      jsonBody: <String, String>{
        'operation_id': validateDataApiAuthOperationId(operationId),
      },
    );
    final root = _jsonObject(
      response.body,
      documentName: 'login complete response',
    );
    final token = _nonEmpty(_stringValue(root['token']));
    final rawExpiresAt = _stringValue(root['expires_at']);
    final expiresAt = rawExpiresAt == null
        ? null
        : DateTime.tryParse(rawExpiresAt);
    if (token == null || expiresAt == null) {
      throw const DataApiProtocolException(
        'login response is missing token or expires_at.',
      );
    }
    return DataApiLoginResult(accessToken: token, expiresAt: expiresAt.toUtc());
  }

  Future<void> cancelAuthOperation(String operationId) async {
    await _request(
      'POST',
      _resourceUri('v1/auth/cancel-operation'),
      requireAuthentication: false,
      jsonBody: <String, String>{
        'operation_id': validateDataApiAuthOperationId(operationId),
      },
      acceptedStatusCodes: const <int>{HttpStatus.noContent},
    );
  }

  @override
  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = maximumPageSize,
    String? cursor,
  }) async {
    if (limit < 1 || limit > maximumPageSize) {
      throw RangeError.range(limit, 1, maximumPageSize, 'limit');
    }
    final normalizedCursor = _nonEmpty(cursor);
    if (normalizedCursor != null &&
        utf8.encode(normalizedCursor).length > maximumCursorBytes) {
      throw const DataApiProtocolException(
        'resource cursor exceeds the 1024-byte limit.',
      );
    }
    final query = <String, String>{
      if (includeSensitive) 'include_sensitive': 'true',
      'limit': limit.toString(),
      'cursor': ?normalizedCursor,
    };
    final normalizedKind = _nonEmpty(kind);
    if (normalizedKind != null) {
      query['kind'] = normalizedKind;
    }
    final response = await _request(
      'GET',
      _resourceUri(
        'v1/resources',
      ).replace(queryParameters: query.isEmpty ? null : query),
    );
    final root = _jsonObject(response.body, documentName: 'resource list');
    final resources = root['resources'];
    if (resources is! List) {
      throw const FormatException(
        'Data API resource list is missing resources.',
      );
    }
    final decodedResources = await Future.wait(
      resources.map(
        (value) => _decodeResource(
          _jsonObject(value, documentName: 'resource'),
          decryptSensitive: includeSensitive,
        ),
      ),
    );
    final rawNextCursor = root['next_cursor'];
    final nextCursor = _nonEmpty(_stringValue(rawNextCursor));
    if (rawNextCursor != null &&
        (nextCursor == null ||
            utf8.encode(nextCursor).length > maximumCursorBytes)) {
      throw const DataApiProtocolException(
        'resource list has an invalid next_cursor.',
      );
    }
    return DataApiResourcePage(
      resources: decodedResources,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async {
    final uri =
        _resourceUri(
          'v1/resources/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}',
        ).replace(
          queryParameters: includeSensitive
              ? const <String, String>{'include_sensitive': 'true'}
              : null,
        );
    final response = await _request(
      'GET',
      uri,
      acceptedStatusCodes: const <int>{HttpStatus.ok, HttpStatus.notFound},
    );
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    return _requireRequestedResource(
      await _decodeResource(
        _jsonObject(response.body, documentName: 'resource'),
        decryptSensitive: includeSensitive,
      ),
      requestedKind: kind,
      requestedId: id,
    );
  }

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) async {
    if (sensitive != null && clearSensitive) {
      throw ArgumentError(
        'sensitive and clearSensitive cannot be used together.',
      );
    }
    final body = <String, Object?>{'data': data};
    if (sensitive != null) {
      body['sensitive'] = await _encryptSensitive(
        kind: kind,
        id: id,
        cleartext: sensitive,
      );
    }
    if (clearSensitive) {
      body['clear_sensitive'] = true;
    }
    if (expectedRevision != null) {
      body['expected_revision'] = expectedRevision;
    }
    final response = await _request(
      'PUT',
      _resourceUri(
        'v1/resources/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}',
      ),
      jsonBody: body,
    );
    return _requireRequestedResource(
      await _decodeResource(
        _jsonObject(response.body, documentName: 'resource'),
        decryptSensitive: sensitive != null,
      ),
      requestedKind: kind,
      requestedId: id,
    );
  }

  @override
  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  }) async {
    final response = await _request(
      'DELETE',
      _resourceUri(
        'v1/resources/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}',
      ).replace(
        queryParameters: expectedRevision == null
            ? null
            : <String, String>{
                'expected_revision': expectedRevision.toString(),
              },
      ),
      acceptedStatusCodes: const <int>{
        HttpStatus.noContent,
        HttpStatus.notFound,
      },
    );
    return response.statusCode == HttpStatus.noContent;
  }

  @override
  Future<DataApiMigrationExportPage> exportMigrationPage({
    String? cursor,
  }) async {
    if (cursor != null && cursor.length > maximumCursorBytes) {
      throw RangeError.range(
        cursor.length,
        0,
        maximumCursorBytes,
        'cursor.length',
      );
    }
    final response = await _request(
      'GET',
      _resourceUri('v1/migrations/export').replace(
        queryParameters: <String, String>{
          'include_deleted': 'false',
          'include_sensitive': 'true',
          'limit': maximumPageSize.toString(),
          'cursor': ?cursor,
        },
      ),
    );
    final root = _jsonObject(response.body, documentName: 'migration export');
    if (root['schema_version'] != 1) {
      throw const FormatException(
        'Unsupported Data API migration export schema.',
      );
    }
    final sourceId = _nonEmpty(_stringValue(root['source_id']));
    final rawResources = root['resources'];
    final nextCursor = _nonEmpty(_stringValue(root['next_cursor']));
    if (sourceId == null || rawResources is! List) {
      throw const FormatException('Invalid Data API migration export.');
    }
    final decodedResources = await Future.wait(
      rawResources.map((value) async {
        final resource = await _decodeResource(
          _jsonObject(value, documentName: 'migration resource'),
          decryptSensitive: true,
        );
        if (resource.deleted) {
          throw const FormatException(
            'Migration export unexpectedly included a deleted resource.',
          );
        }
        return DataApiMigrationResource(
          id: resource.id,
          kind: resource.kind,
          data: resource.data,
          sensitive: resource.sensitive,
          sourceRevision: resource.sourceRevision,
          sourceUpdatedAt: resource.sourceUpdatedAt,
        );
      }),
    );
    return DataApiMigrationExportPage(
      sourceId: sourceId,
      resources: decodedResources,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async {
    final encodedResources = await Future.wait(
      resources.map((resource) async {
        final encoded = resource.toJson();
        if (resource.sensitive != null) {
          encoded['sensitive'] = await _encryptSensitive(
            kind: resource.kind,
            id: resource.id,
            cleartext: resource.sensitive,
          );
        }
        return encoded;
      }),
    );
    final response = await _request(
      'POST',
      _resourceUri('v1/migrations/merge'),
      jsonBody: <String, Object?>{
        'schema_version': 1,
        'source_id': sourceId,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'conflict_policy': conflictPolicy.wireValue,
        'propagate_deletes': false,
        'resources': encodedResources,
      },
    );
    final root = _jsonObject(response.body, documentName: 'migration report');
    final rawResults = root['results'];
    if (rawResults is! List) {
      throw const FormatException(
        'Data API migration report is missing results.',
      );
    }
    return DataApiMigrationMergeReport(
      results: rawResults
          .map((value) {
            final result = _jsonObject(value, documentName: 'migration result');
            final kind = _stringValue(result['kind']);
            final id = _stringValue(result['id']);
            final status = _stringValue(result['status']);
            final reason = _stringValue(result['reason']);
            if (kind == null ||
                id == null ||
                !const <String>{
                  'created',
                  'updated',
                  'deleted',
                  'skipped',
                  'conflict',
                }.contains(status)) {
              throw const FormatException('Invalid Data API migration result.');
            }
            return DataApiMigrationMergeItem(
              kind: kind,
              id: id,
              status: status!,
              reason: reason,
            );
          })
          .toList(growable: false),
    );
  }

  Future<String> _authenticatedOwnerId() {
    return _ownerIdFuture ??= _loadAuthenticatedOwnerId();
  }

  Future<String> _loadAuthenticatedOwnerId() async {
    final response = await _request('GET', _resourceUri('v1/me'));
    final root = _jsonObject(response.body, documentName: 'authenticated user');
    final user = _jsonObject(root['user'], documentName: 'authenticated user');
    final ownerId = _nonEmpty(_stringValue(user['id']));
    if (ownerId == null) {
      throw const DataApiProtocolException(
        'authenticated user response is missing user.id.',
      );
    }
    return ownerId;
  }

  String _requireEncryptionKey() {
    return _encryptionKey ??
        (throw const DataApiEncryptionKeyRequiredException());
  }

  Future<Map<String, Object?>> _encryptSensitive({
    required String kind,
    required String id,
    required Object? cleartext,
  }) async {
    return _sensitiveCipher.encrypt(
      masterKey: _requireEncryptionKey(),
      ownerId: await _authenticatedOwnerId(),
      kind: kind,
      id: id,
      cleartext: cleartext,
    );
  }

  Future<DataApiResource> _decodeResource(
    Map<String, Object?> json, {
    required bool decryptSensitive,
  }) async {
    final wireResource = DataApiResource.fromJson(json);
    if (!decryptSensitive || wireResource.sensitive == null) {
      if (decryptSensitive && wireResource.hasSensitive) {
        throw const DataApiProtocolException(
          'resource omitted its requested sensitive envelope.',
        );
      }
      return wireResource;
    }
    final cleartext = await _sensitiveCipher.decrypt(
      masterKey: _requireEncryptionKey(),
      ownerId: await _authenticatedOwnerId(),
      kind: wireResource.kind,
      id: wireResource.id,
      envelope: wireResource.sensitive,
    );
    return DataApiResource(
      id: wireResource.id,
      kind: wireResource.kind,
      data: wireResource.data,
      sensitive: cleartext,
      hasSensitive: wireResource.hasSensitive,
      revision: wireResource.revision,
      sourceId: wireResource.sourceId,
      sourceRevision: wireResource.sourceRevision,
      sourceUpdatedAt: wireResource.sourceUpdatedAt,
      deleted: wireResource.deleted,
      createdAt: wireResource.createdAt,
      updatedAt: wireResource.updatedAt,
    );
  }

  Uri _resourceUri(String relativePath) => baseUri.resolve(relativePath);

  Future<({int statusCode, Object? body})> _request(
    String method,
    Uri uri, {
    bool requireAuthentication = true,
    Object? jsonBody,
    Set<int>? acceptedStatusCodes,
  }) async {
    final accessToken = _accessToken;
    if (requireAuthentication && accessToken == null) {
      throw const DataApiAuthenticationRequiredException();
    }
    try {
      return await _requestOnce(
        method,
        uri,
        accessToken: accessToken,
        jsonBody: jsonBody,
        acceptedStatusCodes: acceptedStatusCodes,
      );
    } on HandshakeException {
      final fallbackUri = _handshakeFallbackUri(uri);
      if (fallbackUri == null) {
        rethrow;
      }
      // A TLS handshake failure occurs before an HTTP request can be sent, so
      // retrying even a mutating request cannot duplicate a server operation.
      return _requestOnce(
        method,
        fallbackUri,
        accessToken: accessToken,
        jsonBody: jsonBody,
        acceptedStatusCodes: acceptedStatusCodes,
      );
    }
  }

  Uri? _handshakeFallbackUri(Uri uri) {
    final fallbackBaseUri = _handshakeFallbackBaseUri;
    if (fallbackBaseUri == null ||
        uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        uri.port != baseUri.port ||
        !uri.path.startsWith(baseUri.path)) {
      return null;
    }
    final relativePath = uri.path.substring(baseUri.path.length);
    return fallbackBaseUri
        .resolve(relativePath)
        .replace(query: uri.hasQuery ? uri.query : null);
  }

  Future<({int statusCode, Object? body})> _requestOnce(
    String method,
    Uri uri, {
    required String? accessToken,
    required Object? jsonBody,
    required Set<int>? acceptedStatusCodes,
  }) async {
    final client = _httpClientFactory();
    client.connectionTimeout = connectionTimeout;
    try {
      return await _performRequest(
        client,
        method,
        uri,
        accessToken: accessToken,
        jsonBody: jsonBody,
        acceptedStatusCodes: acceptedStatusCodes,
      ).timeout(
        requestTimeout,
        onTimeout: () => throw DataApiTimeoutException(requestTimeout),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<({int statusCode, Object? body})> _performRequest(
    HttpClient client,
    String method,
    Uri uri, {
    required String? accessToken,
    required Object? jsonBody,
    required Set<int>? acceptedStatusCodes,
  }) async {
    List<int>? encodedJsonBody;
    if (jsonBody != null) {
      try {
        encodedJsonBody = utf8.encode(jsonEncode(jsonBody));
      } on JsonUnsupportedObjectError catch (error) {
        throw DataApiProtocolException(
          'request body is not JSON-serializable: $error',
        );
      }
      if (encodedJsonBody.length > maximumRequestBytes) {
        throw DataApiRequestTooLargeException(maximumRequestBytes);
      }
    }
    final request = await client.openUrl(method, uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    if (accessToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    if (encodedJsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.contentLength = encodedJsonBody.length;
      request.add(encodedJsonBody);
    }
    final response = await request.close();
    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in response) {
      byteCount += chunk.length;
      if (byteCount > maximumResponseBytes) {
        throw DataApiResponseTooLargeException(maximumResponseBytes);
      }
      bytes.add(chunk);
    }
    Object? body;
    if (byteCount != 0) {
      try {
        final rawBody = utf8.decode(bytes.takeBytes(), allowMalformed: false);
        body = jsonDecode(rawBody);
      } on FormatException catch (error) {
        throw DataApiProtocolException(error.message);
      }
    }
    final accepted =
        acceptedStatusCodes ?? const <int>{HttpStatus.ok, HttpStatus.created};
    if (!accepted.contains(response.statusCode)) {
      throw _requestException(response.statusCode, body);
    }
    return (statusCode: response.statusCode, body: body);
  }
}

DataApiRequestException _requestException(int statusCode, Object? body) {
  final root = _objectMap(body);
  final error = _objectMap(root?['error']);
  final code = _nonEmpty(_stringValue(error?['code'])) ?? 'http_error';
  final message =
      _nonEmpty(_stringValue(error?['message'])) ??
      'The Data API returned HTTP $statusCode.';
  if (statusCode == HttpStatus.conflict && code == 'revision_conflict') {
    return DataApiRevisionConflictException(message: message);
  }
  return DataApiRequestException(
    statusCode: statusCode,
    code: code,
    message: message,
  );
}

DataApiResource _requireRequestedResource(
  DataApiResource resource, {
  required String requestedKind,
  required String requestedId,
}) {
  if (resource.kind != requestedKind ||
      resource.id != requestedId ||
      resource.deleted) {
    throw const DataApiProtocolException(
      'resource identity or tombstone state does not match the request.',
    );
  }
  return resource;
}

final RegExp _rfc3339DateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})'
  r'(?:\.\d+)?(?:[Zz]|([+-])(\d{2}):(\d{2}))$',
);

DateTime? _parseRfc3339(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = _rfc3339DateTimePattern.firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final offsetHour = match[8] == null ? 0 : int.parse(match[8]!);
  final offsetMinute = match[9] == null ? 0 : int.parse(match[9]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

Map<String, Object?> _jsonObject(
  Object? value, {
  required String documentName,
}) {
  final mapped = _objectMap(value);
  if (mapped == null) {
    throw FormatException('Data API $documentName must be a JSON object.');
  }
  return mapped;
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map(
    (key, entryValue) => MapEntry(key.toString(), entryValue as Object?),
  );
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _stringValue(Object? value) => value is String ? value : null;

Uri? _resolveHandshakeFallbackBaseUri(
  Uri primaryBaseUri,
  Uri? configuredFallbackBaseUri,
) {
  final normalizedPrimary = _normalizeBaseUri(primaryBaseUri);
  final candidate =
      configuredFallbackBaseUri ??
      (normalizedPrimary.toString() == defaultRemoteDataApiBaseUrl
          ? Uri.parse(fallbackRemoteDataApiTransportBaseUrl)
          : null);
  if (candidate == null) {
    return null;
  }
  final normalizedFallback = _normalizeBaseUri(candidate);
  if (!isSecureDataApiRemoteOrigin(normalizedFallback)) {
    throw FormatException(
      'The Data API handshake fallback must use HTTPS, except for a '
      'loopback development endpoint.',
      candidate,
    );
  }
  if (normalizedFallback == normalizedPrimary) {
    throw ArgumentError.value(
      candidate,
      'handshakeFallbackBaseUri',
      'The handshake fallback must differ from the primary Data API URL.',
    );
  }
  return normalizedFallback;
}

Uri _normalizeBaseUri(Uri value) {
  if (!value.hasScheme ||
      !value.hasAuthority ||
      (value.scheme != 'http' && value.scheme != 'https') ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.query.isNotEmpty ||
      value.fragment.isNotEmpty) {
    throw FormatException(
      'The Data API base URL must be an http(s) URL without credentials, '
      'query, or fragment.',
      value,
    );
  }
  final path = value.path.isEmpty
      ? '/'
      : value.path.endsWith('/')
      ? value.path
      : '${value.path}/';
  return value.replace(path: path);
}

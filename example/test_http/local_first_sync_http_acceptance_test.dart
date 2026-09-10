import 'dart:convert';
import 'dart:io';

import 'package:app/data/repositories/data_api_repository_helpers.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/sync/json_three_way_merge.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

const _apiUrl = String.fromEnvironment('IANVS_LOCAL_FIRST_HTTP_API_URL');
const _username = String.fromEnvironment('IANVS_LOCAL_FIRST_HTTP_USERNAME');
const _password = String.fromEnvironment('IANVS_LOCAL_FIRST_HTTP_PASSWORD');
const _encryptionKey = String.fromEnvironment(
  'IANVS_LOCAL_FIRST_HTTP_ENCRYPTION_KEY',
);
const _resourceKind = 'profile';
const _resourceId = 'local-first-http';
const _resourceKey = '$_resourceKind/$_resourceId';
const _secretMarker = 'real-http-secret-marker';

void main() {
  group(LocalFirstSyncCoordinator, () {
    late Uri baseUri;
    late _IssuedSession firstSession;
    late _IssuedSession secondSession;
    late DataApiClient firstClient;
    late DataApiClient secondClient;
    late _Device first;
    late _Device second;
    late List<_Device> openedDevices;
    late List<String> issuedOperationIds;

    setUp(() async {
      openedDevices = <_Device>[];
      issuedOperationIds = <String>[];
      baseUri = _validatedFixtureUri();
      firstSession = await _register(baseUri);
      issuedOperationIds.add(firstSession.operationId);
      secondSession = await _login(baseUri);
      issuedOperationIds.add(secondSession.operationId);
      firstClient = _client(baseUri, firstSession.token);
      secondClient = _client(baseUri, secondSession.token);
      first = await _Device.create(
        label: 'first',
        client: firstClient,
        destination: firstSession.syncIdentity(baseUri),
        initial: _document(
          public: <String, Object?>{
            'shared': 'base',
            'firstOnly': 'first-initial',
          },
          secret: <String, Object?>{'password': _secretMarker},
        ),
      );
      openedDevices.add(first);
      second = await _Device.create(
        label: 'second',
        client: secondClient,
        destination: secondSession.syncIdentity(baseUri),
        initial: _document(
          public: <String, Object?>{
            'shared': 'base',
            'secondOnly': 'second-initial',
          },
          secret: const <String, Object?>{
            'privateKey': 'second-device-private-key-marker',
          },
        ),
      );
      openedDevices.add(second);
    });

    tearDown(() async {
      for (final device in openedDevices.reversed) {
        await device.close();
      }
      for (final operationId in issuedOperationIds) {
        await _bestEffortCancel(baseUri, operationId);
      }
    });

    test(
      'merges two clients and recovers conflicts, outages, 401, and disablement',
      () async {
        expect(
          firstSession.syncIdentity(baseUri),
          secondSession.syncIdentity(baseUri),
        );

        await first.sync.synchronize();
        await second.sync.synchronize();
        await first.sync.synchronize();
        _expectPublic(first.value, <String, Object?>{
          'shared': 'base',
          'firstOnly': 'first-initial',
          'secondOnly': 'second-initial',
        });
        expect(_secret(first.value, 'password'), _secretMarker);
        expect(
          _secret(first.value, 'privateKey'),
          'second-device-private-key-marker',
        );

        final stored = await firstClient.getResource(
          kind: _resourceKind,
          id: _resourceId,
        );
        expect(stored, isNotNull);
        expect(stored!.hasSensitive, isTrue);
        expect(stored.sensitive, isNull);
        expect(jsonEncode(stored.data), isNot(contains(_secretMarker)));
        final encryptedResponse = await _rawGet(
          baseUri.resolve(
            'v1/resources/$_resourceKind/$_resourceId?include_sensitive=true',
          ),
          token: firstSession.token,
        );
        expect(encryptedResponse, contains('"ciphertext"'));
        expect(encryptedResponse, isNot(contains(_secretMarker)));
        expect(
          encryptedResponse,
          isNot(contains('second-device-private-key-marker')),
        );
        final decrypted = await firstClient.getResource(
          kind: _resourceKind,
          id: _resourceId,
          includeSensitive: true,
        );
        final decryptedDocument = mergeDataApiObjects(
          dataApiObject(
            decrypted!.data,
            documentName: 'Decrypted public acceptance resource',
          ),
          dataApiObject(
            decrypted.sensitive,
            documentName: 'Decrypted sensitive acceptance resource',
          ),
        );
        expect(_secret(decryptedDocument, 'password'), _secretMarker);

        await first.updatePublic('firstField', 'changed-by-first');
        await second.updatePublic('secondField', 'changed-by-second');
        await first.sync.synchronize();
        await second.sync.synchronize();
        await first.sync.synchronize();
        _expectPublicValue(first.value, 'firstField', 'changed-by-first');
        _expectPublicValue(first.value, 'secondField', 'changed-by-second');
        _expectPublicValue(second.value, 'firstField', 'changed-by-first');

        await first.updatePublic('shared', 'remote-first');
        await second.updatePublic('shared', 'preferred-local-second');
        await first.sync.synchronize();
        await second.sync.synchronize();
        expect(second.sync.phase, LocalFirstSyncPhase.conflict);
        expect(second.sync.conflicts[_resourceKey], contains('/public/shared'));
        await second.sync.synchronize(
          resolution: JsonConflictResolution.preferLocal,
        );
        await first.sync.synchronize();
        _expectPublicValue(first.value, 'shared', 'preferred-local-second');

        await first.updatePublic('shared', 'preferred-remote-first');
        await second.updatePublic('shared', 'discarded-second');
        await first.sync.synchronize();
        await second.sync.synchronize();
        expect(second.sync.phase, LocalFirstSyncPhase.conflict);
        await second.sync.synchronize(
          resolution: JsonConflictResolution.preferRemote,
        );
        _expectPublicValue(second.value, 'shared', 'preferred-remote-first');

        await second.updatePublic('offlineField', 'survives-http-outage');
        final unavailableUri = await _closedLoopbackUri();
        final offline = second.rebuild(
          client: DataApiClient(
            baseUri: unavailableUri,
            accessToken: 'unreachable-fixture-token',
            encryptionKey: _encryptionKey,
            connectionTimeout: const Duration(milliseconds: 250),
            requestTimeout: const Duration(milliseconds: 500),
          ),
          destination: secondSession.syncIdentity(baseUri),
        );
        openedDevices.add(offline);
        await second.close(removeDirectory: false);
        await offline.sync.synchronize();
        expect(offline.sync.phase, LocalFirstSyncPhase.unavailable);
        expect(
          offline.sync.failureReason,
          LocalFirstSyncFailureReason.unavailable,
        );
        _expectPublicValue(
          offline.value,
          'offlineField',
          'survives-http-outage',
        );
        final recovered = offline.rebuild(
          client: null,
          destination: secondSession.syncIdentity(baseUri),
        );
        openedDevices.add(recovered);
        await offline.close(removeDirectory: false);
        recovered.sync.markUnavailable();
        await recovered.updatePublic('credentialOutage', 'pending-local-edit');
        await first.updatePublic('peerDuringRecovery', 'remote-edit');
        await first.sync.synchronize();

        await recovered.sync.retry(
          restoreTransport: () async {
            throw const FileSystemException(
              'fixture credential store unavailable',
            );
          },
        );
        expect(recovered.sync.phase, LocalFirstSyncPhase.unavailable);
        _expectPublicValue(
          recovered.value,
          'credentialOutage',
          'pending-local-edit',
        );
        await recovered.sync.retry(
          restoreTransport: () => recovered.sync.setTransport(
            nextClient: secondClient,
            nextCheckpoints: FileSyncCheckpointStore(
              directory: () async => recovered.directory,
              destination: secondSession.syncIdentity(baseUri),
              cipher: ProfileSecretCipher(keyStore: recovered.keyStore),
            ),
          ),
        );
        expect(recovered.sync.phase, LocalFirstSyncPhase.idle);
        expect(recovered.sync.failureReason, isNull);
        _expectPublicValue(
          recovered.value,
          'peerDuringRecovery',
          'remote-edit',
        );
        _expectPublicValue(
          recovered.value,
          'offlineField',
          'survives-http-outage',
        );
        expect(_secret(recovered.value, 'password'), _secretMarker);
        await first.sync.synchronize();
        _expectPublicValue(
          first.value,
          'credentialOutage',
          'pending-local-edit',
        );

        await first.updatePublic('after401', 'pending-through-reconnect');
        await _anonymousClient(
          baseUri,
        ).cancelAuthOperation(firstSession.operationId);
        await expectLater(
          firstClient.validateSession,
          throwsA(
            isA<DataApiRequestException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
        await first.sync.synchronize();
        expect(first.sync.phase, LocalFirstSyncPhase.unavailable);
        expect(
          first.sync.failureReason,
          LocalFirstSyncFailureReason.authenticationRequired,
        );

        final renewedSession = await _login(baseUri);
        issuedOperationIds.add(renewedSession.operationId);
        final renewedClient = _client(baseUri, renewedSession.token);
        expect(
          renewedSession.syncIdentity(baseUri),
          firstSession.syncIdentity(baseUri),
        );
        final reconnected = first.rebuild(
          client: renewedClient,
          destination: renewedSession.syncIdentity(baseUri),
        );
        openedDevices.add(reconnected);
        await first.close(removeDirectory: false);
        await reconnected.sync.synchronize();
        expect(reconnected.sync.phase, LocalFirstSyncPhase.idle);
        expect(reconnected.sync.failureReason, isNull);
        await recovered.sync.synchronize();
        _expectPublicValue(
          recovered.value,
          'after401',
          'pending-through-reconnect',
        );

        final remoteBeforeDisable = await renewedClient.getResource(
          kind: _resourceKind,
          id: _resourceId,
          includeSensitive: true,
        );
        final disabled = reconnected.rebuild(
          client: null,
          destination: renewedSession.syncIdentity(baseUri),
        );
        openedDevices.add(disabled);
        await reconnected.close(removeDirectory: false);
        await disabled.updatePublic('disabledField', 'kept-locally');
        await disabled.sync.synchronize();
        expect(disabled.sync.phase, LocalFirstSyncPhase.disabled);
        _expectPublicValue(disabled.value, 'disabledField', 'kept-locally');
        expect(_secret(disabled.value, 'password'), _secretMarker);
        final remoteWhileDisabled = await renewedClient.getResource(
          kind: _resourceKind,
          id: _resourceId,
          includeSensitive: true,
        );
        expect(remoteWhileDisabled!.revision, remoteBeforeDisable!.revision);

        final finalDevice = disabled.rebuild(
          client: renewedClient,
          destination: renewedSession.syncIdentity(baseUri),
        );
        openedDevices.add(finalDevice);
        await disabled.close(removeDirectory: false);
        await finalDevice.sync.synchronize();
        await recovered.sync.synchronize();
        _expectPublicValue(recovered.value, 'disabledField', 'kept-locally');
        expect(_secret(recovered.value, 'password'), _secretMarker);
        await _expectEncryptedCheckpoints(finalDevice.directory);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

Uri _validatedFixtureUri() {
  final uri = Uri.tryParse(_apiUrl);
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != InternetAddress.loopbackIPv4.address ||
      uri.port == 0 ||
      _username.isEmpty ||
      _password.length < 12 ||
      _encryptionKey.isEmpty) {
    throw StateError(
      'Run this acceptance through tools/verify_local_first_sync_http.sh.',
    );
  }
  return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
}

DataApiClient _anonymousClient(Uri baseUri) => DataApiClient(
  baseUri: baseUri,
  accessToken: null,
  encryptionKey: null,
  connectionTimeout: const Duration(seconds: 2),
  requestTimeout: const Duration(seconds: 5),
);

DataApiClient _client(Uri baseUri, String token) => DataApiClient(
  baseUri: baseUri,
  accessToken: token,
  encryptionKey: _encryptionKey,
  connectionTimeout: const Duration(seconds: 2),
  requestTimeout: const Duration(seconds: 5),
);

Future<_IssuedSession> _register(Uri baseUri) async {
  final prepared = await _postJson(
    baseUri.resolve('v1/auth/register/begin'),
    <String, Object?>{'username': _username, 'password': _password},
    expectedStatus: HttpStatus.created,
  );
  final operationId = prepared['operation_id'];
  if (operationId is! String) {
    throw const FormatException('Registration operation ID is missing.');
  }
  final issued = await _postJson(
    baseUri.resolve('v1/auth/register/complete'),
    <String, Object?>{'operation_id': operationId},
    expectedStatus: HttpStatus.ok,
  );
  return _IssuedSession.fromJson(issued, operationId: operationId);
}

Future<_IssuedSession> _login(Uri baseUri) async {
  final anonymous = _anonymousClient(baseUri);
  final prepared = await anonymous.beginLogin(
    username: _username,
    password: _password,
  );
  final issued = await anonymous.completeLogin(prepared.operationId);
  return _IssuedSession(
    operationId: prepared.operationId,
    token: issued.accessToken,
    expiresAt: issued.expiresAt,
  );
}

Future<Map<String, Object?>> _postJson(
  Uri uri,
  Map<String, Object?> body, {
  required int expectedStatus,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client
        .postUrl(uri)
        .timeout(const Duration(seconds: 5));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != expectedStatus) {
      throw HttpException(
        'Expected HTTP $expectedStatus, got ${response.statusCode}: $text',
        uri: uri,
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Authentication response is not an object.');
    }
    return decoded.cast<String, Object?>();
  } finally {
    client.close(force: true);
  }
}

Future<String> _rawGet(Uri uri, {required String token}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Expected HTTP 200, got ${response.statusCode}: $body',
        uri: uri,
      );
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

Future<Uri> _closedLoopbackUri() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return Uri.parse('http://127.0.0.1:$port/');
}

Future<void> _bestEffortCancel(Uri baseUri, String operationId) async {
  try {
    await _anonymousClient(baseUri).cancelAuthOperation(operationId);
  } on Object {
    // Fixture cleanup must not hide the acceptance result.
  }
}

final class _IssuedSession {
  const _IssuedSession({
    required this.operationId,
    required this.token,
    required this.expiresAt,
  });

  factory _IssuedSession.fromJson(
    Map<String, Object?> json, {
    required String operationId,
  }) {
    final token = json['token'];
    final expiresAt = DateTime.tryParse(json['expires_at']?.toString() ?? '');
    if (token is! String || token.isEmpty || expiresAt == null) {
      throw const FormatException('Issued authentication session is invalid.');
    }
    return _IssuedSession(
      operationId: operationId,
      token: token,
      expiresAt: expiresAt.toUtc(),
    );
  }

  final String operationId;
  final String token;
  final DateTime expiresAt;

  String syncIdentity(Uri baseUri) => DataApiRemoteSession(
    baseUri: baseUri,
    accessToken: token,
    encryptionKey: _encryptionKey,
    expiresAt: expiresAt,
    username: _username,
  ).syncIdentity;
}

final class _Device {
  _Device._({
    required this.directory,
    required this.document,
    required this.keyStore,
    required this.sync,
  });

  static Future<_Device> create({
    required String label,
    required DataApiResourceClient client,
    required String destination,
    required Map<String, Object?> initial,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs-local-first-http-$label-',
    );
    final document = _FileDocument(File('${directory.path}/document.json'));
    await document.write(initial);
    return _build(
      directory: directory,
      document: document,
      keyStore: _MemoryProfileSecretKeyStore(),
      client: client,
      destination: destination,
    );
  }

  static _Device _build({
    required Directory directory,
    required _FileDocument document,
    required _MemoryProfileSecretKeyStore keyStore,
    required DataApiResourceClient? client,
    required String destination,
  }) {
    final binding = SyncDocumentBinding(
      kind: _resourceKind,
      id: _resourceId,
      readLocal: document.read,
      writeLocal: document.writeNullable,
      decodeRemote: (resource) {
        final data = dataApiObject(
          resource.data,
          documentName: 'HTTP sync public document',
        );
        final sensitive = resource.sensitive == null
            ? null
            : dataApiObject(
                resource.sensitive,
                documentName: 'HTTP sync sensitive document',
              );
        return mergeDataApiObjects(data, sensitive);
      },
      encodeRemote: (value) {
        final data = Map<String, Object?>.from(value)..remove('secret');
        return (
          data: data,
          sensitive: value['secret'] == null
              ? null
              : <String, Object?>{'secret': value['secret']},
        );
      },
      validate: (value) {
        if (value == null ||
            value['public'] is! Map ||
            value['secret'] is! Map) {
          throw const FormatException('Invalid local-first fixture document.');
        }
      },
    );
    final sync = LocalFirstSyncCoordinator(
      documents: <SyncDocumentBinding>[binding],
      client: client,
      checkpoints: client == null
          ? null
          : FileSyncCheckpointStore(
              directory: () async => directory,
              destination: destination,
              cipher: ProfileSecretCipher(keyStore: keyStore),
            ),
    );
    return _Device._(
      directory: directory,
      document: document,
      keyStore: keyStore,
      sync: sync,
    );
  }

  final Directory directory;
  final _FileDocument document;
  final _MemoryProfileSecretKeyStore keyStore;
  final LocalFirstSyncCoordinator sync;
  bool _closed = false;

  Map<String, Object?> get value => document.value;

  Future<void> updatePublic(String key, Object? value) async {
    final next = await document.read();
    final public = Map<String, Object?>.from(next['public']! as Map);
    public[key] = value;
    await document.write(<String, Object?>{...next, 'public': public});
  }

  _Device rebuild({
    required DataApiResourceClient? client,
    required String destination,
  }) => _build(
    directory: directory,
    document: document,
    keyStore: keyStore,
    client: client,
    destination: destination,
  );

  Future<void> close({bool removeDirectory = true}) async {
    if (!_closed) {
      _closed = true;
      await sync.close();
    }
    if (removeDirectory && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

final class _FileDocument {
  _FileDocument(this.file);

  final File file;
  Map<String, Object?> _value = <String, Object?>{};

  Map<String, Object?> get value => _deepCopy(_value);

  Future<Map<String, Object?>> read() async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Fixture document is not an object.');
    }
    _value = decoded.cast<String, Object?>();
    return value;
  }

  Future<void> write(Map<String, Object?> value) async {
    _value = _deepCopy(value);
    await file.writeAsString(jsonEncode(_value), flush: true);
  }

  Future<void> writeNullable(Map<String, Object?>? value) async {
    if (value == null) {
      throw const FormatException('Fixture document cannot be deleted.');
    }
    await write(value);
  }
}

final class _MemoryProfileSecretKeyStore implements ProfileSecretKeyStore {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

Map<String, Object?> _document({
  required Map<String, Object?> public,
  required Map<String, Object?> secret,
}) => <String, Object?>{'public': public, 'secret': secret};

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

Object? _secret(Map<String, Object?> document, String key) =>
    (document['secret']! as Map)[key];

void _expectPublicValue(
  Map<String, Object?> document,
  String key,
  Object? expected,
) {
  expect((document['public']! as Map)[key], expected);
}

void _expectPublic(
  Map<String, Object?> document,
  Map<String, Object?> expected,
) {
  expect((document['public']! as Map).cast<String, Object?>(), expected);
}

Future<void> _expectEncryptedCheckpoints(Directory directory) async {
  final checkpointDirectory = Directory('${directory.path}/sync-checkpoints');
  final files = await checkpointDirectory
      .list()
      .where((entry) => entry is File)
      .cast<File>()
      .toList();
  expect(files, hasLength(1));
  final contents = await files.single.readAsString();
  expect(contents, isNot(contains(_secretMarker)));
  expect(contents, isNot(contains('second-device-private-key-marker')));
}

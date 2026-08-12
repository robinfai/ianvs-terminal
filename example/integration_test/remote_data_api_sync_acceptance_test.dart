import 'dart:convert';
import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _remoteApiUrl = String.fromEnvironment('IANVS_ACCEPTANCE_REMOTE_API_URL');
const _credentialsUrl = String.fromEnvironment(
  'IANVS_ACCEPTANCE_CREDENTIALS_URL',
);
const _syncPhase = String.fromEnvironment('IANVS_ACCEPTANCE_SYNC_PHASE');
const _syncResourceId = String.fromEnvironment(
  'IANVS_ACCEPTANCE_SYNC_RESOURCE_ID',
);

const _resourceKind = 'acceptance';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS and iOS exchange a remote Data API resource', (_) async {
    final input = await _AcceptanceInput.load();
    final client = await _login(input);
    try {
      await client.validateSession();
      switch (input.phase) {
        case _SyncPhase.macOsWrite:
          expect(Platform.isMacOS, isTrue);
          final existing = await client.getResource(
            kind: _resourceKind,
            id: input.resourceId,
            includeSensitive: true,
          );
          expect(existing, isNull);
          final saved = await client.putResource(
            kind: _resourceKind,
            id: input.resourceId,
            data: <String, Object?>{
              'schema_version': 1,
              'writer': 'macos',
              'resource_id': input.resourceId,
            },
            sensitive: const <String, Object?>{'platform': 'macos'},
            expectedRevision: 0,
          );
          expect(saved.revision, 1);
        case _SyncPhase.iosReadWrite:
          expect(Platform.isIOS, isTrue);
          final observed = await _requireResource(client, input.resourceId);
          expect(_writer(observed), 'macos');
          expect(observed.sensitive, const <String, Object?>{
            'platform': 'macos',
          });
          final saved = await client.putResource(
            kind: _resourceKind,
            id: input.resourceId,
            data: <String, Object?>{
              'schema_version': 1,
              'writer': 'ios',
              'resource_id': input.resourceId,
            },
            sensitive: const <String, Object?>{'platform': 'ios'},
            expectedRevision: observed.revision,
          );
          expect(saved.revision, greaterThan(observed.revision));
        case _SyncPhase.macOsReadCleanup:
          expect(Platform.isMacOS, isTrue);
          final observed = await _requireResource(client, input.resourceId);
          expect(_writer(observed), 'ios');
          expect(observed.sensitive, const <String, Object?>{
            'platform': 'ios',
          });
          expect(
            await client.deleteResource(
              kind: _resourceKind,
              id: input.resourceId,
              expectedRevision: observed.revision,
            ),
            isTrue,
          );
          expect(
            await client.getResource(kind: _resourceKind, id: input.resourceId),
            isNull,
          );
        case _SyncPhase.cleanup:
          final existing = await client.getResource(
            kind: _resourceKind,
            id: input.resourceId,
          );
          if (existing != null) {
            await client.deleteResource(
              kind: _resourceKind,
              id: input.resourceId,
              expectedRevision: existing.revision,
            );
          }
      }
    } finally {
      await _bestEffortLogout(client);
    }
  });
}

enum _SyncPhase { macOsWrite, iosReadWrite, macOsReadCleanup, cleanup }

final class _AcceptanceInput {
  const _AcceptanceInput({
    required this.baseUri,
    required this.username,
    required this.password,
    required this.encryptionKey,
    required this.phase,
    required this.resourceId,
  });

  static Future<_AcceptanceInput> load() async {
    final baseUri = Uri.tryParse(_remoteApiUrl);
    if (baseUri == null || baseUri.scheme != 'https' || baseUri.host.isEmpty) {
      throw StateError(
        'IANVS_ACCEPTANCE_REMOTE_API_URL must be a remote HTTPS base URL.',
      );
    }
    final phase = switch (_syncPhase) {
      'macos-write' => _SyncPhase.macOsWrite,
      'ios-read-write' => _SyncPhase.iosReadWrite,
      'macos-read-cleanup' => _SyncPhase.macOsReadCleanup,
      'cleanup' => _SyncPhase.cleanup,
      _ => throw StateError('Unsupported acceptance sync phase: $_syncPhase'),
    };
    if (!RegExp(r'^sync-[a-f0-9]{24}$').hasMatch(_syncResourceId)) {
      throw StateError(
        'IANVS_ACCEPTANCE_SYNC_RESOURCE_ID must match sync-[a-f0-9]{24}.',
      );
    }
    final credentialsUri = Uri.tryParse(_credentialsUrl);
    if (credentialsUri == null ||
        credentialsUri.scheme != 'http' ||
        credentialsUri.host != '127.0.0.1') {
      throw StateError(
        'IANVS_ACCEPTANCE_CREDENTIALS_URL must be an ephemeral loopback URL.',
      );
    }
    final credentials = await _getJson(credentialsUri);
    final username = credentials['username'];
    final password = credentials['password'];
    final encryptionKey = credentials['encryption_key'];
    if (username is! String ||
        username.isEmpty ||
        password is! String ||
        password.isEmpty ||
        encryptionKey is! String ||
        encryptionKey.isEmpty) {
      throw const FormatException(
        'Acceptance credentials are incomplete or invalid.',
      );
    }
    return _AcceptanceInput(
      baseUri: baseUri,
      username: username,
      password: password,
      encryptionKey: encryptionKey,
      phase: phase,
      resourceId: _syncResourceId,
    );
  }

  final Uri baseUri;
  final String username;
  final String password;
  final String encryptionKey;
  final _SyncPhase phase;
  final String resourceId;
}

Future<Map<String, Object?>> _getJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Acceptance credential broker returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      if (buffer.length + chunk.length > 4096) {
        throw const FormatException(
          'Acceptance credentials exceeded the 4096-byte limit.',
        );
      }
      return buffer..addAll(chunk);
    });
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Acceptance credentials are not a JSON object.',
      );
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<DataApiClient> _login(_AcceptanceInput input) async {
  final anonymous = DataApiClient(
    baseUri: input.baseUri,
    accessToken: null,
    encryptionKey: null,
  );
  final operation = await anonymous.beginLogin(
    username: input.username,
    password: input.password,
  );
  final login = await anonymous.completeLogin(operation.operationId);
  return DataApiClient(
    baseUri: input.baseUri,
    accessToken: login.accessToken,
    encryptionKey: input.encryptionKey,
  );
}

Future<DataApiResource> _requireResource(
  DataApiClient client,
  String resourceId,
) async {
  final resource = await client.getResource(
    kind: _resourceKind,
    id: resourceId,
    includeSensitive: true,
  );
  expect(resource, isNotNull);
  return resource!;
}

String? _writer(DataApiResource resource) {
  final data = resource.data;
  return data is Map<String, Object?> ? data['writer'] as String? : null;
}

Future<void> _bestEffortLogout(DataApiClient client) async {
  try {
    await client.logout();
  } on Object {
    // Logout cleanup must not conceal the sync acceptance result.
  }
}

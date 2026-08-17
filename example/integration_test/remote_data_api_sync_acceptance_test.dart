import 'dart:convert';
import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/ssh/ssh_private_key_material.dart';
import 'package:app/features/ssh/ssh_profile_import_service.dart';
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

const _macOsPassword = 'macos-acceptance-password';
const _macOsPassphrase = 'macos-acceptance-passphrase';
const _iosPassword = 'ios-acceptance-password';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS imports SSH Cloud and iOS decrypts it', (_) async {
    final input = await _AcceptanceInput.load();
    final client = await _login(input);
    try {
      await client.validateSession();
      final repository = DataApiProfileRepository(client: client);
      switch (input.phase) {
        case _SyncPhase.macOsWrite:
          expect(Platform.isMacOS, isTrue);
          final imported = await const NativeSshProfileImportService().load();
          expect(imported.error, isNull);
          final cloud = imported.profiles.singleWhere(
            (profile) =>
                profile.name.toLowerCase() == 'cloud' ||
                (profile.connection.host == '43.132.135.30' &&
                    profile.connection.user == 'lighthouse'),
          );
          expect(cloud.connection.host, '43.132.135.30');
          expect(cloud.connection.user, 'lighthouse');
          expect(cloud.connection.port, 22);
          _expectInlinePrivateKeys(cloud.connection.privateKeys);

          final importedWithSecrets = cloud.copyWith(
            id: 'ssh-cloud-${input.resourceId.substring(5, 13)}',
            name: 'SSH Cloud',
            tags: <String>[...cloud.tags, 'Acceptance', input.resourceId],
            connection: cloud.connection.copyWith(
              password: _macOsPassword,
              privateKeyPassphrase: _macOsPassphrase,
            ),
          );
          final initial = await repository.loadVersioned();
          final saved = await repository.saveVersioned(
            initial.withValue(
              _withProfiles(initial.value, <TerminalProfile>[
                ...initial.value.profiles.where(
                  (profile) => profile.id != importedWithSecrets.id,
                ),
                importedWithSecrets,
              ]),
            ),
          );
          expect(saved.revision, greaterThan(initial.revision!));

          final publicResource = await client.getResource(
            kind: DataApiProfileRepository.resourceKind,
            id: DataApiProfileRepository.resourceId,
          );
          expect(publicResource, isNotNull);
          expect(publicResource!.hasSensitive, isTrue);
          expect(publicResource.sensitive, isNull);
          expect(publicResource.data.toString(), contains('43.132.135.30'));
          expect(
            publicResource.data.toString(),
            isNot(contains(_macOsPassword)),
          );
          expect(
            publicResource.data.toString(),
            isNot(contains(_macOsPassphrase)),
          );
          expect(
            publicResource.data.toString(),
            isNot(contains('PRIVATE KEY-----')),
          );
        case _SyncPhase.iosReadWrite:
          expect(Platform.isIOS, isTrue);
          final observed = await repository.loadVersioned();
          final profile = observed.value.profiles.singleWhere(
            (profile) => profile.id == _acceptanceProfileId(input.resourceId),
          );
          _expectImportedCloudProfile(
            profile,
            resourceId: input.resourceId,
            password: _macOsPassword,
          );
          expect(profile.connection.privateKeyPassphrase, _macOsPassphrase);

          final updated = profile.copyWith(
            name: 'SSH Cloud (iOS verified)',
            connection: profile.connection.copyWith(password: _iosPassword),
          );
          final saved = await repository.saveVersioned(
            observed.withValue(
              _withProfiles(observed.value, <TerminalProfile>[
                for (final current in observed.value.profiles)
                  current.id == updated.id ? updated : current,
              ]),
            ),
          );
          expect(saved.revision, greaterThan(observed.revision!));
        case _SyncPhase.macOsReadCleanup:
          expect(Platform.isMacOS, isTrue);
          final observed = await repository.loadVersioned();
          final acceptanceProfileId = _acceptanceProfileId(input.resourceId);
          final profile = observed.value.profiles.singleWhere(
            (profile) => profile.id == acceptanceProfileId,
          );
          _expectImportedCloudProfile(
            profile,
            resourceId: input.resourceId,
            password: _iosPassword,
          );
          expect(profile.name, 'SSH Cloud (iOS verified)');
          expect(profile.connection.privateKeyPassphrase, _macOsPassphrase);
          final imported = await const NativeSshProfileImportService().load();
          expect(imported.error, isNull);
          final localCloud = imported.profiles.singleWhere(
            (profile) =>
                profile.name.toLowerCase() == 'cloud' ||
                (profile.connection.host == '43.132.135.30' &&
                    profile.connection.user == 'lighthouse'),
          );
          final persistedCloud = localCloud.copyWith(name: 'SSH Cloud');
          _expectInlinePrivateKeys(persistedCloud.connection.privateKeys);
          final cleaned = await repository.saveVersioned(
            observed.withValue(
              _withProfiles(observed.value, <TerminalProfile>[
                ...observed.value.profiles.where(
                  (profile) =>
                      profile.id != acceptanceProfileId &&
                      profile.id != persistedCloud.id,
                ),
                persistedCloud,
              ]),
            ),
          );
          expect(cleaned.revision, greaterThan(observed.revision!));
          final savedCloud = cleaned.value.profiles.singleWhere(
            (profile) => profile.id == persistedCloud.id,
          );
          expect(savedCloud.name, 'SSH Cloud');
          expect(savedCloud.connection.host, '43.132.135.30');
          expect(savedCloud.connection.user, 'lighthouse');
          expect(
            await client.getResource(
              kind: DataApiProfileRepository.resourceKind,
              id: DataApiProfileRepository.resourceId,
            ),
            isNotNull,
          );
        case _SyncPhase.cleanup:
          final observed = await repository.loadVersioned();
          final acceptanceProfileId = _acceptanceProfileId(input.resourceId);
          if (observed.value.profiles.any(
            (profile) => profile.id == acceptanceProfileId,
          )) {
            await repository.saveVersioned(
              observed.withValue(
                _withProfiles(
                  observed.value,
                  observed.value.profiles
                      .where((profile) => profile.id != acceptanceProfileId)
                      .toList(growable: false),
                ),
              ),
            );
          }
      }
    } finally {
      await _bestEffortLogout(client);
    }
  });
}

String _acceptanceProfileId(String resourceId) =>
    'ssh-cloud-${resourceId.substring(5, 13)}';

TerminalProfilesDocument _withProfiles(
  TerminalProfilesDocument current,
  List<TerminalProfile> profiles,
) {
  return TerminalProfilesDocument(
    schemaVersion: current.schemaVersion,
    profiles: profiles,
    loadWarnings: current.loadWarnings,
    secretClearIntents: current.secretClearIntents,
  );
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

void _expectImportedCloudProfile(
  TerminalProfile profile, {
  required String resourceId,
  required String password,
}) {
  expect(profile.id, 'ssh-cloud-${resourceId.substring(5, 13)}');
  expect(profile.tags, containsAll(<String>['SSH', 'OpenSSH', 'Acceptance']));
  expect(profile.tags, contains(resourceId));
  expect(profile.connection.host, '43.132.135.30');
  expect(profile.connection.user, 'lighthouse');
  expect(profile.connection.port, 22);
  expect(profile.connection.password, password);
  _expectInlinePrivateKeys(profile.connection.privateKeys);
}

void _expectInlinePrivateKeys(List<String> privateKeys) {
  if (privateKeys.isEmpty) {
    fail('The imported SSH profile did not contain a private key.');
  }
  for (var index = 0; index < privateKeys.length; index += 1) {
    if (!looksLikeSshPrivateKeyContents(privateKeys[index])) {
      fail(
        'The imported SSH profile private key at index $index was a path '
        'instead of inline private key contents.',
      );
    }
  }
}

Future<void> _bestEffortLogout(DataApiClient client) async {
  try {
    await client.logout();
  } on Object {
    // Logout cleanup must not conceal the sync acceptance result.
  }
}

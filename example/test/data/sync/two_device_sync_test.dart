import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/sync/json_three_way_merge.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/data/sync/sync_repositories.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../support/memory_data_api_resource_client.dart';

const _destination = 'remote:https://sync.example.com/:user:alice';
const _firstPassword = 'device-a-password-marker';
const _firstPrivateKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nDEVICE-A-KEY\n'
    '-----END OPENSSH PRIVATE KEY-----';
const _firstPassphrase = 'device-a-passphrase-marker';
const _firstCookie = 'device-a-x11-cookie-marker';
const _secondPassword = 'device-b-password-marker';
const _secondPrivateKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nDEVICE-B-KEY\n'
    '-----END OPENSSH PRIVATE KEY-----';

void main() {
  test(
    'two devices keep encrypted local profiles while merging through one API',
    () async {
      final remote = MemoryDataApiResourceClient();
      remote.resources['paste_history/default'] = dataApiTestResource(
        kind: 'paste_history',
        id: 'default',
        data: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
        sensitive: const <String, Object?>{
          'schema_version': 1,
          'entries': <Object?>[],
        },
        revision: 7,
      );
      final first = await _Device.create('first', remote);
      final second = await _Device.create('second', remote);
      addTearDown(() async {
        await first.close();
        await second.close();
      });
      expect(
        first.sync.documents.map((binding) => binding.kind),
        isNot(contains('paste_history')),
      );

      await first.repositories.profiles.save(
        TerminalProfilesDocument(profiles: <TerminalProfile>[_firstProfile()]),
      );
      await first.sync.synchronize();
      await second.repositories.profiles.save(
        TerminalProfilesDocument(profiles: <TerminalProfile>[_secondProfile()]),
      );
      await second.sync.synchronize();
      await first.sync.synchronize();

      await _expectProfileIds(first, <String>{'device-a', 'device-b'});
      await _expectProfileIds(second, <String>{'device-a', 'device-b'});
      await _expectSecretsSurviveRepositoryRebuild(first);
      await _expectSecretsSurviveRepositoryRebuild(second);
      await _expectNoPlaintext(first.directory);
      await _expectNoPlaintext(second.directory);
      expect(remote.resources['paste_history/default']?.revision, 7);
      expect(
        remote.deletedResourceKeys,
        isNot(contains('paste_history/default')),
      );

      await first.edit('device-a', (profile) => profile.copyWith(name: 'A2'));
      await second.edit(
        'device-b',
        (profile) => profile.copyWith(tags: <String>[...profile.tags, 'B2']),
      );
      await first.sync.synchronize();
      await second.sync.synchronize();
      await first.sync.synchronize();
      expect((await first.profile('device-a')).name, 'A2');
      expect((await first.profile('device-b')).tags, contains('B2'));
      expect((await second.profile('device-a')).name, 'A2');
      expect((await second.profile('device-b')).tags, contains('B2'));

      await first.edit(
        'device-a',
        (profile) => profile.copyWith(name: 'A conflict winner'),
      );
      await second.edit(
        'device-a',
        (profile) => profile.copyWith(name: 'B unresolved edit'),
      );
      await first.sync.synchronize();
      await second.sync.synchronize();
      expect(second.sync.phase, LocalFirstSyncPhase.conflict);
      expect(
        second.sync.conflicts['profile/default'],
        contains('/profiles/device-a/name'),
      );
      expect((await second.profile('device-a')).name, 'B unresolved edit');
      expect(_remoteProfileName(remote, 'device-a'), 'A conflict winner');

      await second.sync.synchronize(
        resolution: JsonConflictResolution.preferLocal,
      );
      await first.sync.synchronize();
      expect(second.sync.conflicts, isEmpty);
      expect((await first.profile('device-a')).name, 'B unresolved edit');
      expect(_remoteProfileName(remote, 'device-a'), 'B unresolved edit');

      await first.remove('device-b');
      await first.sync.synchronize();
      await second.sync.synchronize();
      await second.sync.synchronize();
      await _expectProfileIds(first, <String>{'device-a'});
      await _expectProfileIds(second, <String>{'device-a'});

      final disabled = first.rebuild(client: null);
      await disabled.repositories.profiles.save(
        TerminalProfilesDocument(
          profiles: <TerminalProfile>[
            ...(await disabled.repositories.profiles.load()).profiles,
            _thirdProfile(),
          ],
        ),
      );
      expect(disabled.sync.phase, LocalFirstSyncPhase.disabled);
      expect(await disabled.profile('device-c'), isNotNull);
      await disabled.close(removeDirectory: false);

      final reenabled = first.rebuild(client: remote);
      await reenabled.sync.synchronize();
      await second.sync.synchronize();
      await _expectProfileIds(reenabled, <String>{'device-a', 'device-c'});
      await _expectProfileIds(second, <String>{'device-a', 'device-c'});
      await _expectNoPlaintext(reenabled.directory);
      await reenabled.close(removeDirectory: false);
    },
  );
}

final class _Device {
  _Device._({
    required this.directory,
    required this.keyStore,
    required this.sync,
    required this.repositories,
  });

  final Directory directory;
  final _MemoryProfileSecretKeyStore keyStore;
  final LocalFirstSyncCoordinator sync;
  final LocalFirstRepositories repositories;

  static Future<_Device> create(
    String label,
    DataApiResourceClient? client,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs-two-device-sync-$label-',
    );
    return _build(directory, _MemoryProfileSecretKeyStore(), client);
  }

  static _Device _build(
    Directory directory,
    _MemoryProfileSecretKeyStore keyStore,
    DataApiResourceClient? client,
  ) {
    final cipher = ProfileSecretCipher(keyStore: keyStore);
    final profiles = ProfileRepository(
      directoryResolver: () async => directory,
      secretCipher: cipher,
    );
    final bindings = SyncRepositoryBindings(
      profiles: profiles,
      preferences: AppPreferencesRepository(
        directoryResolver: () async => directory,
      ),
      terminalConfig: LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      ),
      pasteHistory: PasteHistoryRepository(
        directoryResolver: () async => directory,
      ),
    );
    final sync = LocalFirstSyncCoordinator(
      documents: bindings.bindings,
      client: client,
      checkpoints: client == null
          ? null
          : FileSyncCheckpointStore(
              directory: () async => directory,
              destination: _destination,
              cipher: cipher,
            ),
    );
    return _Device._(
      directory: directory,
      keyStore: keyStore,
      sync: sync,
      repositories: bindings.wrap(sync),
    );
  }

  _Device rebuild({required DataApiResourceClient? client}) =>
      _build(directory, keyStore, client);

  Future<TerminalProfile> profile(String id) async =>
      (await repositories.profiles.load()).profiles.singleWhere(
        (profile) => profile.id == id,
      );

  Future<void> edit(
    String id,
    TerminalProfile Function(TerminalProfile) update,
  ) async {
    final document = await repositories.profiles.load();
    await repositories.profiles.save(
      TerminalProfilesDocument(
        profiles: <TerminalProfile>[
          for (final profile in document.profiles)
            profile.id == id ? update(profile) : profile,
        ],
      ),
    );
  }

  Future<void> remove(String id) async {
    final document = await repositories.profiles.load();
    await repositories.profiles.save(
      TerminalProfilesDocument(
        profiles: document.profiles
            .where((profile) => profile.id != id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> close({bool removeDirectory = true}) async {
    await sync.close();
    if (removeDirectory && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

TerminalProfile _firstProfile() => defaultTerminalProfile().copyWith(
  id: 'device-a',
  name: 'Device A',
  connection: const terminal.TerminalConnectionConfig.ssh(
    host: 'a.example.test',
    user: 'alice',
    auth: terminal.TerminalSshAuthMethod.publicKey,
    password: _firstPassword,
    privateKeys: <String>[_firstPrivateKey],
    privateKeyPassphrase: _firstPassphrase,
    x11Forwarding: true,
    x11AuthCookie: _firstCookie,
  ),
);

TerminalProfile _secondProfile() => defaultTerminalProfile().copyWith(
  id: 'device-b',
  name: 'Device B',
  connection: const terminal.TerminalConnectionConfig.ssh(
    host: 'b.example.test',
    user: 'bob',
    auth: terminal.TerminalSshAuthMethod.password,
    password: _secondPassword,
    privateKeys: <String>[_secondPrivateKey],
  ),
);

TerminalProfile _thirdProfile() => defaultTerminalProfile().copyWith(
  id: 'device-c',
  name: 'Created while sync was off',
  connection: const terminal.TerminalConnectionConfig.ssh(
    host: 'c.example.test',
    user: 'carol',
    auth: terminal.TerminalSshAuthMethod.password,
    password: 'device-c-offline-password-marker',
  ),
);

Future<void> _expectProfileIds(_Device device, Set<String> expected) async {
  expect(
    (await device.repositories.profiles.load()).profiles
        .map((profile) => profile.id)
        .toSet(),
    expected,
  );
}

Future<void> _expectSecretsSurviveRepositoryRebuild(_Device device) async {
  final rebuilt = device.rebuild(client: null);
  final first = await rebuilt.profile('device-a');
  final second = await rebuilt.profile('device-b');
  expect(first.connection.password, _firstPassword);
  expect(first.connection.privateKeys, <String>[_firstPrivateKey]);
  expect(first.connection.privateKeyPassphrase, _firstPassphrase);
  expect(first.connection.x11AuthCookie, _firstCookie);
  expect(second.connection.password, _secondPassword);
  expect(second.connection.privateKeys, <String>[_secondPrivateKey]);
  await rebuilt.close(removeDirectory: false);
}

Future<void> _expectNoPlaintext(Directory directory) async {
  final files = await directory
      .list(recursive: true)
      .where((entry) => entry is File)
      .cast<File>()
      .toList();
  final contents = (await Future.wait(
    files.map((file) => file.readAsString()),
  )).join('\n');
  for (final marker in const <String>[
    _firstPassword,
    _firstPrivateKey,
    _firstPassphrase,
    _firstCookie,
    _secondPassword,
    _secondPrivateKey,
    'device-c-offline-password-marker',
  ]) {
    expect(contents, isNot(contains(marker)));
  }
}

String? _remoteProfileName(MemoryDataApiResourceClient remote, String id) {
  final resource = remote.resources['profile/default'];
  if (resource == null) return null;
  final data = Map<String, Object?>.from(resource.data! as Map);
  final profiles = data['profiles']! as List<Object?>;
  final profile = profiles.whereType<Map<Object?, Object?>>().singleWhere(
    (profile) => profile['id'] == id,
  );
  return profile['name'] as String?;
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

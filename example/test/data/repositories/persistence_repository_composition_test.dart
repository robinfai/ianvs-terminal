import 'dart:io';

import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/data/sync/sync_repositories.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/persistence_repository_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late _MemoryMasterKeyStorage masterKeyStorage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-persistence-composition-',
    );
    masterKeyStorage = _MemoryMasterKeyStorage();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  PersistenceRepositoryComposition compose(
    DataApiRuntime? runtime, {
    bool dataApiPersistenceRequired = false,
    bool dataApiPersistenceUnavailable = false,
  }) {
    return PersistenceRepositoryComposition.forRuntime(
      runtime,
      profileExportDirectoryResolver: () async => temporaryDirectory,
      masterKeyRepository: PortableMasterKeyRepository(
        storage: masterKeyStorage,
        allowLegacyMigration: false,
      ),
      dataApiPersistenceRequired: dataApiPersistenceRequired,
      dataApiPersistenceUnavailable: dataApiPersistenceUnavailable,
    );
  }

  test('disabled runtime composes local-first repositories', () async {
    final composition = compose(null);

    expect(composition.usesDataApi, isFalse);
    expect(composition.persistenceUnavailable, isFalse);
    expect(composition.profiles, isA<LocalFirstProfileRepository>());
    expect(
      composition.terminalConfig,
      isA<LocalFirstTerminalConfigRepository>(),
    );
    expect(composition.terminalLayout, isA<LocalTerminalLayoutRepository>());

    await composition.terminalLayout.save(const TerminalLayout());
    expect(
      File(
        '${temporaryDirectory.path}/ianvs_terminal_layout.json',
      ).existsSync(),
      isTrue,
    );
    await composition.sync.close();
  });

  test(
    'unavailable API transport still permits local reads and writes',
    () async {
      final composition = compose(
        DataApiRuntime.remote(baseUri: Uri.parse('https://sync.example.test/')),
        dataApiPersistenceRequired: true,
        dataApiPersistenceUnavailable: true,
      );
      final document = TerminalProfilesDocument(
        profiles: [
          defaultTerminalProfile().copyWith(name: 'Local while offline'),
        ],
      );

      await composition.profiles.save(document);
      final loaded = await composition.profiles.load();

      expect(composition.usesDataApi, isFalse);
      expect(composition.persistenceUnavailable, isFalse);
      expect(composition.profiles, isA<LocalFirstProfileRepository>());
      expect(loaded.profiles.single.name, 'Local while offline');
      await composition.sync.close();
    },
  );

  test(
    'API enablement and disablement reuse encrypted local SSH profile data',
    () async {
      final first = compose(null);
      final sshProfile = defaultTerminalProfile().copyWith(
        id: 'saved-ssh',
        name: 'Saved SSH',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'ssh.example.test',
          user: 'developer',
          password: 'profile-password',
          privateKeys: ['private-key-contents'],
          privateKeyPassphrase: 'key-passphrase',
        ),
      );
      await first.profiles.save(
        TerminalProfilesDocument(profiles: [sshProfile]),
      );
      final storedProfiles = await File(
        '${temporaryDirectory.path}/ianvs_profiles.json',
      ).readAsString();
      expect(storedProfiles, isNot(contains('profile-password')));
      expect(storedProfiles, isNot(contains('private-key-contents')));
      expect(storedProfiles, isNot(contains('key-passphrase')));
      await first.sync.close();

      final apiEnabled = compose(
        DataApiRuntime.remote(
          baseUri: Uri.parse('https://sync.example.test/'),
          remoteAccessToken: 'access-token',
          encryptionKey: 'transport-encryption-key',
          syncIdentity: 'test-account',
        ),
      );
      final loadedWithApi = (await apiEnabled.profiles.load()).profiles.single;

      expect(apiEnabled.usesDataApi, isTrue);
      expect(apiEnabled.profiles, isA<LocalFirstProfileRepository>());
      expect(loadedWithApi.id, 'saved-ssh');
      expect(loadedWithApi.connection.password, 'profile-password');
      expect(loadedWithApi.connection.privateKeys, ['private-key-contents']);
      expect(loadedWithApi.connection.privateKeyPassphrase, 'key-passphrase');
      await apiEnabled.profiles.save(
        TerminalProfilesDocument(
          profiles: [loadedWithApi.copyWith(name: 'Edited with API enabled')],
        ),
      );
      await apiEnabled.sync.close();

      final disabledAgain = compose(null);
      final restored = (await disabledAgain.profiles.load()).profiles.single;

      expect(restored.name, 'Edited with API enabled');
      expect(restored.connection.password, 'profile-password');
      expect(restored.connection.privateKeys, ['private-key-contents']);
      expect(restored.connection.privateKeyPassphrase, 'key-passphrase');
      await disabledAgain.sync.close();
    },
  );

  test('profile export remains an explicit local copy in API mode', () async {
    final composition = compose(
      DataApiRuntime.remote(
        baseUri: Uri.parse('https://sync.example.test/'),
        remoteAccessToken: 'access-token',
        encryptionKey: 'transport-encryption-key',
      ),
    );

    final exported = await composition.profiles.exportDocument(
      const TerminalProfilesDocument(profiles: <TerminalProfile>[]),
      basename: 'remote-backup',
    );

    expect(exported.parent.path, temporaryDirectory.path);
    expect(
      exported.path,
      endsWith('remote-backup.ianvs-terminal-profiles.json'),
    );
    expect(await exported.exists(), isTrue);
    await composition.sync.close();
  });
}

final class _MemoryMasterKeyStorage implements PortableMasterKeyStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
  }
}

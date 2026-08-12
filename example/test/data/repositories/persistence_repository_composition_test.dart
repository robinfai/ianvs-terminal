import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/config/data_api_terminal_config_repository.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/persistence_repository_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-profile-export-composition-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('disabled runtime composes only local repositories', () {
    final composition = PersistenceRepositoryComposition.forRuntime(
      null,
      profileExportDirectoryResolver: () async => temporaryDirectory,
    );

    expect(composition.usesDataApi, isFalse);
    expect(composition.profiles, isA<LocalTerminalOnlyProfileRepository>());
    expect(composition.terminalConfig, isA<LocalTerminalConfigRepository>());
  });

  test(
    'disabled runtime hides custom SSH profiles without deleting them',
    () async {
      final delegate = ProfileRepository(
        directoryResolver: () async => temporaryDirectory,
      );
      final sshProfile = defaultTerminalProfile().copyWith(
        id: 'saved-ssh',
        name: 'Saved SSH',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'ssh.example.test',
          user: 'developer',
        ),
      );
      await delegate.save(
        TerminalProfilesDocument(
          profiles: <TerminalProfile>[defaultTerminalProfile(), sshProfile],
        ),
      );
      final composition = PersistenceRepositoryComposition.forRuntime(
        null,
        profileExportDirectoryResolver: () async => temporaryDirectory,
      );

      final visible = await composition.profiles.load();

      expect(visible.profiles, hasLength(1));
      expect(visible.profiles.single.isSsh, isFalse);
      await composition.profiles.save(
        TerminalProfilesDocument(
          profiles: <TerminalProfile>[
            visible.profiles.single.copyWith(name: 'Local terminal'),
          ],
        ),
      );
      final preserved = await delegate.load();
      expect(
        preserved.profiles.where((profile) => profile.isSsh).single.id,
        sshProfile.id,
      );
      await expectLater(
        composition.profiles.save(
          TerminalProfilesDocument(profiles: <TerminalProfile>[sshProfile]),
        ),
        throwsA(isA<CustomSshProfileConfigurationUnavailableException>()),
      );
    },
  );

  test(
    'URL-only remote runtime composes API repositories and fails closed',
    () async {
      final composition = PersistenceRepositoryComposition.forRuntime(
        DataApiRuntime.remote(baseUri: Uri.parse('https://sync.example.com/')),
        profileExportDirectoryResolver: () async => temporaryDirectory,
      );

      expect(composition.usesDataApi, isTrue);
      expect(composition.profiles, isA<DataApiProfileRepository>());
      expect(
        composition.terminalConfig,
        isA<DataApiTerminalConfigRepository>(),
      );
      await expectLater(
        composition.terminalConfig.load(),
        throwsA(isA<DataApiAuthenticationRequiredException>()),
      );
    },
  );

  test('bundled local runtime exposes API-backed custom SSH persistence', () {
    final composition = PersistenceRepositoryComposition.forRuntime(
      DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:42100/'),
        localAccessToken: 'local-access-token',
        encryptionKey: 'local-encryption-key',
        closeLocalSidecar: () async {},
      ),
      profileExportDirectoryResolver: () async => temporaryDirectory,
    );

    expect(composition.usesDataApi, isTrue);
    expect(composition.profiles, isA<DataApiProfileRepository>());
  });

  test(
    'API persistence keeps profile export as an explicit local copy',
    () async {
      final composition = PersistenceRepositoryComposition.forRuntime(
        DataApiRuntime.remote(
          baseUri: Uri.parse('https://sync.example.com/'),
          remoteAccessToken: 'access-token',
          encryptionKey: 'encryption-key-material',
        ),
        profileExportDirectoryResolver: () async => temporaryDirectory,
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
    },
  );

  test(
    'migration failure locks API persistence instead of seeding defaults',
    () async {
      final runtime = DataApiRuntime.remote(
        baseUri: Uri.parse('https://sync.example.com/'),
        remoteAccessToken: 'access-token',
        encryptionKey: 'encryption-key-material',
      );
      final composition = PersistenceRepositoryComposition.forRuntime(
        runtime,
        profileExportDirectoryResolver: () async => temporaryDirectory,
        dataApiPersistenceRequired: true,
        dataApiPersistenceUnavailable: true,
      );

      expect(composition.usesDataApi, isTrue);
      expect(composition.persistenceUnavailable, isTrue);
      await expectLater(
        composition.profiles.load(),
        throwsA(isA<DataApiPersistenceUnavailableException>()),
      );
    },
  );
}

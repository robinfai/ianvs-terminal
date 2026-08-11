import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/config/data_api_terminal_config_repository.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
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
    expect(composition.profiles, isA<ProfileRepository>());
    expect(composition.terminalConfig, isA<LocalTerminalConfigRepository>());
  });

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

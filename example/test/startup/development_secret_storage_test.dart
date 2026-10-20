import 'dart:io';

import 'package:app/data/services/data_api_local_credentials.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_remote_session_vault.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/startup/app_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const keychain = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Directory root;
  late Directory directory;
  var keychainCalls = 0;

  PortableMasterKeyRepository repository() => PortableMasterKeyRepository(
    storage: DevelopmentPortableMasterKeyStorage(
      directoryResolver: () async => directory,
    ),
    allowLegacyMigration: false,
  );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    root = await Directory.systemTemp.createTemp('trail-development-secrets-');
    directory = AppEnvironment.development.supportDirectory(root);
    keychainCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, (_) async {
          keychainCalls++;
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, null);
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  test(
    'development credentials survive restart without Keychain access',
    () async {
      final oldDatabase = File('${root.path}/development/data-api/ianvs.db');
      await oldDatabase.parent.create(recursive: true);
      await oldDatabase.writeAsString('preserve-old-encrypted-database');

      Future<DataApiLocalCredentials> credentials() =>
          KeychainDataApiLocalCredentialsProvider(
            dataEncryptionKeyStore:
                PortableMasterDataApiLocalDataEncryptionKeyStore(
                  masterKeyRepository: repository(),
                ),
          ).createForStart(directory);
      final first = await credentials();
      // Exercise the existing-database branch, not only first-run generation.
      await File(
        '${directory.path}/data-api/ianvs.db',
      ).writeAsString('fixture');
      final second = await credentials();
      expect(first.dataEncryptionKey == second.dataEncryptionKey, isTrue);
      expect(first.bearerToken != second.bearerToken, isTrue);
      expect(
        await oldDatabase.readAsString(),
        'preserve-old-encrypted-database',
      );
      expect(keychainCalls, 0);

      final secretDirectory = Directory('${directory.path}/secrets');
      expect((await secretDirectory.stat()).mode & 511, 448);
      final files = await secretDirectory.list().toList();
      expect(files, hasLength(1));
      expect((await files.single.stat()).mode & 511, 384);
    },
  );

  test('a damaged key is never replaced', () async {
    await repository().readOrCreate();
    final keyFile = File('${directory.path}/secrets/master-key.v1');
    for (final damaged in ['', 'invalid-key']) {
      await keyFile.writeAsString(damaged);
      await expectLater(repository().readOrCreate(), throwsFormatException);
      expect(await keyFile.readAsString(), damaged);
    }
    expect(keychainCalls, 0);
  });

  test(
    'development AI settings persist, delete and isolate production',
    () async {
      AiConfigurationStore store() => createAiConfigurationStore(
        appSupportDirectoryResolver: () async => root,
      );
      expect(store(), isA<DevelopmentAiConfigurationStore>());
      await store().write(const AiConfiguration.mock());
      expect(
        (await store().read())?.toJson(),
        const AiConfiguration.mock().toJson(),
      );
      final file = File('${directory.path}/secrets/ai-configuration.v1.json');
      expect((await file.stat()).mode & 511, 384);
      await store().write(null);
      expect(await store().read(), isNull);
      expect(await file.exists(), isFalse);
      expect(keychainCalls, 0);

      // Positive control: the same trap observes production's existing backend.
      final production = createAiConfigurationStore(
        environment: AppEnvironment.production,
      );
      expect(production, isA<SecureAiConfigurationStore>());
      await production.read();
      expect(keychainCalls, 1);
    },
  );

  test('SSH profiles and remote sessions do not fall back to Keychain', () async {
    PersistenceRepositoryComposition profiles() =>
        PersistenceRepositoryComposition.forRuntime(
          null,
          profileExportDirectoryResolver: () async => directory,
          masterKeyRepository: repository(),
        );
    final writer = profiles();
    final reader = profiles();
    addTearDown(writer.sync.close);
    addTearDown(reader.sync.close);
    await writer.profiles.save(
      TerminalProfilesDocument(
        profiles: [
          defaultTerminalProfile().copyWith(
            connection: const terminal.TerminalConnectionConfig.ssh(
              host: 'test.invalid',
              user: 'test',
              password: 'test-password',
            ),
          ),
        ],
      ),
    );
    expect(
      (await reader.profiles.load()).profiles.single.connection.password,
      'test-password',
    );
    final rawProfiles = await File(
      '${directory.path}/ianvs_profiles.json',
    ).readAsString();
    expect(rawProfiles, isNot(contains('test-password')));

    final master = repository();
    final vault = MigratingDataApiRemoteSessionStore(
      primary: EncryptedFileDataApiRemoteSessionStore(
        vaultFile: File(
          '${directory.path}/${EncryptedFileDataApiRemoteSessionStore.fileName}',
        ),
        masterKeyRepository: master,
      ),
      legacy: FlutterSecureDataApiRemoteSessionStore(),
      masterKeyRepository: master,
      legacyMigrationEnabled: false,
    );
    const slot = 'development_test_slot';
    expect(await vault.readSlot(slot), isNull);
    await vault.writeSlot(
      slot,
      DataApiRemoteSession(
        baseUri: Uri.parse('http://127.0.0.1:9999'),
        accessToken: 'test-token',
        encryptionKey: (await master.readOrCreate()).secret,
        expiresAt: DateTime.utc(2099),
      ),
    );
    expect(await vault.listSlotRefs(), {slot});
    expect((await vault.readSlot(slot))?.accessToken, 'test-token');
    await vault.deleteSlot(slot);
    expect(await vault.listSlotRefs(), isEmpty);
    expect(keychainCalls, 0);
  });
}

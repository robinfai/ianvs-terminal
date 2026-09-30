import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Linux master key secure storage', () {
    late FlutterSecureStoragePlatform originalPlatform;
    late _LinuxVaultPlatform vault;

    setUp(() {
      originalPlatform = FlutterSecureStoragePlatform.instance;
      vault = _LinuxVaultPlatform();
      FlutterSecureStoragePlatform.instance = vault;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    });

    tearDown(() {
      FlutterSecureStoragePlatform.instance = originalPlatform;
      debugDefaultTargetPlatformOverride = null;
    });

    test('uses the Linux platform vault and recovers the same key', () async {
      final first = PortableMasterKeyRepository(allowLegacyMigration: false);
      final key = await first.readOrCreate();
      final reopened = PortableMasterKeyRepository(allowLegacyMigration: false);

      expect((await reopened.read())?.secret == key.secret, isTrue);
      expect(vault.items.keys, [
        FlutterSecurePortableMasterKeyStorage.storageKey,
      ]);
      expect(vault.options.single.containsKey('synchronizable'), isFalse);
      expect(usesAutomaticallySynchronizedAppleKeychain, isFalse);
    });

    test('development and production keep separate vault items', () async {
      const production = FlutterSecurePortableMasterKeyStorage();
      const development = FlutterSecurePortableMasterKeyStorage.development();
      await production.write('production-fixture');
      await development.write('development-fixture');

      expect(await production.read(), 'production-fixture');
      expect(await development.read(), 'development-fixture');
      expect(vault.items, hasLength(2));
    });

    test('unavailable keyring fails without writing a replacement', () async {
      vault.failReads = true;
      final repository = PortableMasterKeyRepository(
        allowLegacyMigration: false,
      );

      await expectLater(
        repository.readOrCreate(),
        throwsA(isA<PlatformException>()),
      );
      expect(vault.items, isEmpty);
      expect(vault.options, isEmpty);
    });

    test('failed secure write is not cached as a usable key', () async {
      vault.failWrites = true;
      final repository = PortableMasterKeyRepository(
        allowLegacyMigration: false,
      );

      await expectLater(
        repository.readOrCreate(),
        throwsA(isA<PlatformException>()),
      );
      expect(await repository.read(), isNull);
      expect(vault.items, isEmpty);
      vault.failWrites = false;
      final recovered = await repository.readOrCreate();
      expect((await repository.read())?.secret == recovered.secret, isTrue);
      expect(vault.items, hasLength(1));
    });

    test(
      'a keyring failure never persists an SSH secret as plaintext',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'ianvs-linux-locked-vault-',
        );
        addTearDown(() => root.delete(recursive: true));
        vault.failWrites = true;
        final repository = ProfileRepository(
          directoryResolver: () async => root,
          secretCipher: ProfileSecretCipher(
            keyStore: PortableMasterProfileSecretKeyStore(
              masterKeyRepository: PortableMasterKeyRepository(
                allowLegacyMigration: false,
              ),
            ),
          ),
        );
        final profile = defaultTerminalProfile().copyWith(
          connection: const TerminalConnectionConfig.ssh(
            host: 'offline.example.test',
            user: 'fixture',
            password: 'must-never-be-written-in-plaintext',
          ),
        );
        await expectLater(
          repository.save(TerminalProfilesDocument(profiles: [profile])),
          throwsA(isA<PlatformException>()),
        );
        expect(
          await File('${root.path}/ianvs_profiles.json').exists(),
          isFalse,
        );
        expect(vault.items, isEmpty);
      },
    );
  });
}

final class _LinuxVaultPlatform extends FlutterSecureStoragePlatform {
  final items = <String, String>{};
  final options = <Map<String, String>>[];
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failReads) throw PlatformException(code: 'keyring_unavailable');
    return items[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failWrites) throw PlatformException(code: 'keyring_locked');
    this.options.add(Map.of(options));
    items[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => items.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => items.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(items);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      items.clear();
}

import 'dart:io';

import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_remote_session_vault.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/data/services/portable_master_key_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File vaultFile;
  late File marker;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ianvs-key-recovery-');
    vaultFile = File('${directory.path}/sessions.vault');
    marker = File('${directory.path}/migration.complete');
  });

  tearDown(() => directory.delete(recursive: true));

  test('verified legacy key replaces a mismatched synchronized key', () async {
    final correctKey = PortableMasterKey.generate();
    final wrongKey = PortableMasterKey.generate();
    await _writeVault(vaultFile, correctKey);
    final synchronizedStorage = _MemoryStorage(wrongKey.portableValue);
    final legacyStorage = _MemoryStorage(correctKey.portableValue);

    final recovered = await recoverVerifiedLegacyMacOsMasterKey(
      vaultFile: vaultFile,
      migrationMarker: marker,
      synchronizedRepository: PortableMasterKeyRepository(
        storage: synchronizedStorage,
      ),
      legacyStorage: legacyStorage,
      deleteLegacy: legacyStorage.delete,
    );

    expect(recovered, isTrue);
    expect(synchronizedStorage.encoded, correctKey.portableValue);
    expect(legacyStorage.encoded, isNull);
    expect(await marker.readAsString(), 'complete\n');
  });

  test('unverified legacy key preserves both Keychain items', () async {
    final correctKey = PortableMasterKey.generate();
    final synchronizedKey = PortableMasterKey.generate();
    final unrelatedLegacyKey = PortableMasterKey.generate();
    await _writeVault(vaultFile, correctKey);
    final synchronizedStorage = _MemoryStorage(synchronizedKey.portableValue);
    final legacyStorage = _MemoryStorage(unrelatedLegacyKey.portableValue);

    await expectLater(
      recoverVerifiedLegacyMacOsMasterKey(
        vaultFile: vaultFile,
        migrationMarker: marker,
        synchronizedRepository: PortableMasterKeyRepository(
          storage: synchronizedStorage,
        ),
        legacyStorage: legacyStorage,
        deleteLegacy: legacyStorage.delete,
      ),
      throwsA(isA<DataApiRemoteSessionFormatException>()),
    );

    expect(synchronizedStorage.encoded, synchronizedKey.portableValue);
    expect(legacyStorage.encoded, unrelatedLegacyKey.portableValue);
    expect(await marker.exists(), isFalse);
  });

  test(
    'matching synchronized key finishes without reading legacy key',
    () async {
      final correctKey = PortableMasterKey.generate();
      await _writeVault(vaultFile, correctKey);
      final synchronizedStorage = _MemoryStorage(correctKey.portableValue);
      final legacyStorage = _ThrowingReadStorage();

      final recovered = await recoverVerifiedLegacyMacOsMasterKey(
        vaultFile: vaultFile,
        migrationMarker: marker,
        synchronizedRepository: PortableMasterKeyRepository(
          storage: synchronizedStorage,
        ),
        legacyStorage: legacyStorage,
        deleteLegacy: () async {},
      );

      expect(recovered, isFalse);
      expect(await marker.exists(), isTrue);
    },
  );
}

Future<void> _writeVault(File file, PortableMasterKey key) async {
  await EncryptedFileDataApiRemoteSessionStore(
    vaultFile: file,
    masterKeyRepository: PortableMasterKeyRepository(
      storage: _MemoryStorage(key.portableValue),
    ),
  ).writeSlot(
    'fixture_slot_0001',
    DataApiRemoteSession(
      baseUri: Uri.parse('https://example.test/'),
      accessToken: 'fixture-token',
      encryptionKey: key.secret,
      expiresAt: DateTime.utc(2030),
    ),
  );
}

final class _MemoryStorage implements PortableMasterKeyStorage {
  _MemoryStorage(this.encoded);

  String? encoded;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String portableValue) async {
    encoded = portableValue;
  }

  Future<void> delete() async {
    encoded = null;
  }
}

final class _ThrowingReadStorage implements PortableMasterKeyStorage {
  @override
  Future<String?> read() => throw StateError('legacy storage was read');

  @override
  Future<void> write(String portableValue) async {}
}

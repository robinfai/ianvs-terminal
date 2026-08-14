import 'dart:io';

import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_remote_session_vault.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _MemoryMasterKeyStorage keyStorage;
  late PortableMasterKeyRepository keyRepository;
  late File vaultFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ianvs-session-vault-');
    keyStorage = _MemoryMasterKeyStorage();
    keyRepository = PortableMasterKeyRepository(storage: keyStorage);
    vaultFile = File('${directory.path}/sessions.vault');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('round-trips sessions without persisting the master key', () async {
    final key = await keyRepository.adoptLegacySecret(
      'shared-master-key-material',
    );
    final store = EncryptedFileDataApiRemoteSessionStore(
      vaultFile: vaultFile,
      masterKeyRepository: keyRepository,
    );
    final session = _session(key.secret);

    await store.writeSlot('credentialSlot000001', session);

    final encodedVault = await vaultFile.readAsString();
    expect(encodedVault, isNot(contains(session.accessToken)));
    expect(encodedVault, isNot(contains(key.secret)));
    expect(await store.listSlotRefs(), <String>{'credentialSlot000001'});
    expect(
      (await store.readSlot('credentialSlot000001'))?.encryptionKey,
      key.secret,
    );
    expect(keyStorage.writeCount, 1);
  });

  test('a copied master key opens the vault on another platform', () async {
    final sourceKey = await keyRepository.readOrCreate();
    final sourceStore = EncryptedFileDataApiRemoteSessionStore(
      vaultFile: vaultFile,
      masterKeyRepository: keyRepository,
    );
    await sourceStore.writeSlot(
      'credentialSlot000002',
      _session(sourceKey.secret),
    );
    final copied = await keyRepository.exportPortable();
    final destinationKeys = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    await destinationKeys.importPortable(copied);
    final destinationStore = EncryptedFileDataApiRemoteSessionStore(
      vaultFile: vaultFile,
      masterKeyRepository: destinationKeys,
    );

    final restored = await destinationStore.readSlot('credentialSlot000002');

    expect(restored?.accessToken, 'remote-access-token');
    expect(restored?.encryptionKey, sourceKey.secret);
  });

  test('different installed key cannot write a remote session', () async {
    final key = await keyRepository.adoptLegacySecret('first-master-key-1234');
    final store = EncryptedFileDataApiRemoteSessionStore(
      vaultFile: vaultFile,
      masterKeyRepository: keyRepository,
    );

    await expectLater(
      store.writeSlot(
        'credentialSlot000003',
        _session('different-master-key-1234'),
      ),
      throwsA(isA<PortableMasterKeyConflictException>()),
    );
    expect(await vaultFile.exists(), isFalse);
    expect(key.secret, 'first-master-key-1234');
  });

  test('tampering is rejected without replacing vault evidence', () async {
    final key = await keyRepository.readOrCreate();
    final store = EncryptedFileDataApiRemoteSessionStore(
      vaultFile: vaultFile,
      masterKeyRepository: keyRepository,
    );
    await store.writeSlot('credentialSlot000004', _session(key.secret));
    final original = await vaultFile.readAsString();
    await vaultFile.writeAsString(original.replaceFirst('ciphertext', 'macx'));
    final tampered = await vaultFile.readAsString();

    await expectLater(
      store.readSlot('credentialSlot000004'),
      throwsA(isA<DataApiRemoteSessionFormatException>()),
    );
    expect(await vaultFile.readAsString(), tampered);
  });

  test(
    'migrates predecessor Keychain sessions then removes their items',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final secureValues = <String, String>{};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        secureValues,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );
      final legacy = FlutterSecureDataApiRemoteSessionStore();
      await legacy.writeSlot(
        'credentialSlot000005',
        _session('legacy-remote-master-key'),
      );
      final primary = EncryptedFileDataApiRemoteSessionStore(
        vaultFile: vaultFile,
        masterKeyRepository: keyRepository,
      );
      final marker = File('${directory.path}/migration.complete');
      final store = MigratingDataApiRemoteSessionStore(
        primary: primary,
        legacy: legacy,
        masterKeyRepository: keyRepository,
        migrationMarker: marker,
      );

      expect(await store.listSlotRefs(), <String>{'credentialSlot000005'});

      expect(await marker.readAsString(), 'complete\n');
      expect(secureValues, isEmpty);
      expect(
        (await primary.readSlot('credentialSlot000005'))?.encryptionKey,
        'legacy-remote-master-key',
      );
    },
  );

  test(
    'authoritative startup migration never reads the legacy registry',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final secureValues = <String, String>{};
      final securePlatform = _ReadTrackingSecureStoragePlatform(secureValues);
      FlutterSecureStoragePlatform.instance = securePlatform;
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );
      final legacy = FlutterSecureDataApiRemoteSessionStore();
      await legacy.writeSlot(
        'credentialSlot000006',
        _session('legacy-authoritative-master-key'),
      );
      securePlatform.readKeys.clear();
      final primary = EncryptedFileDataApiRemoteSessionStore(
        vaultFile: vaultFile,
        masterKeyRepository: keyRepository,
      );
      final marker = File('${directory.path}/migration.complete');
      final store = MigratingDataApiRemoteSessionStore(
        primary: primary,
        legacy: legacy,
        masterKeyRepository: keyRepository,
        migrationMarker: marker,
      );

      final migrated = await store.readSlot('credentialSlot000006');

      expect(migrated?.accessToken, 'remote-access-token');
      expect(securePlatform.readKeys, <String>[
        'ianvs.data-api.remote-session.slot.v1.credentialSlot000006',
      ]);
      expect(await marker.readAsString(), 'complete\n');
      expect(secureValues, isEmpty);
      expect(await store.listSlotRefs(), <String>{'credentialSlot000006'});
      expect(securePlatform.readKeys, hasLength(1));
    },
  );
}

DataApiRemoteSession _session(String encryptionKey) {
  return DataApiRemoteSession(
    baseUri: Uri.parse('https://sync.example.com/'),
    accessToken: 'remote-access-token',
    encryptionKey: encryptionKey,
    expiresAt: DateTime.utc(2100),
  );
}

final class _MemoryMasterKeyStorage implements PortableMasterKeyStorage {
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
    writeCount += 1;
  }
}

final class _ReadTrackingSecureStoragePlatform
    extends TestFlutterSecureStoragePlatform {
  _ReadTrackingSecureStoragePlatform(super.data);

  final List<String> readKeys = <String>[];

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    readKeys.add(key);
    return super.read(key: key, options: options);
  }
}

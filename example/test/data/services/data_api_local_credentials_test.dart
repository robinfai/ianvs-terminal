import 'dart:io';
import 'dart:math';

import 'package:app/data/services/data_api_local_access_token.dart';
import 'package:app/data/services/data_api_local_credentials.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'each sidecar start gets a new Bearer and reuses the data key',
    () async {
      final dataKeyStore = _MemoryDataEncryptionKeyStore('stable-data-key');
      final provider = KeychainDataApiLocalCredentialsProvider(
        dataEncryptionKeyStore: dataKeyStore,
        bearerRandom: Random(1234),
      );
      final unusedDirectory = Directory.systemTemp;

      final first = await provider.createForStart(unusedDirectory);
      final second = await provider.createForStart(unusedDirectory);

      expect(isCanonicalDataApiLocalAccessToken(first.bearerToken), isTrue);
      expect(isCanonicalDataApiLocalAccessToken(second.bearerToken), isTrue);
      expect(first.bearerToken, isNot(second.bearerToken));
      expect(first.dataEncryptionKey, 'stable-data-key');
      expect(second.dataEncryptionKey, 'stable-data-key');
      expect(dataKeyStore.readCalls, 2);
    },
  );

  test('existing Keychain data key is returned without rewriting', () async {
    final previousPlatform = FlutterSecureStoragePlatform.instance;
    final values = <String, String>{
      FlutterSecureDataApiLocalDataEncryptionKeyStore.encryptionKeyStorageKey:
          'existing-encryption-key',
    };
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      values,
    );
    addTearDown(() => FlutterSecureStoragePlatform.instance = previousPlatform);

    final key = await FlutterSecureDataApiLocalDataEncryptionKeyStore()
        .readOrCreate();

    expect(key, 'existing-encryption-key');
    expect(values, hasLength(1));
  });

  test('missing Keychain data key is generated once and reused', () async {
    final previousPlatform = FlutterSecureStoragePlatform.instance;
    final values = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      values,
    );
    addTearDown(() => FlutterSecureStoragePlatform.instance = previousPlatform);
    final store = FlutterSecureDataApiLocalDataEncryptionKeyStore(
      secureRandom: Random(1234),
    );

    final first = await store.readOrCreate();
    final second = await store.readOrCreate();

    expect(isCanonicalDataApiLocalAccessToken(first), isTrue);
    expect(second, first);
    expect(
      values[FlutterSecureDataApiLocalDataEncryptionKeyStore
          .encryptionKeyStorageKey],
      first,
    );
  });

  test(
    'default production provider stores only the portable master key',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-local-master-key-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final provider = KeychainDataApiLocalCredentialsProvider(
        bearerRandom: Random(1234),
      );

      final first = await provider.createForStart(directory);
      final second = await provider.createForStart(directory);

      expect(first.dataEncryptionKey, second.dataEncryptionKey);
      expect(values.keys, <String>[
        FlutterSecurePortableMasterKeyStorage.storageKey,
      ]);
    },
  );

  test(
    'legacy local data key is adopted and its old item is removed',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{
        FlutterSecureDataApiLocalDataEncryptionKeyStore.encryptionKeyStorageKey:
            'legacy-local-data-key',
      };
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-local-key-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataDirectory = Directory('${directory.path}/data-api');
      await dataDirectory.create();
      await File('${dataDirectory.path}/ianvs.db').writeAsString('legacy');

      final credentials = await KeychainDataApiLocalCredentialsProvider()
          .createForStart(directory);

      expect(credentials.dataEncryptionKey, 'legacy-local-data-key');
      expect(values.keys, <String>[
        FlutterSecurePortableMasterKeyStorage.storageKey,
      ]);
      expect(
        PortableMasterKey.parsePortable(
          values[FlutterSecurePortableMasterKeyStorage.storageKey]!,
        ).secret,
        'legacy-local-data-key',
      );
      expect(
        await File(
          '${dataDirectory.path}/master-key-migration.v1.complete',
        ).exists(),
        isTrue,
      );
    },
  );

  test('existing local database without any key fails closed', () async {
    final previousPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
    addTearDown(() => FlutterSecureStoragePlatform.instance = previousPlatform);
    final directory = await Directory.systemTemp.createTemp(
      'ianvs-local-key-missing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final dataDirectory = Directory('${directory.path}/data-api');
    await dataDirectory.create();
    await File('${dataDirectory.path}/ianvs.db').writeAsString('legacy');

    await expectLater(
      KeychainDataApiLocalCredentialsProvider().createForStart(directory),
      throwsA(isA<DataApiLegacyLocalKeyMissingException>()),
    );
    expect(
      await File(
        '${dataDirectory.path}/master-key-migration.v1.complete',
      ).exists(),
      isFalse,
    );
  });

  test('local production stores no bundled API Bearer token', () {
    final exampleRoot = Directory.current.path.endsWith('example')
        ? Directory.current
        : Directory('${Directory.current.path}/example');
    final servicesRoot = Directory('${exampleRoot.path}/lib/data/services');
    final removedStore = File(
      '${servicesRoot.path}/data_api_secret_store.dart',
    );
    final bootstrap = File(
      '${servicesRoot.path}/data_api_bootstrap.dart',
    ).readAsStringSync();
    final localCredentials = File(
      '${servicesRoot.path}/data_api_local_credentials.dart',
    ).readAsStringSync();
    final masterKeyStorage = File(
      '${servicesRoot.path}/portable_master_key.dart',
    ).readAsStringSync();

    expect(removedStore.existsSync(), isFalse);
    expect(masterKeyStorage, contains('flutter_secure_storage'));
    expect(masterKeyStorage, contains('ianvs.master-key.v1'));
    expect(
      localCredentials,
      contains('PortableMasterDataApiLocalDataEncryptionKeyStore'),
    );
    // The old name remains read-only migration input for existing installs.
    expect(localCredentials, contains('ianvs.data-api.encryption-key.v1'));
    expect(
      '$bootstrap\n$localCredentials',
      isNot(contains('ianvs.data-api.local-access-token.v1')),
    );
    expect(localCredentials, isNot(contains('local-data-key.json')));
  });
}

final class _MemoryDataEncryptionKeyStore
    implements DataApiLocalDataEncryptionKeyStore {
  _MemoryDataEncryptionKeyStore(this.value);

  final String value;
  int readCalls = 0;

  @override
  Future<String> readOrCreate() async {
    readCalls += 1;
    return value;
  }
}

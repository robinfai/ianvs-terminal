import 'dart:io';
import 'dart:math';

import 'package:app/data/services/data_api_local_access_token.dart';
import 'package:app/data/services/data_api_local_credentials.dart';
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

    expect(removedStore.existsSync(), isFalse);
    expect(localCredentials, contains('flutter_secure_storage'));
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

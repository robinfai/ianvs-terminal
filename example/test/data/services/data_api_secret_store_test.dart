import 'package:app/data/services/data_api_secret_store.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storageKey = 'ianvs.data-api.local-access-token.v1';

  test(
    'current local token is returned without rewriting secure storage',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{
        storageKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      };
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );

      final token = await FlutterSecureDataApiSecretStore().localAccessToken();

      expect(token, values[storageKey]);
      expect(values, hasLength(1));
    },
  );

  for (final invalid in <String>[
    'short',
    List<String>.filled(43, 'é').join(),
    '${List<String>.filled(42, 'A').join()}\u0000',
    '${List<String>.filled(42, 'A').join()}=',
    '${List<String>.filled(42, 'A').join()}B',
  ]) {
    test(
      'invalid stored local token fails closed without replacement',
      () async {
        final previousPlatform = FlutterSecureStoragePlatform.instance;
        final values = <String, String>{storageKey: invalid};
        FlutterSecureStoragePlatform.instance =
            TestFlutterSecureStoragePlatform(values);
        addTearDown(
          () => FlutterSecureStoragePlatform.instance = previousPlatform,
        );

        await expectLater(
          FlutterSecureDataApiSecretStore().localAccessToken(),
          throwsA(isA<DataApiSecretStoreInvalidSecretException>()),
        );
        expect(values[storageKey], invalid);
      },
    );
  }

  test(
    'encryption-key storage keeps its independent existing contract',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{
        'ianvs.data-api.encryption-key.v1': 'existing-encryption-key',
      };
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );

      expect(
        await FlutterSecureDataApiSecretStore().encryptionKey(),
        'existing-encryption-key',
      );
    },
  );
}

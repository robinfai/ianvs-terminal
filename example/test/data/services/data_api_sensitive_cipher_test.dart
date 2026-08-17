import 'package:app/data/services/data_api_sensitive_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips client-only sensitive data', () async {
    final cipher = DataApiSensitiveCipher();
    final envelope = await cipher.encrypt(
      masterKey: 'test-master-key-material-with-enough-entropy',
      ownerId: 'owner-a',
      kind: 'profile',
      id: 'work',
      cleartext: const <String, Object?>{'password': 'secret'},
    );

    expect(envelope.toString(), isNot(contains('secret')));
    expect(
      await cipher.decrypt(
        masterKey: 'test-master-key-material-with-enough-entropy',
        ownerId: 'owner-a',
        kind: 'profile',
        id: 'work',
        envelope: envelope,
      ),
      const <String, Object?>{'password': 'secret'},
    );
  });

  test('wrong local key is a local authentication error', () async {
    final cipher = DataApiSensitiveCipher();
    final envelope = await cipher.encrypt(
      masterKey: 'first-test-master-key-material',
      ownerId: 'owner-a',
      kind: 'profile',
      id: 'work',
      cleartext: const <String, Object?>{'password': 'secret'},
    );

    await expectLater(
      cipher.decrypt(
        masterKey: 'different-test-master-key-material',
        ownerId: 'owner-a',
        kind: 'profile',
        id: 'work',
        envelope: envelope,
      ),
      throwsA(isA<DataApiSensitiveAuthenticationException>()),
    );
  });

  test('owner and resource identity are authenticated', () async {
    final cipher = DataApiSensitiveCipher();
    final envelope = await cipher.encrypt(
      masterKey: 'test-master-key-material-with-enough-entropy',
      ownerId: 'owner-a',
      kind: 'profile',
      id: 'work',
      cleartext: const <String, Object?>{'password': 'secret'},
    );

    await expectLater(
      cipher.decrypt(
        masterKey: 'test-master-key-material-with-enough-entropy',
        ownerId: 'owner-b',
        kind: 'profile',
        id: 'work',
        envelope: envelope,
      ),
      throwsA(isA<DataApiSensitiveAuthenticationException>()),
    );
  });
}

import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generates one reusable key and round-trips an encrypted secret',
    () async {
      final keyStore = _MemoryProfileSecretKeyStore();
      final firstCipher = ProfileSecretCipher(keyStore: keyStore);
      final envelope = await firstCipher.encrypt(
        profileId: 'ssh-production',
        field: 'password',
        value: 'correct horse battery staple',
      );

      final secondCipher = ProfileSecretCipher(keyStore: keyStore);
      final cleartext = await secondCipher.decrypt(
        profileId: 'ssh-production',
        field: 'password',
        envelope: envelope,
      );

      expect(cleartext, 'correct horse battery staple');
      expect(keyStore.writeCount, 1);
      expect(envelope['algorithm'], 'aes-256-gcm');
      expect(envelope.toString(), isNot(contains(cleartext)));
    },
  );

  test('binds ciphertext to its profile and field', () async {
    final cipher = ProfileSecretCipher(
      keyStore: _MemoryProfileSecretKeyStore(),
    );
    final envelope = await cipher.encrypt(
      profileId: 'profile-a',
      field: 'password',
      value: 'secret',
    );

    expect(
      () => cipher.decrypt(
        profileId: 'profile-b',
        field: 'password',
        envelope: envelope,
      ),
      throwsFormatException,
    );
    expect(
      () => cipher.decrypt(
        profileId: 'profile-a',
        field: 'privateKeyPassphrase',
        envelope: envelope,
      ),
      throwsFormatException,
    );
  });
}

final class _MemoryProfileSecretKeyStore implements ProfileSecretKeyStore {
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
    writeCount += 1;
  }
}

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import '../tools/verify_remote_session_vault_key.dart';

void main() {
  test(
    'matching portable key authenticates the remote session vault',
    () async {
      const secret = 'fixture-master-key-material';
      final vault = await _vaultFixture(secret, slotCount: 2);

      expect(
        await verifyRemoteSessionVaultKey(
          encodedVault: vault,
          portableKey: _portable(secret),
        ),
        2,
      );
    },
  );

  test('different portable key fails vault authentication', () async {
    final vault = await _vaultFixture('original-master-key', slotCount: 1);

    await expectLater(
      verifyRemoteSessionVaultKey(
        encodedVault: vault,
        portableKey: _portable('different-master-key'),
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}

String _portable(String secret) {
  final payload = base64UrlEncode(utf8.encode(secret)).replaceAll('=', '');
  return 'ianvs-key-v1.$payload';
}

Future<String> _vaultFixture(String secret, {required int slotCount}) async {
  final cleartext = jsonEncode(<String, Object?>{
    'version': 1,
    'slots': <String, Object?>{
      for (var index = 0; index < slotCount; index++)
        'fixture_slot_${index.toString().padLeft(4, '0')}': <String, Object?>{
          'base_url': 'https://example.test/',
          'access_token': 'token-$index',
          'expires_at': '2030-01-01T00:00:00.000Z',
        },
    },
  });
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(utf8.encode(secret)),
    nonce: utf8.encode('ianvs-portable-master-key-v1'),
    info: utf8.encode('remote-session-vault-v1'),
  );
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(cleartext),
    secretKey: key,
    aad: utf8.encode('ianvs:remote-session-vault:v1'),
  );
  return jsonEncode(<String, Object?>{
    'version': 1,
    'cipher': 'aes-256-gcm',
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  });
}

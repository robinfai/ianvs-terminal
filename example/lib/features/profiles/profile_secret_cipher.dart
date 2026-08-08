import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _profileKeyName = 'ianvs.ssh.profile-encryption-key.v1';
const String _envelopeAlgorithm = 'aes-256-gcm';
const int _envelopeSchemaVersion = 1;

abstract interface class ProfileSecretKeyStore {
  Future<String?> read();

  Future<void> write(String value);
}

final class FlutterSecureProfileSecretKeyStore
    implements ProfileSecretKeyStore {
  const FlutterSecureProfileSecretKeyStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      // The standard macOS login Keychain is secure and works with local
      // ad-hoc signatures. Data Protection Keychain requires a development
      // certificate and provisioning-profile entitlements.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _profileKeyName);

  @override
  Future<void> write(String value) {
    return _storage.write(key: _profileKeyName, value: value);
  }
}

/// Encrypts saved SSH secrets with AES-256-GCM.
///
/// Production stores the randomly generated symmetric key in the platform's
/// safe storage. Every field uses a fresh nonce and profile-specific
/// authenticated data, preventing ciphertext from being moved between fields.
final class ProfileSecretCipher {
  ProfileSecretCipher({
    ProfileSecretKeyStore keyStore = const FlutterSecureProfileSecretKeyStore(),
    AesGcm? algorithm,
  }) : _keyStore = keyStore,
       _algorithm = algorithm ?? AesGcm.with256bits();

  final ProfileSecretKeyStore _keyStore;
  final AesGcm _algorithm;
  Future<SecretKey>? _keyFuture;

  Future<Map<String, Object?>> encrypt({
    required String profileId,
    required String field,
    required String value,
  }) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _key(),
      aad: _associatedData(profileId, field),
    );
    return <String, Object?>{
      'schemaVersion': _envelopeSchemaVersion,
      'algorithm': _envelopeAlgorithm,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String> decrypt({
    required String profileId,
    required String field,
    required Object? envelope,
  }) async {
    final json = _asStringMap(envelope);
    if (json == null ||
        json['schemaVersion'] != _envelopeSchemaVersion ||
        json['algorithm'] != _envelopeAlgorithm) {
      throw const FormatException('Unsupported encrypted profile secret');
    }
    try {
      final nonce = base64Decode(_requiredString(json, 'nonce'));
      final ciphertext = base64Decode(_requiredString(json, 'ciphertext'));
      final mac = base64Decode(_requiredString(json, 'mac'));
      if (nonce.length != _algorithm.nonceLength ||
          mac.length != _algorithm.macAlgorithm.macLength) {
        throw const FormatException('Invalid encrypted profile secret');
      }
      final cleartext = await _algorithm.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: await _key(),
        aad: _associatedData(profileId, field),
      );
      return utf8.decode(cleartext);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Encrypted profile secret could not be decrypted',
      );
    }
  }

  Future<SecretKey> _key() => _keyFuture ??= _loadOrCreateKey();

  Future<SecretKey> _loadOrCreateKey() async {
    final encoded = await _keyStore.read();
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final bytes = base64Decode(encoded);
        if (bytes.length != 32) {
          throw const FormatException('Invalid profile encryption key');
        }
        return SecretKey(bytes);
      } on FormatException {
        rethrow;
      } on Object {
        throw const FormatException('Invalid profile encryption key');
      }
    }

    final generated = await _algorithm.newSecretKey();
    final bytes = await generated.extractBytes();
    if (bytes.length != 32) {
      throw StateError('Profile encryption key generation failed');
    }
    await _keyStore.write(base64Encode(bytes));
    return SecretKey(bytes);
  }

  List<int> _associatedData(String profileId, String field) {
    return utf8.encode('ianvs:ssh-profile:v1:$profileId:$field');
  }
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map(
    (key, entryValue) => MapEntry(key.toString(), entryValue as Object?),
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid encrypted profile secret');
  }
  return value;
}

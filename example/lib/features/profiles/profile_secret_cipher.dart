import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/services/portable_master_key.dart';

const String _profileKeyName = 'ianvs.ssh.profile-encryption-key.v1';
const String _envelopeAlgorithm = 'aes-256-gcm';
const int _envelopeSchemaVersion = 1;

abstract interface class ProfileSecretKeyStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
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

  @override
  Future<void> delete() => _storage.delete(key: _profileKeyName);
}

/// Adapts the one portable master key to the profile-envelope cipher.
final class PortableMasterProfileSecretKeyStore
    implements ProfileSecretKeyStore {
  PortableMasterProfileSecretKeyStore({
    PortableMasterKeyRepository? masterKeyRepository,
    ProfileSecretKeyStore? legacyStore,
  }) : _masterKeyRepository =
           masterKeyRepository ?? PortableMasterKeyRepository(),
       _legacyStore = legacyStore ?? const FlutterSecureProfileSecretKeyStore();

  static const _purpose = 'ssh-profile-secrets-v1';

  final PortableMasterKeyRepository _masterKeyRepository;
  final ProfileSecretKeyStore _legacyStore;
  bool _legacySecretObserved = false;

  bool get legacySecretObserved => _legacySecretObserved;

  @override
  Future<String> read() async {
    final masterKey = await _masterKeyRepository.readOrCreate(
      legacyLoader: () async {
        final legacy = await _legacyStore.read();
        _legacySecretObserved = legacy != null && legacy.isNotEmpty;
        return legacy;
      },
    );
    final derived = await masterKey.deriveKey(_purpose);
    return base64Encode(await derived.extractBytes());
  }

  @override
  Future<void> write(String value) {
    throw StateError('Profile keys are derived from the Ianvs master key.');
  }

  @override
  Future<void> delete() {
    throw StateError(
      'The Ianvs master key cannot be deleted as a profile key.',
    );
  }
}

/// Encrypts saved SSH secrets with AES-256-GCM.
///
/// Production derives this cipher key from the one portable master key. Every
/// field uses a fresh nonce and profile-specific authenticated data, preventing
/// ciphertext from being moved between fields.
final class ProfileSecretCipher {
  factory ProfileSecretCipher({
    ProfileSecretKeyStore? keyStore,
    ProfileSecretKeyStore? legacyKeyStore,
    AesGcm? algorithm,
  }) {
    if (keyStore != null) {
      return ProfileSecretCipher._(
        keyStore: keyStore,
        legacyKeyStore: legacyKeyStore,
        algorithm: algorithm ?? AesGcm.with256bits(),
      );
    }
    final legacy = legacyKeyStore ?? const FlutterSecureProfileSecretKeyStore();
    return ProfileSecretCipher._(
      keyStore: PortableMasterProfileSecretKeyStore(legacyStore: legacy),
      legacyKeyStore: legacy,
      algorithm: algorithm ?? AesGcm.with256bits(),
    );
  }

  ProfileSecretCipher._({
    required ProfileSecretKeyStore keyStore,
    required ProfileSecretKeyStore? legacyKeyStore,
    required AesGcm algorithm,
  }) : _keyStore = keyStore,
       _legacyKeyStore = legacyKeyStore,
       _algorithm = algorithm;

  final ProfileSecretKeyStore _keyStore;
  final ProfileSecretKeyStore? _legacyKeyStore;
  final AesGcm _algorithm;
  Future<SecretKey>? _keyFuture;
  Future<SecretKey?>? _legacyKeyFuture;
  bool _usedLegacyKey = false;

  bool get legacyMigrationRequired =>
      _usedLegacyKey ||
      switch (_keyStore) {
        final PortableMasterProfileSecretKeyStore store =>
          store.legacySecretObserved,
        _ => false,
      };

  Future<void> finishLegacyMigration() async {
    if (!legacyMigrationRequired) {
      return;
    }
    await _legacyKeyStore?.delete();
    _usedLegacyKey = false;
  }

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
      final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
      final associatedData = _associatedData(profileId, field);
      final cleartext = await _decryptWithFallback(box, associatedData);
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

  Future<SecretKey?> _legacyKey() {
    return _legacyKeyFuture ??= _loadExistingKey(_legacyKeyStore);
  }

  Future<List<int>> _decryptWithFallback(
    SecretBox box,
    List<int> associatedData,
  ) async {
    try {
      return await _algorithm.decrypt(
        box,
        secretKey: await _key(),
        aad: associatedData,
      );
    } on Object {
      final legacyKey = await _legacyKey();
      if (legacyKey == null) {
        rethrow;
      }
      final cleartext = await _algorithm.decrypt(
        box,
        secretKey: legacyKey,
        aad: associatedData,
      );
      _usedLegacyKey = true;
      return cleartext;
    }
  }

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

  Future<SecretKey?> _loadExistingKey(ProfileSecretKeyStore? store) async {
    if (store == null) {
      return null;
    }
    final encoded = await store.read();
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
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

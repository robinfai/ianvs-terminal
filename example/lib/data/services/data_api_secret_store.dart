import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DataApiSecretStore {
  Future<String> localAccessToken();

  Future<String> encryptionKey();
}

class FlutterSecureDataApiSecretStore implements DataApiSecretStore {
  FlutterSecureDataApiSecretStore({
    FlutterSecureStorage? storage,
    Random? secureRandom,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             // Local macOS builds use ad-hoc signatures. The standard login
             // Keychain remains encrypted and does not require the Data
             // Protection Keychain entitlement that ad-hoc builds lack.
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           ),
       _secureRandom = secureRandom ?? Random.secure();

  static const _localAccessTokenKey = 'ianvs.data-api.local-access-token.v1';
  static const _encryptionKeyKey = 'ianvs.data-api.encryption-key.v1';

  final FlutterSecureStorage _storage;
  final Random _secureRandom;

  @override
  Future<String> localAccessToken() => _getOrCreate(_localAccessTokenKey);

  @override
  Future<String> encryptionKey() => _getOrCreate(_encryptionKeyKey);

  Future<String> _getOrCreate(String key) async {
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final bytes = List<int>.generate(
      32,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    final generated = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: key, value: generated);
    return generated;
  }
}

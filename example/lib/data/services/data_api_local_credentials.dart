import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Process-scoped authentication plus the installation-scoped local data key.
final class DataApiLocalCredentials {
  const DataApiLocalCredentials({
    required this.bearerToken,
    required this.dataEncryptionKey,
  });

  /// A new canonical 32-byte token for one bundled-sidecar process.
  final String bearerToken;

  /// The stable Keychain value required to decrypt local SQLite resources.
  final String dataEncryptionKey;
}

abstract interface class DataApiLocalCredentialsProvider {
  Future<DataApiLocalCredentials> createForStart(Directory appSupportDirectory);
}

abstract interface class DataApiLocalDataEncryptionKeyStore {
  Future<String> readOrCreate();
}

/// Stores only the long-lived local data-encryption key in Keychain.
///
/// The bundled API Bearer token deliberately has no secure-storage key and is
/// generated independently for every sidecar process.
final class FlutterSecureDataApiLocalDataEncryptionKeyStore
    implements DataApiLocalDataEncryptionKeyStore {
  FlutterSecureDataApiLocalDataEncryptionKeyStore({
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

  static const encryptionKeyStorageKey = 'ianvs.data-api.encryption-key.v1';

  final FlutterSecureStorage _storage;
  final Random _secureRandom;

  @override
  Future<String> readOrCreate() async {
    final existing = await _storage.read(key: encryptionKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateCanonicalSecret(_secureRandom);
    await _storage.write(key: encryptionKeyStorageKey, value: generated);
    return generated;
  }
}

/// Creates one ephemeral Bearer token and reuses the Keychain data key.
final class KeychainDataApiLocalCredentialsProvider
    implements DataApiLocalCredentialsProvider {
  KeychainDataApiLocalCredentialsProvider({
    DataApiLocalDataEncryptionKeyStore? dataEncryptionKeyStore,
    Random? bearerRandom,
  }) : _dataEncryptionKeyStore =
           dataEncryptionKeyStore ??
           FlutterSecureDataApiLocalDataEncryptionKeyStore(),
       _bearerRandom = bearerRandom ?? Random.secure();

  final DataApiLocalDataEncryptionKeyStore _dataEncryptionKeyStore;
  final Random _bearerRandom;

  @override
  Future<DataApiLocalCredentials> createForStart(
    Directory appSupportDirectory,
  ) async {
    return DataApiLocalCredentials(
      bearerToken: _generateCanonicalSecret(_bearerRandom),
      dataEncryptionKey: await _dataEncryptionKeyStore.readOrCreate(),
    );
  }
}

String _generateCanonicalSecret(Random random) {
  final bytes = List<int>.generate(
    32,
    (_) => random.nextInt(256),
    growable: false,
  );
  return base64UrlEncode(bytes).replaceAll('=', '');
}

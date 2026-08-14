import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../platform/local_json_file.dart';
import 'portable_master_key.dart';

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

final class DataApiLegacyLocalKeyMissingException implements Exception {
  const DataApiLegacyLocalKeyMissingException();

  @override
  String toString() {
    return 'The existing local Data API database has no recoverable legacy '
        'key or imported Ianvs master key. Refusing to generate a replacement '
        'that could make existing data unreadable.';
  }
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

  Future<String?> readExisting() {
    return _storage.read(key: encryptionKeyStorageKey);
  }

  Future<void> deleteExisting() {
    return _storage.delete(key: encryptionKeyStorageKey);
  }

  @override
  Future<String> readOrCreate() async {
    final existing = await readExisting();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateCanonicalSecret(_secureRandom);
    await _storage.write(key: encryptionKeyStorageKey, value: generated);
    return generated;
  }
}

/// Resolves the local Data API secret from the one portable master key.
final class PortableMasterDataApiLocalDataEncryptionKeyStore
    implements DataApiLocalDataEncryptionKeyStore {
  PortableMasterDataApiLocalDataEncryptionKeyStore({
    PortableMasterKeyRepository? masterKeyRepository,
    FlutterSecureDataApiLocalDataEncryptionKeyStore? legacyStore,
  }) : _masterKeyRepository =
           masterKeyRepository ?? PortableMasterKeyRepository(),
       _legacyStore =
           legacyStore ?? FlutterSecureDataApiLocalDataEncryptionKeyStore();

  final PortableMasterKeyRepository _masterKeyRepository;
  final FlutterSecureDataApiLocalDataEncryptionKeyStore _legacyStore;

  @override
  Future<String> readOrCreate({bool migrateLegacy = true}) async {
    final legacy = migrateLegacy ? await _legacyStore.readExisting() : null;
    final existingMaster = migrateLegacy
        ? await _masterKeyRepository.read()
        : null;
    if (migrateLegacy &&
        (legacy == null || legacy.isEmpty) &&
        existingMaster == null) {
      throw const DataApiLegacyLocalKeyMissingException();
    }
    final key =
        existingMaster ??
        await _masterKeyRepository.readOrCreate(
          legacyLoader: legacy == null ? null : () async => legacy,
        );
    if (legacy != null && legacy.isNotEmpty) {
      if (legacy != key.secret) {
        throw const PortableMasterKeyConflictException();
      }
      await _legacyStore.deleteExisting();
    }
    return key.secret;
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
           PortableMasterDataApiLocalDataEncryptionKeyStore(),
       _bearerRandom = bearerRandom ?? Random.secure();

  final DataApiLocalDataEncryptionKeyStore _dataEncryptionKeyStore;
  final Random _bearerRandom;

  @override
  Future<DataApiLocalCredentials> createForStart(
    Directory appSupportDirectory,
  ) async {
    final dataEncryptionKey = await _readDataEncryptionKey(appSupportDirectory);
    return DataApiLocalCredentials(
      bearerToken: _generateCanonicalSecret(_bearerRandom),
      dataEncryptionKey: dataEncryptionKey,
    );
  }

  Future<String> _readDataEncryptionKey(Directory appSupportDirectory) async {
    final store = _dataEncryptionKeyStore;
    if (store is! PortableMasterDataApiLocalDataEncryptionKeyStore) {
      return store.readOrCreate();
    }
    final dataDirectory = Directory(
      '${appSupportDirectory.path}${Platform.pathSeparator}data-api',
    );
    final migrationMarker = File(
      '${dataDirectory.path}${Platform.pathSeparator}'
      'master-key-migration.v1.complete',
    );
    final legacyDatabase = File(
      '${dataDirectory.path}${Platform.pathSeparator}ianvs.db',
    );
    final migrationComplete = await migrationMarker.exists();
    final key = await store.readOrCreate(
      migrateLegacy: !migrationComplete && await legacyDatabase.exists(),
    );
    if (!migrationComplete) {
      await writeStringAtomically(migrationMarker, 'complete\n');
    }
    return key;
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

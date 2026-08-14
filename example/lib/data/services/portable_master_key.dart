import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'data_api_auth_contract.dart';

typedef PortableMasterKeyLegacyLoader = Future<String?> Function();

/// The one user-owned secret used to unlock every encrypted Ianvs data set.
///
/// [secret] is the value supplied to the Data API key contract. The portable
/// representation wraps that exact UTF-8 value in a versioned base64url
/// envelope so whitespace and non-ASCII legacy keys survive copy/paste.
final class PortableMasterKey {
  factory PortableMasterKey.fromSecret(String secret) {
    validateDataApiEncryptionKey(secret);
    return PortableMasterKey._(secret);
  }

  factory PortableMasterKey.generate([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(
      32,
      (_) => source.nextInt(256),
      growable: false,
    );
    return PortableMasterKey._(base64UrlEncode(bytes).replaceAll('=', ''));
  }

  factory PortableMasterKey.parsePortable(String encoded) {
    final normalized = encoded.trim();
    if (!normalized.startsWith(_portablePrefix)) {
      throw const FormatException(
        'Ianvs master key must start with ianvs-key-v1.',
      );
    }
    final payload = normalized.substring(_portablePrefix.length);
    if (payload.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload)) {
      throw const FormatException('Ianvs master key payload is invalid.');
    }
    try {
      final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
      final secret = utf8.decode(base64Url.decode(padded));
      final key = PortableMasterKey.fromSecret(secret);
      if (key.portableValue != normalized) {
        throw const FormatException(
          'Ianvs master key is not canonically encoded.',
        );
      }
      return key;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Ianvs master key payload is invalid.');
    }
  }

  const PortableMasterKey._(this.secret);

  static const _portablePrefix = 'ianvs-key-v1.';
  static const _derivationSalt = 'ianvs-portable-master-key-v1';

  /// Exact user-key material used by local and remote Data API instances.
  final String secret;

  /// Versioned text safe for explicit user-controlled copy/paste transfer.
  String get portableValue {
    final payload = base64UrlEncode(utf8.encode(secret)).replaceAll('=', '');
    return '$_portablePrefix$payload';
  }

  /// Derives a domain-separated 256-bit key from the sole portable secret.
  ///
  /// The user still owns and transfers one key. Domain separation prevents a
  /// nonce or protocol mistake in one encrypted file format from reusing the
  /// identical AES key in another format.
  Future<SecretKey> deriveKey(String purpose) {
    if (purpose.isEmpty) {
      throw ArgumentError.value(purpose, 'purpose', 'must not be empty');
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: utf8.encode(_derivationSalt),
      info: utf8.encode(purpose),
    );
  }
}

abstract interface class PortableMasterKeyStorage {
  Future<String?> read();

  Future<void> write(String portableValue);
}

/// The only production platform-vault item owned by Ianvs Terminal.
final class FlutterSecurePortableMasterKeyStorage
    implements PortableMasterKeyStorage {
  const FlutterSecurePortableMasterKeyStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      // Ad-hoc macOS development builds cannot use the Data Protection
      // Keychain. Android and Windows use the plugin's platform defaults.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _storage = storage;

  static const storageKey = 'ianvs.master-key.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: storageKey);

  @override
  Future<void> write(String portableValue) {
    return _storage.write(key: storageKey, value: portableValue);
  }
}

final class PortableMasterKeyConflictException implements Exception {
  const PortableMasterKeyConflictException();

  @override
  String toString() {
    return 'A different Ianvs master key is already installed. Replacing it '
        'without rotating every encrypted data set would make existing data '
        'unreadable.';
  }
}

/// Single source of truth for generation, migration, import and export.
///
/// Operations are serialized and an installed key is cached, avoiding repeated
/// platform-vault reads throughout the process lifetime.
final class PortableMasterKeyRepository {
  PortableMasterKeyRepository({PortableMasterKeyStorage? storage})
    : _storage = storage ?? const FlutterSecurePortableMasterKeyStorage();

  final PortableMasterKeyStorage _storage;
  Future<void> _operationTail = Future<void>.value();
  PortableMasterKey? _cached;

  Future<PortableMasterKey?> read() {
    return _serialized(() async {
      final cached = _cached;
      if (cached != null) {
        return cached;
      }
      final encoded = await _storage.read();
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      return _cached = PortableMasterKey.parsePortable(encoded);
    });
  }

  Future<PortableMasterKey> readOrCreate({
    PortableMasterKeyLegacyLoader? legacyLoader,
  }) {
    return _serialized(() async {
      final existing = await _readUnlocked();
      if (existing != null) {
        return existing;
      }
      final legacySecret = await legacyLoader?.call();
      final key = legacySecret == null || legacySecret.isEmpty
          ? PortableMasterKey.generate()
          : PortableMasterKey.fromSecret(legacySecret);
      await _storage.write(key.portableValue);
      return _cached = key;
    });
  }

  /// Adopts existing encrypted-data material without generating a new key.
  Future<PortableMasterKey> adoptLegacySecret(String secret) {
    return _serialized(() async {
      final candidate = PortableMasterKey.fromSecret(secret);
      final existing = await _readUnlocked();
      if (existing != null) {
        if (existing.secret != candidate.secret) {
          throw const PortableMasterKeyConflictException();
        }
        return existing;
      }
      await _storage.write(candidate.portableValue);
      return _cached = candidate;
    });
  }

  /// Installs a copied key only when no different key already owns local data.
  Future<PortableMasterKey> importPortable(String encoded) {
    final candidate = PortableMasterKey.parsePortable(encoded);
    return adoptLegacySecret(candidate.secret);
  }

  Future<String> exportPortable() async {
    return (await readOrCreate()).portableValue;
  }

  Future<PortableMasterKey?> _readUnlocked() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final encoded = await _storage.read();
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    return _cached = PortableMasterKey.parsePortable(encoded);
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

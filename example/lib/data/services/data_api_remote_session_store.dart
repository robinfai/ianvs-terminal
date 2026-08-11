import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../configuration/data_api_configuration.dart';
import 'data_api_auth_contract.dart';

/// Authenticated remote Data API material. This object must only be persisted
/// by a [DataApiRemoteSessionStore], never in the non-secret configuration
/// JSON file.
final class DataApiRemoteSession {
  static const int maximumAccessTokenBytes = 32 * 1024;

  factory DataApiRemoteSession({
    required Uri baseUri,
    required String accessToken,
    required String encryptionKey,
    required DateTime expiresAt,
  }) {
    final normalizedBaseUri = DataApiConfiguration.remote(
      baseUri.toString(),
    ).remoteBaseUri!;
    if (!isSecureDataApiRemoteOrigin(normalizedBaseUri)) {
      throw const FormatException(
        'Remote Data API sessions require HTTPS (HTTP is allowed only for a '
        'loopback development endpoint).',
      );
    }
    final accessTokenBytes = utf8.encode(accessToken).length;
    final normalizedEncryptionKey = validateDataApiEncryptionKey(encryptionKey);
    if (accessToken.trim().isEmpty) {
      throw const FormatException('Remote Data API access token is empty.');
    }
    if (accessTokenBytes > maximumAccessTokenBytes) {
      throw const FormatException('Remote Data API access token is too large.');
    }
    return DataApiRemoteSession._(
      baseUri: normalizedBaseUri,
      accessToken: accessToken,
      encryptionKey: normalizedEncryptionKey,
      expiresAt: expiresAt.toUtc(),
    );
  }

  factory DataApiRemoteSession.fromJson(Map<String, Object?> json) {
    if (json['version'] != currentVersion) {
      throw FormatException(
        'Unsupported remote Data API session version: ${json['version']}.',
      );
    }
    final baseUri = json['base_url'];
    final accessToken = json['access_token'];
    final encryptionKey = json['encryption_key'];
    final expiresAt = json['expires_at'];
    final parsedExpiry = expiresAt is String
        ? DateTime.tryParse(expiresAt)
        : null;
    if (baseUri is! String ||
        accessToken is! String ||
        encryptionKey is! String ||
        parsedExpiry == null) {
      throw const FormatException('Invalid remote Data API session.');
    }
    return DataApiRemoteSession(
      baseUri: Uri.parse(baseUri),
      accessToken: accessToken,
      encryptionKey: encryptionKey,
      expiresAt: parsedExpiry,
    );
  }

  const DataApiRemoteSession._({
    required this.baseUri,
    required this.accessToken,
    required this.encryptionKey,
    required this.expiresAt,
  });

  static const currentVersion = 1;

  final Uri baseUri;
  final String accessToken;
  final String encryptionKey;
  final DateTime expiresAt;

  bool isUsableFor(Uri requestedBaseUri, {DateTime? now}) {
    final normalizedRequested = DataApiConfiguration.remote(
      requestedBaseUri.toString(),
    ).remoteBaseUri!;
    return normalizedRequested == baseUri &&
        expiresAt.isAfter((now ?? DateTime.now()).toUtc());
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'base_url': baseUri.toString(),
    'access_token': accessToken,
    'encryption_key': encryptionKey,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

abstract interface class DataApiRemoteSessionStore {
  Future<DataApiRemoteSession?> read();

  Future<void> write(DataApiRemoteSession session);

  Future<void> clear();
}

abstract interface class DataApiRemoteSessionSlotStore {
  Future<Set<String>> listSlotRefs();

  Future<DataApiRemoteSession?> readSlot(String slotRef);

  Future<void> writeSlot(String slotRef, DataApiRemoteSession session);

  Future<void> deleteSlot(String slotRef);
}

final class DataApiRemoteSessionFormatException implements Exception {
  const DataApiRemoteSessionFormatException({
    required this.slotRef,
    required this.cause,
  });

  final String slotRef;
  final Object cause;

  @override
  String toString() {
    return 'The secure Data API credential in slot $slotRef is invalid: '
        '$cause. The original Keychain item was preserved and persistence '
        'remains locked.';
  }
}

final class DataApiRemoteSessionSlotExistsException implements Exception {
  const DataApiRemoteSessionSlotExistsException(this.slotRef);

  final String slotRef;

  @override
  String toString() =>
      'Secure Data API credential slot already exists: $slotRef.';
}

/// Stores the bearer token, its expiry and the per-user encryption key in the
/// platform credential vault. The ordinary configuration file contains only
/// deployment mode and base URL.
final class FlutterSecureDataApiRemoteSessionStore
    implements DataApiRemoteSessionStore, DataApiRemoteSessionSlotStore {
  FlutterSecureDataApiRemoteSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _sessionKey = 'ianvs.data-api.remote-session.v1';
  static const _slotKeyPrefix = 'ianvs.data-api.remote-session.slot.v1.';
  static const int _maximumEncodedSessionBytes = 64 * 1024;

  final FlutterSecureStorage _storage;

  @override
  Future<DataApiRemoteSession?> read() async {
    return _readKey(_sessionKey, slotRef: 'legacy');
  }

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) {
    return _readKey(_slotKey(slotRef), slotRef: slotRef);
  }

  Future<DataApiRemoteSession?> _readKey(
    String key, {
    required String slotRef,
  }) async {
    final encoded = await _storage.read(key: key);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      if (utf8.encode(encoded).length > _maximumEncodedSessionBytes) {
        throw const FormatException('Remote Data API session is too large.');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException(
          'Remote Data API session is not an object.',
        );
      }
      return DataApiRemoteSession.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value as Object?)),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataApiRemoteSessionFormatException(slotRef: slotRef, cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> write(DataApiRemoteSession session) {
    return _storage.write(key: _sessionKey, value: _encodeSession(session));
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async {
    final key = _slotKey(slotRef);
    if (await _storage.read(key: key) != null) {
      throw DataApiRemoteSessionSlotExistsException(slotRef);
    }
    await _storage.write(key: key, value: _encodeSession(session));
  }

  @override
  Future<void> deleteSlot(String slotRef) {
    return _storage.delete(key: _slotKey(slotRef));
  }

  @override
  Future<Set<String>> listSlotRefs() async {
    final stored = await _storage.readAll();
    final result = <String>{};
    for (final key in stored.keys) {
      if (!key.startsWith(_slotKeyPrefix)) {
        continue;
      }
      final slotRef = key.substring(_slotKeyPrefix.length);
      if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(slotRef)) {
        throw DataApiRemoteSessionFormatException(
          slotRef: slotRef.isEmpty ? '<empty>' : slotRef,
          cause: const FormatException(
            'Secure Data API credential slot identifier is invalid.',
          ),
        );
      }
      result.add(slotRef);
    }
    return Set<String>.unmodifiable(result);
  }

  String _slotKey(String slotRef) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(slotRef)) {
      throw FormatException(
        'Invalid secure Data API credential slot: $slotRef',
      );
    }
    return '$_slotKeyPrefix$slotRef';
  }

  String _encodeSession(DataApiRemoteSession session) {
    final encoded = jsonEncode(session.toJson());
    if (utf8.encode(encoded).length > _maximumEncodedSessionBytes) {
      throw const FormatException('Remote Data API session is too large.');
    }
    return encoded;
  }
}

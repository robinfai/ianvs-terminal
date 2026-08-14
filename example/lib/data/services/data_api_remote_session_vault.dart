import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../platform/local_json_file.dart';
import '../data_api_json.dart';
import 'data_api_remote_session_store.dart';
import 'portable_master_key.dart';

/// Stores remote bearer sessions in one master-key-encrypted local vault.
///
/// The platform credential vault contains only `ianvs.master-key.v1`; bearer
/// tokens and slot metadata are ciphertext in the application-support folder.
final class EncryptedFileDataApiRemoteSessionStore
    implements DataApiRemoteSessionSlotStore {
  EncryptedFileDataApiRemoteSessionStore({
    required File vaultFile,
    required PortableMasterKeyRepository masterKeyRepository,
    AesGcm? algorithm,
  }) : _vaultFile = vaultFile,
       _masterKeyRepository = masterKeyRepository,
       _algorithm = algorithm ?? AesGcm.with256bits();

  static const fileName = 'data-api-remote-sessions.v1.vault';
  static const _vaultVersion = 1;
  static const _cipher = 'aes-256-gcm';
  static const _keyPurpose = 'remote-session-vault-v1';
  static const _associatedData = 'ianvs:remote-session-vault:v1';
  static const int _maximumVaultBytes = 1024 * 1024;

  final File _vaultFile;
  final PortableMasterKeyRepository _masterKeyRepository;
  final AesGcm _algorithm;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<Set<String>> listSlotRefs() {
    return _serialized(() async {
      final vault = await _readVault();
      return Set<String>.unmodifiable(vault.keys);
    });
  }

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) {
    _validateSlotRef(slotRef);
    return _serialized(() async => (await _readVault())[slotRef]);
  }

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) {
    _validateSlotRef(slotRef);
    return _serialized(() async {
      final vault = await _readVault();
      if (vault.containsKey(slotRef)) {
        throw DataApiRemoteSessionSlotExistsException(slotRef);
      }
      final key = await _masterKeyRepository.readOrCreate();
      if (session.encryptionKey != key.secret) {
        throw const PortableMasterKeyConflictException();
      }
      await _writeVault(<String, DataApiRemoteSession>{
        ...vault,
        slotRef: session,
      }, key);
    });
  }

  @override
  Future<void> deleteSlot(String slotRef) {
    _validateSlotRef(slotRef);
    return _serialized(() async {
      final vault = await _readVault();
      if (!vault.containsKey(slotRef)) {
        return;
      }
      final key = await _requireExistingMasterKey();
      final updated = <String, DataApiRemoteSession>{...vault}..remove(slotRef);
      if (updated.isEmpty) {
        if (await _vaultFile.exists()) {
          await _vaultFile.delete();
        }
        return;
      }
      await _writeVault(updated, key);
    });
  }

  Future<Map<String, DataApiRemoteSession>> _readVault() async {
    if (!await _vaultFile.exists()) {
      return <String, DataApiRemoteSession>{};
    }
    final key = await _requireExistingMasterKey();
    try {
      final encoded = await _readBounded(_vaultFile, _maximumVaultBytes);
      final envelope = decodeDataApiJsonObject(
        encoded,
        documentName: 'Remote session vault',
      );
      if (envelope.keys.any(
            (field) =>
                field != 'version' &&
                field != 'cipher' &&
                field != 'nonce' &&
                field != 'ciphertext' &&
                field != 'mac',
          ) ||
          envelope['version'] != _vaultVersion ||
          envelope['cipher'] != _cipher) {
        throw const FormatException('Remote session vault is invalid.');
      }
      final nonce = _decodeRequiredBase64(envelope, 'nonce');
      final ciphertext = _decodeRequiredBase64(envelope, 'ciphertext');
      final mac = _decodeRequiredBase64(envelope, 'mac');
      if (nonce.length != _algorithm.nonceLength ||
          mac.length != _algorithm.macAlgorithm.macLength) {
        throw const FormatException('Remote session vault is invalid.');
      }
      final cleartext = await _algorithm.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: await key.deriveKey(_keyPurpose),
        aad: utf8.encode(_associatedData),
      );
      return _decodeCleartext(utf8.decode(cleartext), key);
    } on DataApiRemoteSessionFormatException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataApiRemoteSessionFormatException(slotRef: '<vault>', cause: error),
        stackTrace,
      );
    }
  }

  Map<String, DataApiRemoteSession> _decodeCleartext(
    String encoded,
    PortableMasterKey key,
  ) {
    final root = decodeDataApiJsonObject(
      encoded,
      documentName: 'Remote session vault cleartext',
    );
    if (root.keys.any((field) => field != 'version' && field != 'slots') ||
        root['version'] != _vaultVersion ||
        root['slots'] is! Map) {
      throw const FormatException('Remote session vault is invalid.');
    }
    final slots = _stringObject(
      root['slots'],
      documentName: 'Remote session vault slots',
    );
    final result = <String, DataApiRemoteSession>{};
    for (final entry in slots.entries) {
      _validateSlotRef(entry.key);
      final value = _stringObject(
        entry.value,
        documentName: 'Remote session vault slot',
      );
      if (value.keys.any(
        (field) =>
            field != 'base_url' &&
            field != 'access_token' &&
            field != 'expires_at',
      )) {
        throw const FormatException('Remote session vault slot is invalid.');
      }
      final baseUrl = value['base_url'];
      final accessToken = value['access_token'];
      final expiresAt = value['expires_at'];
      final parsedExpiry = expiresAt is String
          ? DateTime.tryParse(expiresAt)
          : null;
      if (baseUrl is! String ||
          accessToken is! String ||
          parsedExpiry == null) {
        throw const FormatException('Remote session vault slot is invalid.');
      }
      result[entry.key] = DataApiRemoteSession(
        baseUri: Uri.parse(baseUrl),
        accessToken: accessToken,
        encryptionKey: key.secret,
        expiresAt: parsedExpiry,
      );
    }
    return result;
  }

  Future<void> _writeVault(
    Map<String, DataApiRemoteSession> vault,
    PortableMasterKey key,
  ) async {
    final sortedRefs = vault.keys.toList(growable: false)..sort();
    final cleartext = jsonEncode(<String, Object?>{
      'version': _vaultVersion,
      'slots': <String, Object?>{
        for (final slotRef in sortedRefs)
          slotRef: <String, Object?>{
            'base_url': vault[slotRef]!.baseUri.toString(),
            'access_token': vault[slotRef]!.accessToken,
            'expires_at': vault[slotRef]!.expiresAt.toUtc().toIso8601String(),
          },
      },
    });
    final box = await _algorithm.encrypt(
      utf8.encode(cleartext),
      secretKey: await key.deriveKey(_keyPurpose),
      aad: utf8.encode(_associatedData),
    );
    final encoded = jsonEncode(<String, Object?>{
      'version': _vaultVersion,
      'cipher': _cipher,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    if (utf8.encode(encoded).length > _maximumVaultBytes) {
      throw const FormatException('Remote session vault is too large.');
    }
    await writeStringAtomically(_vaultFile, encoded);
  }

  Future<PortableMasterKey> _requireExistingMasterKey() async {
    final key = await _masterKeyRepository.read();
    if (key == null) {
      throw StateError(
        'The encrypted remote session vault exists, but its Ianvs master key '
        'is missing.',
      );
    }
    return key;
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

/// One-time bridge from predecessor per-slot Keychain items to the encrypted
/// file vault. New writes never create predecessor items.
final class MigratingDataApiRemoteSessionStore
    implements DataApiRemoteSessionSlotStore {
  MigratingDataApiRemoteSessionStore({
    required EncryptedFileDataApiRemoteSessionStore primary,
    required FlutterSecureDataApiRemoteSessionStore legacy,
    required PortableMasterKeyRepository masterKeyRepository,
    File? migrationMarker,
    bool legacyMigrationEnabled = true,
  }) : _primary = primary,
       _legacy = legacy,
       _masterKeyRepository = masterKeyRepository,
       _migrationMarker = migrationMarker,
       _legacyMigrationEnabled = legacyMigrationEnabled;

  final EncryptedFileDataApiRemoteSessionStore _primary;
  final FlutterSecureDataApiRemoteSessionStore _legacy;
  final PortableMasterKeyRepository _masterKeyRepository;
  final File? _migrationMarker;
  bool _legacyMigrationEnabled;

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async {
    final current = await _primary.readSlot(slotRef);
    if (current != null) {
      if (_legacyMigrationEnabled) {
        await _retireAuthoritativeLegacySlot(slotRef);
      }
      return current;
    }
    if (!_legacyMigrationEnabled) {
      return null;
    }
    final predecessor = await _legacy.readSlot(slotRef);
    if (predecessor == null) {
      return null;
    }
    await _masterKeyRepository.adoptLegacySecret(predecessor.encryptionKey);
    await _primary.writeSlot(slotRef, predecessor);
    final migrated = await _primary.readSlot(slotRef);
    if (migrated == null ||
        migrated.baseUri != predecessor.baseUri ||
        migrated.accessToken != predecessor.accessToken) {
      throw StateError('Remote session vault migration verification failed.');
    }
    await _retireAuthoritativeLegacySlot(slotRef);
    return migrated;
  }

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) {
    return _primary.writeSlot(slotRef, session);
  }

  @override
  Future<void> deleteSlot(String slotRef) async {
    await _primary.deleteSlot(slotRef);
    if (!_legacyMigrationEnabled) {
      return;
    }
    final legacyRefs = await _legacy.listSlotRefs();
    if (legacyRefs.contains(slotRef)) {
      await _legacy.deleteSlot(slotRef);
      await _legacy.deleteRegistryIfEmpty();
    }
  }

  @override
  Future<Set<String>> listSlotRefs() async {
    final result = <String>{...await _primary.listSlotRefs()};
    if (!_legacyMigrationEnabled) {
      return Set<String>.unmodifiable(result);
    }
    final legacyRefs = await _legacy.listSlotRefs();
    for (final slotRef in legacyRefs) {
      final current = await _primary.readSlot(slotRef);
      final migrated = current ?? await _migrateListedLegacySlot(slotRef);
      if (migrated != null) {
        result.add(slotRef);
      }
    }
    for (final slotRef in legacyRefs) {
      await _legacy.deleteSlot(slotRef);
    }
    await _legacy.deleteRegistryIfEmpty();
    await _finishLegacyMigration();
    return Set<String>.unmodifiable(result);
  }

  Future<DataApiRemoteSession?> _migrateListedLegacySlot(String slotRef) async {
    final predecessor = await _legacy.readSlot(slotRef);
    if (predecessor == null) {
      return null;
    }
    await _masterKeyRepository.adoptLegacySecret(predecessor.encryptionKey);
    await _primary.writeSlot(slotRef, predecessor);
    final migrated = await _primary.readSlot(slotRef);
    if (migrated == null ||
        migrated.baseUri != predecessor.baseUri ||
        migrated.accessToken != predecessor.accessToken) {
      throw StateError('Remote session vault migration verification failed.');
    }
    return migrated;
  }

  Future<void> _retireAuthoritativeLegacySlot(String slotRef) async {
    await _legacy.retireAuthoritativeSlot(slotRef);
    await _finishLegacyMigration();
  }

  Future<void> _finishLegacyMigration() async {
    if (_migrationMarker case final marker?) {
      await writeStringAtomically(marker, 'complete\n');
    }
    _legacyMigrationEnabled = false;
  }
}

List<int> _decodeRequiredBase64(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Remote session vault is invalid.');
  }
  try {
    return base64Decode(value);
  } on FormatException {
    throw const FormatException('Remote session vault is invalid.');
  }
}

Map<String, Object?> _stringObject(
  Object? value, {
  required String documentName,
}) {
  if (value is! Map) {
    throw FormatException('$documentName must contain a JSON object.');
  }
  return value.map((key, entryValue) {
    if (key is! String) {
      throw FormatException('$documentName contains a non-string key.');
    }
    return MapEntry(key, entryValue as Object?);
  });
}

void _validateSlotRef(String slotRef) {
  if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(slotRef)) {
    throw FormatException('Invalid secure Data API credential slot: $slotRef');
  }
}

Future<String> _readBounded(File file, int maximumBytes) async {
  final bytes = <int>[];
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > maximumBytes) {
      throw FormatException('${file.path} exceeds the size limit.');
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

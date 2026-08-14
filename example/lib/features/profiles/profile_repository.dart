import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../persistence/versioned_document.dart';
import '../ssh/ssh_feature_access.dart';
import 'profile_models.dart';
import 'profile_secret_cipher.dart';

typedef DirectoryResolver = Future<Directory> Function();
typedef TerminalProfilesDocumentUpdate =
    TerminalProfilesDocument Function(TerminalProfilesDocument current);

abstract class ProfileRepositoryPort {
  const ProfileRepositoryPort();

  Future<TerminalProfilesDocument> load();

  Future<void> save(TerminalProfilesDocument document);

  Future<VersionedDocument<TerminalProfilesDocument>> loadVersioned() async {
    return VersionedDocument<TerminalProfilesDocument>.local(await load());
  }

  Future<VersionedDocument<TerminalProfilesDocument>> saveVersioned(
    VersionedDocument<TerminalProfilesDocument> document,
  ) async {
    await save(document.value);
    return document.withRevision(null);
  }

  /// Applies a pure document mutation to the supplied snapshot.
  ///
  /// Remote implementations may replay [update] after an optimistic-
  /// concurrency conflict, so it must not perform I/O or externally visible
  /// side effects. The base implementation is sufficient for local stores;
  /// the Data API repository overrides this method with a bounded rebase.
  Future<VersionedDocument<TerminalProfilesDocument>> updateVersioned(
    TerminalProfilesDocumentUpdate update, {
    VersionedDocument<TerminalProfilesDocument>? base,
  }) async {
    final current = base ?? await loadVersioned();
    return saveVersioned(current.withValue(update(current.value)));
  }

  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  });
}

/// Exposes only local terminal profiles while preserving hidden SSH profiles
/// in the backing document.
///
/// Disabled and bundled-local Data API modes use this decorator. OpenSSH
/// config entries do not pass through this repository and remain available as
/// ephemeral session choices.
final class LocalTerminalOnlyProfileRepository extends ProfileRepositoryPort {
  const LocalTerminalOnlyProfileRepository({required this.delegate});

  final ProfileRepositoryPort delegate;

  @override
  Future<TerminalProfilesDocument> load() async {
    return _visibleDocument(await delegate.load());
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> loadVersioned() async {
    final loaded = await delegate.loadVersioned();
    return loaded.withValue(_visibleDocument(loaded.value));
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    _requireLocalOnly(document);
    final current = await delegate.load();
    await delegate.save(_mergeWithHiddenSsh(document, current));
  }

  @override
  Future<VersionedDocument<TerminalProfilesDocument>> saveVersioned(
    VersionedDocument<TerminalProfilesDocument> document,
  ) async {
    _requireLocalOnly(document.value);
    final current = await delegate.loadVersioned();
    final saved = await delegate.saveVersioned(
      VersionedDocument<TerminalProfilesDocument>(
        value: _mergeWithHiddenSsh(document.value, current.value),
        revision: document.revision,
      ),
    );
    return saved.withValue(_visibleDocument(saved.value));
  }

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) {
    _requireLocalOnly(document);
    return delegate.exportDocument(document, basename: basename);
  }

  TerminalProfilesDocument _visibleDocument(TerminalProfilesDocument document) {
    final profiles = document.profiles
        .where((profile) => !profile.isSsh)
        .toList(growable: false);
    final visibleProfiles = profiles.isEmpty
        ? <TerminalProfile>[defaultTerminalProfile()]
        : profiles;
    final visibleIds = {for (final profile in visibleProfiles) profile.id};
    return TerminalProfilesDocument(
      schemaVersion: document.schemaVersion,
      profiles: visibleProfiles,
      loadWarnings: [
        for (final warning in document.loadWarnings)
          if (warning.profileId == 'document' ||
              visibleIds.contains(warning.profileId))
            warning,
      ],
      secretClearIntents: {
        for (final entry in document.secretClearIntents.entries)
          if (visibleIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  TerminalProfilesDocument _mergeWithHiddenSsh(
    TerminalProfilesDocument visible,
    TerminalProfilesDocument current,
  ) {
    final visibleIds = {for (final profile in visible.profiles) profile.id};
    final hiddenSsh = current.profiles
        .where((profile) => profile.isSsh)
        .toList(growable: false);
    if (hiddenSsh.any((profile) => visibleIds.contains(profile.id))) {
      throw const CustomSshProfileConfigurationUnavailableException();
    }
    return TerminalProfilesDocument(
      schemaVersion: visible.schemaVersion,
      profiles: <TerminalProfile>[...visible.profiles, ...hiddenSsh],
      loadWarnings: visible.loadWarnings,
      secretClearIntents: visible.secretClearIntents,
    );
  }

  void _requireLocalOnly(TerminalProfilesDocument document) {
    if (document.profiles.any((profile) => profile.isSsh) ||
        document.secretClearIntents.isNotEmpty) {
      throw const CustomSshProfileConfigurationUnavailableException();
    }
  }
}

class ProfileRepository extends ProfileRepositoryPort {
  ProfileRepository({
    DirectoryResolver? directoryResolver,
    ProfileSecretCipher? secretCipher,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _secretCipher = secretCipher ?? ProfileSecretCipher();

  final DirectoryResolver _directoryResolver;
  final ProfileSecretCipher _secretCipher;
  final Map<String, Map<String, Object?>> _opaqueEncryptedSecretsByProfileId =
      <String, Map<String, Object?>>{};
  bool _opaqueSecretsInitialized = false;

  @override
  Future<TerminalProfilesDocument> load() async {
    final file = await _profilesFile();
    if (!await file.exists()) {
      final fallback = TerminalProfilesDocument(
        profiles: [defaultTerminalProfile(), vt220TerminalProfile()],
      );
      await save(fallback);
      return fallback;
    }

    final raw = await file.readAsString();
    final Map<String, Object?> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const UnsupportedTerminalProfilesSchemaVersion(null);
      }
      json = decoded;
    } on FormatException catch (error) {
      return _repairInvalidLoad(file, rawValueSummary: error.message);
    }
    try {
      TerminalProfilesDocument.validateSchema(json);
    } on FormatException catch (error) {
      return _repairInvalidLoad(file, rawValueSummary: error.message);
    }
    final decoded = await _decryptSecretsForLoad(json);
    final TerminalProfilesDocument parsed;
    try {
      parsed = TerminalProfilesDocument.fromJson(decoded.json);
    } on FormatException catch (error) {
      return _repairInvalidLoad(file, rawValueSummary: error.message);
    }
    final document = TerminalProfilesDocument(
      schemaVersion: parsed.schemaVersion,
      profiles: parsed.profiles,
      loadWarnings: <TerminalProfileLoadWarning>[
        ...parsed.loadWarnings,
        ...decoded.warnings,
      ],
    );
    return document;
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    if (document.schemaVersion !=
        TerminalProfilesDocument.currentSchemaVersion) {
      throw UnsupportedTerminalProfilesSchemaVersion(document.schemaVersion);
    }
    final file = await _profilesFile();
    await _initializeOpaqueSecretsFromExistingFile(file);
    final encoded = await _encodeForStorage(document);
    await writeStringAtomically(file, encoded);
    // Refresh only after the atomic write succeeds. A later save must reflect
    // secrets that were replaced or explicitly cleared, not the stale
    // envelopes captured by an earlier failed-decryption load.
    _captureOpaqueSecrets(
      decodeJsonObject(encoded, documentName: 'Profiles document'),
    );
  }

  @override
  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final safeBasename = _safeBasename(basename);
    final file = File(
      '${directory.path}/$safeBasename.ianvs-terminal-profiles.json',
    );
    await writeStringAtomically(file, document.encode());
    return file;
  }

  Future<File> _profilesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_profiles.json');
  }

  Future<String> _encodeForStorage(TerminalProfilesDocument document) async {
    final root = document.toJson();
    final rawProfiles = root['profiles'];
    if (rawProfiles is! List) {
      return jsonEncode(root);
    }
    for (var index = 0; index < document.profiles.length; index += 1) {
      final profile = document.profiles[index];
      if (!profile.isSsh || index >= rawProfiles.length) {
        continue;
      }
      final profileJson = _mutableStringMap(rawProfiles[index]);
      if (profileJson == null) {
        continue;
      }
      rawProfiles[index] = profileJson;
      final connection = _mutableStringMap(profileJson['connection']);
      if (connection == null) {
        continue;
      }
      profileJson['connection'] = connection;
      final opaque = _opaqueEncryptedSecretsByProfileId[profile.id];
      final opaqueFormat = opaque?['format'];
      final clearIntents =
          document.secretClearIntents[profile.id] ??
          const <ProfileSecretField>{};
      final hasCleartextSecret =
          profile.connection.password != null ||
          profile.connection.privateKeys.isNotEmpty ||
          profile.connection.privateKeyPassphrase != null ||
          profile.connection.x11AuthCookie != null;
      if ((hasCleartextSecret || clearIntents.isNotEmpty) &&
          opaque != null &&
          opaqueFormat != 'ianvs-profile-secrets-v1') {
        throw StateError(
          'Cannot safely update an unknown encryptedSecrets format for '
          'profile ${profile.id}.',
        );
      }
      final encrypted = opaque == null
          ? <String, Object?>{}
          : _deepCopyJsonMap(opaque);
      for (final field in clearIntents) {
        encrypted.remove(_secretFieldName(field));
      }
      final password = profile.connection.password;
      if (password != null) {
        encrypted['password'] = await _secretCipher.encrypt(
          profileId: profile.id,
          field: 'password',
          value: password,
        );
      }
      // Private key values may contain complete PEM/OpenSSH key documents.
      // They must never be copied into the ordinary profile JSON. Encrypt the
      // complete list as one authenticated field so key order is preserved.
      connection.remove('privateKeys');
      final privateKeys = profile.connection.privateKeys;
      if (privateKeys.isNotEmpty) {
        encrypted['privateKeys'] = await _secretCipher.encrypt(
          profileId: profile.id,
          field: 'privateKeys',
          value: jsonEncode(privateKeys),
        );
      }
      final passphrase = profile.connection.privateKeyPassphrase;
      if (passphrase != null) {
        encrypted['privateKeyPassphrase'] = await _secretCipher.encrypt(
          profileId: profile.id,
          field: 'privateKeyPassphrase',
          value: passphrase,
        );
      }
      final x11AuthCookie = profile.connection.x11AuthCookie;
      if (x11AuthCookie != null) {
        encrypted['x11AuthCookie'] = await _secretCipher.encrypt(
          profileId: profile.id,
          field: 'x11AuthCookie',
          value: x11AuthCookie,
        );
      }
      if (hasCleartextSecret || opaqueFormat == 'ianvs-profile-secrets-v1') {
        encrypted['format'] = 'ianvs-profile-secrets-v1';
      }
      if (encrypted.keys.any((key) => key != 'format')) {
        connection['encryptedSecrets'] = encrypted;
      } else {
        connection.remove('encryptedSecrets');
      }
    }
    return jsonEncode(root);
  }

  Future<
    ({Map<String, Object?> json, List<TerminalProfileLoadWarning> warnings})
  >
  _decryptSecretsForLoad(Map<String, Object?> root) async {
    final warnings = <TerminalProfileLoadWarning>[];
    final rawProfiles = root['profiles'];
    if (rawProfiles is! List) {
      _opaqueSecretsInitialized = true;
      return (json: root, warnings: warnings);
    }

    _captureOpaqueSecrets(root);

    for (var index = 0; index < rawProfiles.length; index += 1) {
      final profile = _mutableStringMap(rawProfiles[index]);
      if (profile == null) {
        continue;
      }
      rawProfiles[index] = profile;
      final connection = _mutableStringMap(profile['connection']);
      if (connection == null || connection['type'] != 'ssh') {
        continue;
      }
      profile['connection'] = connection;
      final profileId = _nonEmptyString(profile['id']) ?? 'profile-$index';
      final profileName = _nonEmptyString(profile['name']) ?? profileId;
      if (connection.containsKey('password') ||
          connection.containsKey('privateKeyPassphrase') ||
          connection.containsKey('x11AuthCookie')) {
        throw const UnsupportedTerminalProfilePlaintextSecrets();
      }
      if (_containsInlinePrivateKey(connection['privateKeys'])) {
        throw const UnsupportedTerminalProfilePlaintextSecrets();
      }
      final encrypted = _mutableStringMap(connection['encryptedSecrets']);
      if (encrypted == null) {
        continue;
      }
      if (encrypted['format'] != 'ianvs-profile-secrets-v1') {
        continue;
      }
      for (final field in const <String>[
        'password',
        'privateKeys',
        'privateKeyPassphrase',
        'x11AuthCookie',
      ]) {
        if (!encrypted.containsKey(field)) {
          continue;
        }
        try {
          final cleartext = await _secretCipher.decrypt(
            profileId: profileId,
            field: field,
            envelope: encrypted[field],
          );
          connection[field] = field == 'privateKeys'
              ? _decodeEncryptedPrivateKeys(cleartext)
              : cleartext;
          final opaque = _opaqueEncryptedSecretsByProfileId[profileId];
          opaque?.remove(field);
          if (opaque != null && opaque.keys.every((key) => key == 'format')) {
            _opaqueEncryptedSecretsByProfileId.remove(profileId);
          }
        } on Object {
          warnings.add(
            TerminalProfileLoadWarning(
              profileId: profileId,
              profileName: profileName,
              path: 'connection.encryptedSecrets.$field',
              rawValueSummary: 'encrypted secret',
              fallbackSummary:
                  'left the secret empty because secure decryption failed',
            ),
          );
        }
      }
    }
    return (json: root, warnings: warnings);
  }

  Future<void> _initializeOpaqueSecretsFromExistingFile(File file) async {
    if (_opaqueSecretsInitialized) {
      return;
    }
    if (!await file.exists()) {
      _opaqueSecretsInitialized = true;
      return;
    }
    try {
      final root = decodeJsonObject(
        await file.readAsString(),
        documentName: 'Profiles document',
      );
      _validateCanonicalCurrentProfilesDocument(root);
      _captureOpaqueSecrets(root);
    } on UnsupportedTerminalProfilesSchemaVersion {
      rethrow;
    } on FormatException {
      // A direct save remains an explicit replacement of a malformed file.
      // load() is the path that quarantines and repairs invalid JSON.
      _opaqueSecretsInitialized = true;
      _opaqueEncryptedSecretsByProfileId.clear();
    }
  }

  void _validateCanonicalCurrentProfilesDocument(Map<String, Object?> root) {
    TerminalProfilesDocument.validateSchema(root);
    final plain = _deepCopyJsonMap(root);
    final rawProfiles = plain['profiles'];
    if (rawProfiles is List) {
      for (var index = 0; index < rawProfiles.length; index += 1) {
        final profile = _mutableStringMap(rawProfiles[index]);
        if (profile == null) {
          continue;
        }
        rawProfiles[index] = profile;
        final connection = _mutableStringMap(profile['connection']);
        if (connection == null) {
          continue;
        }
        profile['connection'] = connection;
        final encrypted = connection['encryptedSecrets'];
        if (encrypted != null && encrypted is! Map) {
          throw const FormatException(
            'Profile encryptedSecrets must be a JSON object.',
          );
        }
        connection.remove('encryptedSecrets');
      }
    }
    final decoded = TerminalProfilesDocument.fromJson(plain);
    if (decoded.loadWarnings.isNotEmpty ||
        !_jsonValuesEquivalent(decoded.toJson(), plain)) {
      throw const FormatException(
        'Profiles document is not canonical current-schema data.',
      );
    }
  }

  void _captureOpaqueSecrets(Map<String, Object?> root) {
    _opaqueSecretsInitialized = true;
    _opaqueEncryptedSecretsByProfileId.clear();
    final rawProfiles = root['profiles'];
    if (rawProfiles is! List) {
      return;
    }
    for (var index = 0; index < rawProfiles.length; index += 1) {
      final profile = _mutableStringMap(rawProfiles[index]);
      final profileId = _nonEmptyString(profile?['id']);
      final connection = _mutableStringMap(profile?['connection']);
      final encrypted = _mutableStringMap(connection?['encryptedSecrets']);
      if (profileId == null ||
          connection?['type'] != 'ssh' ||
          encrypted == null) {
        continue;
      }
      _opaqueEncryptedSecretsByProfileId[profileId] = _deepCopyJsonMap(
        encrypted,
      );
    }
  }

  String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty) {
      return 'ianvs-profiles';
    }
    return safe;
  }

  Future<TerminalProfilesDocument> _repairInvalidLoad(
    File file, {
    required String rawValueSummary,
  }) async {
    await quarantineCorruptFile(file);
    final repaired = TerminalProfilesDocument(
      profiles: [defaultTerminalProfile(), vt220TerminalProfile()],
      loadWarnings: [
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'document',
          rawValueSummary: rawValueSummary,
          fallbackSummary:
              'quarantined corrupt file and saved fallback profiles',
        ),
      ],
    );
    await save(repaired);
    return repaired;
  }
}

final class UnsupportedTerminalProfilePlaintextSecrets implements Exception {
  const UnsupportedTerminalProfilePlaintextSecrets();

  @override
  String toString() =>
      'Plaintext secrets in persisted terminal profiles are unsupported.';
}

String _secretFieldName(ProfileSecretField field) => switch (field) {
  ProfileSecretField.password => 'password',
  ProfileSecretField.privateKeys => 'privateKeys',
  ProfileSecretField.privateKeyPassphrase => 'privateKeyPassphrase',
  ProfileSecretField.x11AuthCookie => 'x11AuthCookie',
};

List<String> _decodeEncryptedPrivateKeys(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List ||
      decoded.any(
        (entry) => entry is! String || entry.isEmpty || entry.trim() != entry,
      )) {
    throw const FormatException('Invalid encrypted private keys');
  }
  return decoded.cast<String>().toList(growable: false);
}

bool _containsInlinePrivateKey(Object? value) {
  if (value is! List) {
    return false;
  }
  return value.whereType<String>().any((entry) {
    final trimmed = entry.trimLeft();
    return trimmed.startsWith('-----BEGIN ') ||
        trimmed.startsWith('PuTTY-User-Key-File-');
  });
}

Map<String, Object?>? _mutableStringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map(
    (key, entryValue) => MapEntry(key.toString(), entryValue as Object?),
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  return source.map((key, value) => MapEntry(key, _deepCopyJsonValue(value)));
}

bool _jsonValuesEquivalent(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length ||
        left.keys.any((key) => !right.containsKey(key))) {
      return false;
    }
    return left.keys.every(
      (key) => _jsonValuesEquivalent(left[key], right[key]),
    );
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_jsonValuesEquivalent(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

Object? _deepCopyJsonValue(Object? value) {
  return switch (value) {
    final Map<Object?, Object?> map => map.map(
      (key, entryValue) =>
          MapEntry(key.toString(), _deepCopyJsonValue(entryValue)),
    ),
    final List<Object?> list =>
      list.map(_deepCopyJsonValue).toList(growable: false),
    _ => value,
  };
}

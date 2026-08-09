import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'profile_models.dart';
import 'profile_secret_cipher.dart';

typedef DirectoryResolver = Future<Directory> Function();

class ProfileRepository {
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
      json = decodeJsonObject(raw, documentName: 'Profiles document');
    } on FormatException catch (error) {
      return _repairInvalidLoad(file, rawValueSummary: error.message);
    }
    final decoded = await _decryptSecretsForLoad(json);
    final parsed = TerminalProfilesDocument.fromJson(decoded.json);
    final document = TerminalProfilesDocument(
      schemaVersion: parsed.schemaVersion,
      profiles: parsed.profiles,
      loadWarnings: <TerminalProfileLoadWarning>[
        ...parsed.loadWarnings,
        ...decoded.warnings,
      ],
    );
    if (decoded.canMigrateLegacyPlaintextSecrets) {
      // A migration failure must surface to the caller. Treating it as a JSON
      // parse failure would quarantine an otherwise valid plaintext document.
      await save(document);
    }
    return document;
  }

  Future<void> save(TerminalProfilesDocument document) async {
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
    ({
      Map<String, Object?> json,
      List<TerminalProfileLoadWarning> warnings,
      bool canMigrateLegacyPlaintextSecrets,
    })
  >
  _decryptSecretsForLoad(Map<String, Object?> root) async {
    final warnings = <TerminalProfileLoadWarning>[];
    var hadLegacyPlaintextSecrets = false;
    var encryptedSecretFailed = false;
    var hasUnknownEncryptedSecretsFormat = false;
    final rawProfiles = root['profiles'];
    if (rawProfiles is! List) {
      _opaqueSecretsInitialized = true;
      return (
        json: root,
        warnings: warnings,
        canMigrateLegacyPlaintextSecrets: false,
      );
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
        hadLegacyPlaintextSecrets = true;
      }
      final encrypted = _mutableStringMap(connection['encryptedSecrets']);
      if (encrypted == null) {
        continue;
      }
      if (encrypted['format'] != 'ianvs-profile-secrets-v1') {
        hasUnknownEncryptedSecretsFormat = true;
        continue;
      }
      for (final field in const <String>[
        'password',
        'privateKeyPassphrase',
        'x11AuthCookie',
      ]) {
        if (!encrypted.containsKey(field)) {
          continue;
        }
        try {
          connection[field] = await _secretCipher.decrypt(
            profileId: profileId,
            field: field,
            envelope: encrypted[field],
          );
          final opaque = _opaqueEncryptedSecretsByProfileId[profileId];
          opaque?.remove(field);
          if (opaque != null && opaque.keys.every((key) => key == 'format')) {
            _opaqueEncryptedSecretsByProfileId.remove(profileId);
          }
        } on Object {
          encryptedSecretFailed = true;
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
    return (
      json: root,
      warnings: warnings,
      canMigrateLegacyPlaintextSecrets:
          hadLegacyPlaintextSecrets &&
          !encryptedSecretFailed &&
          !hasUnknownEncryptedSecretsFormat,
    );
  }

  Future<void> _initializeOpaqueSecretsFromExistingFile(File file) async {
    if (_opaqueSecretsInitialized) {
      return;
    }
    _opaqueSecretsInitialized = true;
    if (!await file.exists()) {
      return;
    }
    try {
      final root = decodeJsonObject(
        await file.readAsString(),
        documentName: 'Profiles document',
      );
      _captureOpaqueSecrets(root);
    } on FormatException {
      // A direct save remains an explicit replacement of a malformed file.
      // load() is the path that quarantines and repairs invalid JSON.
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

String _secretFieldName(ProfileSecretField field) => switch (field) {
  ProfileSecretField.password => 'password',
  ProfileSecretField.privateKeyPassphrase => 'privateKeyPassphrase',
  ProfileSecretField.x11AuthCookie => 'x11AuthCookie',
};

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

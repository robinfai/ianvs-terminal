import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

const _portablePrefix = 'ianvs-key-v1.';
const _derivationSalt = 'ianvs-portable-master-key-v1';
const _keyPurpose = 'remote-session-vault-v1';
const _associatedData = 'ianvs:remote-session-vault:v1';

/// Verifies that [portableKey] authenticates [encodedVault].
///
/// The decrypted credential material is validated in memory and never
/// returned, keeping this helper safe to use in one-time recovery scripts.
Future<int> verifyRemoteSessionVaultKey({
  required String encodedVault,
  required String portableKey,
}) async {
  final normalizedKey = portableKey.trim();
  if (!normalizedKey.startsWith(_portablePrefix)) {
    throw const FormatException(
      'Ianvs master key must start with ianvs-key-v1.',
    );
  }
  final payload = normalizedKey.substring(_portablePrefix.length);
  if (payload.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload)) {
    throw const FormatException('Ianvs master key payload is invalid.');
  }
  final paddedPayload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
  final secret = utf8.decode(base64Url.decode(paddedPayload));
  final canonicalPayload = base64UrlEncode(
    utf8.encode(secret),
  ).replaceAll('=', '');
  if ('$_portablePrefix$canonicalPayload' != normalizedKey) {
    throw const FormatException('Ianvs master key is not canonically encoded.');
  }

  final envelope = _stringObject(
    jsonDecode(encodedVault),
    documentName: 'Remote session vault',
  );
  if (envelope['version'] != 1 || envelope['cipher'] != 'aes-256-gcm') {
    throw const FormatException('Remote session vault is invalid.');
  }
  final algorithm = AesGcm.with256bits();
  final nonce = _decodeRequiredBase64(envelope, 'nonce');
  final ciphertext = _decodeRequiredBase64(envelope, 'ciphertext');
  final mac = _decodeRequiredBase64(envelope, 'mac');
  if (nonce.length != algorithm.nonceLength ||
      mac.length != algorithm.macAlgorithm.macLength) {
    throw const FormatException('Remote session vault is invalid.');
  }

  final derivedKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
        secretKey: SecretKey(utf8.encode(secret)),
        nonce: utf8.encode(_derivationSalt),
        info: utf8.encode(_keyPurpose),
      );
  final cleartext = await algorithm.decrypt(
    SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
    secretKey: derivedKey,
    aad: utf8.encode(_associatedData),
  );
  final root = _stringObject(
    jsonDecode(utf8.decode(cleartext)),
    documentName: 'Remote session vault cleartext',
  );
  final slots = root['slots'];
  if (root['version'] != 1 || slots is! Map<Object?, Object?>) {
    throw const FormatException('Remote session vault is invalid.');
  }
  return slots.length;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tools/verify_remote_session_vault_key.dart '
      '<vault-file>',
    );
    exitCode = 64;
    return;
  }
  final key = await utf8.decoder.bind(stdin).join();
  try {
    final slotCount = await verifyRemoteSessionVaultKey(
      encodedVault: await File(arguments.single).readAsString(),
      portableKey: key,
    );
    stdout.writeln('Master key matches vault ($slotCount slot(s)).');
  } on SecretBoxAuthenticationError {
    stderr.writeln('Master key does not match vault.');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
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
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$documentName must contain a JSON object.');
  }
  return value.map((key, entryValue) {
    if (key is! String) {
      throw FormatException('$documentName contains a non-string key.');
    }
    return MapEntry(key, entryValue);
  });
}

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final class DataApiEncryptionKeyRequiredException implements Exception {
  const DataApiEncryptionKeyRequiredException();

  @override
  String toString() =>
      'The local Ianvs master key is required to unlock sensitive data.';
}

final class DataApiSensitiveAuthenticationException implements Exception {
  const DataApiSensitiveAuthenticationException({
    required this.kind,
    required this.id,
  });

  final String kind;
  final String id;

  @override
  String toString() =>
      'Sensitive data for $kind/$id could not be authenticated with the local '
      'Ianvs master key.';
}

/// Client-only authenticated encryption for the opaque `sensitive` API field.
///
/// The server stores this envelope as JSON and never receives the master key.
/// The authenticated owner and resource identity prevent ciphertext from being
/// replayed under a different account, kind, or resource ID.
final class DataApiSensitiveCipher {
  DataApiSensitiveCipher({AesGcm? algorithm})
    : _algorithm = algorithm ?? AesGcm.with256bits();

  static const int envelopeVersion = 1;
  static const String cipherName = 'aes-256-gcm';
  static const String _derivationSalt = 'ianvs-portable-master-key-v1';
  static const String _purpose = 'data-api-sensitive-v1';

  final AesGcm _algorithm;

  Future<Map<String, Object?>> encrypt({
    required String masterKey,
    required String ownerId,
    required String kind,
    required String id,
    required Object? cleartext,
  }) async {
    _validateIdentity(ownerId: ownerId, kind: kind, id: id);
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(cleartext)),
      secretKey: await _deriveKey(
        masterKey: masterKey,
        ownerId: ownerId,
        kind: kind,
        id: id,
      ),
      aad: _associatedData(ownerId: ownerId, kind: kind, id: id),
    );
    return <String, Object?>{
      'version': envelopeVersion,
      'cipher': cipherName,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<Object?> decrypt({
    required String masterKey,
    required String ownerId,
    required String kind,
    required String id,
    required Object? envelope,
  }) async {
    _validateIdentity(ownerId: ownerId, kind: kind, id: id);
    final value = _envelope(envelope);
    try {
      final cleartext = await _algorithm.decrypt(
        SecretBox(
          _base64Field(value, 'ciphertext'),
          nonce: _base64Field(value, 'nonce'),
          mac: Mac(_base64Field(value, 'mac')),
        ),
        secretKey: await _deriveKey(
          masterKey: masterKey,
          ownerId: ownerId,
          kind: kind,
          id: id,
        ),
        aad: _associatedData(ownerId: ownerId, kind: kind, id: id),
      );
      return jsonDecode(utf8.decode(cleartext, allowMalformed: false));
    } on SecretBoxAuthenticationError {
      throw DataApiSensitiveAuthenticationException(kind: kind, id: id);
    }
  }

  Future<SecretKey> _deriveKey({
    required String masterKey,
    required String ownerId,
    required String kind,
    required String id,
  }) {
    if (masterKey.isEmpty) {
      throw const DataApiEncryptionKeyRequiredException();
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(masterKey)),
      nonce: utf8.encode(_derivationSalt),
      info: utf8.encode('$_purpose:$ownerId:$kind:$id'),
    );
  }

  List<int> _associatedData({
    required String ownerId,
    required String kind,
    required String id,
  }) => utf8.encode('ianvs:$_purpose:$ownerId:$kind:$id');

  Map<String, Object?> _envelope(Object? value) {
    if (value is! Map) {
      throw const FormatException('Sensitive data envelope must be an object.');
    }
    final envelope = value.map<String, Object?>(
      (key, field) => MapEntry(key.toString(), field),
    );
    const fields = <String>{'version', 'cipher', 'nonce', 'ciphertext', 'mac'};
    if (envelope.keys.any((key) => !fields.contains(key)) ||
        envelope['version'] != envelopeVersion ||
        envelope['cipher'] != cipherName ||
        envelope.length != fields.length) {
      throw const FormatException('Sensitive data envelope is invalid.');
    }
    final nonce = _base64Field(envelope, 'nonce');
    final mac = _base64Field(envelope, 'mac');
    if (nonce.length != _algorithm.nonceLength ||
        mac.length != _algorithm.macAlgorithm.macLength) {
      throw const FormatException('Sensitive data envelope is invalid.');
    }
    return envelope;
  }

  List<int> _base64Field(Map<String, Object?> envelope, String field) {
    final value = envelope[field];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Sensitive data envelope is invalid.');
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw const FormatException('Sensitive data envelope is invalid.');
    }
  }

  void _validateIdentity({
    required String ownerId,
    required String kind,
    required String id,
  }) {
    if (ownerId.isEmpty || kind.isEmpty || id.isEmpty) {
      throw ArgumentError('Sensitive data identity must not be empty.');
    }
  }
}

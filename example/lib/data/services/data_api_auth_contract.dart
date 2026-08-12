import 'dart:convert';

const int minimumDataApiEncryptionKeyBytes = 16;
const int maximumDataApiEncryptionKeyBytes = 1024;
const int minimumDataApiPasswordBytes = 12;
const int maximumDataApiPasswordBytes = 72;

final RegExp _dataApiUsernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$');
final RegExp _dataApiAuthOperationIdPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

String validateDataApiAuthOperationId(String value) {
  if (!_dataApiAuthOperationIdPattern.hasMatch(value)) {
    throw const FormatException(
      'Data API authentication operation ID must be 32 unpadded base64url '
      'bytes.',
    );
  }
  return value;
}

String normalizeDataApiUsername(String value) {
  final normalized = value.trim().toLowerCase();
  if (!_dataApiUsernamePattern.hasMatch(normalized) ||
      normalized == '__local__') {
    throw const FormatException(
      'Remote Data API username must be 3–64 lowercase letters, numbers, '
      'dots, underscores, or hyphens.',
    );
  }
  return normalized;
}

String validateDataApiPassword(String value) {
  final byteLength = utf8.encode(value).length;
  if (byteLength < minimumDataApiPasswordBytes ||
      byteLength > maximumDataApiPasswordBytes) {
    throw const FormatException(
      'Remote Data API password must contain 12–72 UTF-8 bytes.',
    );
  }
  return value;
}

String validateDataApiEncryptionKey(String value) {
  final byteLength = utf8.encode(value).length;
  if (byteLength < minimumDataApiEncryptionKeyBytes ||
      byteLength > maximumDataApiEncryptionKeyBytes) {
    throw const FormatException(
      'Remote Data API encryption key must contain 16–1024 UTF-8 bytes.',
    );
  }
  return value;
}

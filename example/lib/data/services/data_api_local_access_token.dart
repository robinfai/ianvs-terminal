import 'dart:convert';

final RegExp _canonicalLocalAccessTokenShape = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Whether [value] is the canonical unpadded base64url encoding of 32 bytes.
bool isCanonicalDataApiLocalAccessToken(String value) {
  if (!_canonicalLocalAccessTokenShape.hasMatch(value)) {
    return false;
  }
  try {
    final bytes = base64Url.decode('$value=');
    return bytes.length == 32 &&
        base64UrlEncode(bytes).replaceAll('=', '') == value;
  } on FormatException {
    return false;
  }
}

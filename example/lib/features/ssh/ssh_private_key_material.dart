import 'dart:convert';
import 'dart:io';

const int maximumSshPrivateKeyBytes = 64 * 1024;

bool looksLikeSshPrivateKeyContents(String value) {
  final trimmed = value.trimLeft();
  return RegExp(
        '^-----BEGIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----',
      ).hasMatch(trimmed) ||
      trimmed.startsWith('PuTTY-User-Key-File-');
}

String validateSshPrivateKeyContents(String value) {
  final contents = value.trim();
  if (utf8.encode(contents).length > maximumSshPrivateKeyBytes) {
    throw const FormatException('Private key files must be 64 KiB or smaller.');
  }
  if (!looksLikeSshPrivateKeyContents(contents)) {
    throw const FormatException(
      'The selected IdentityFile is not a private key.',
    );
  }
  return contents;
}

String readSshPrivateKeyContents(String path) {
  final file = File(path);
  if (FileSystemEntity.typeSync(path, followLinks: true) !=
      FileSystemEntityType.file) {
    throw const FormatException(
      'The selected IdentityFile is not a regular private key file.',
    );
  }
  final handle = file.openSync(mode: FileMode.read);
  late final List<int> bytes;
  try {
    if (handle.lengthSync() > maximumSshPrivateKeyBytes) {
      throw const FormatException(
        'Private key files must be 64 KiB or smaller.',
      );
    }
    bytes = handle.readSync(maximumSshPrivateKeyBytes + 1);
    if (bytes.length > maximumSshPrivateKeyBytes ||
        handle.readSync(1).isNotEmpty) {
      throw const FormatException(
        'Private key files must be 64 KiB or smaller.',
      );
    }
  } finally {
    handle.closeSync();
  }
  late final String decoded;
  try {
    decoded = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const FormatException(
      'The selected IdentityFile is not valid UTF-8 private key data.',
    );
  }
  return validateSshPrivateKeyContents(decoded);
}

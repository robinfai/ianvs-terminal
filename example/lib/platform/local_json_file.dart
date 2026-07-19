import 'dart:convert';
import 'dart:io';

typedef AtomicFileReplace =
    Future<File> Function(File temporaryFile, String targetPath);

int _atomicWriteSerial = 0;

Map<String, Object?> decodeJsonObject(
  String source, {
  required String documentName,
}) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw FormatException('$documentName must contain a JSON object.');
  }
  return decoded.map((key, value) {
    if (key is! String) {
      throw FormatException('$documentName contains a non-string key.');
    }
    return MapEntry(key, value);
  });
}

List<Object?> decodeJsonArray(String source, {required String documentName}) {
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw FormatException('$documentName must contain a JSON array.');
  }
  return List<Object?>.from(decoded);
}

Future<void> writeStringAtomically(
  File file,
  String contents, {
  Encoding encoding = utf8,
  AtomicFileReplace? replace,
}) async {
  await file.parent.create(recursive: true);
  final serial = _atomicWriteSerial++;
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final temporaryFile = File('${file.path}.tmp.$pid.$timestamp.$serial');
  try {
    await temporaryFile.writeAsString(
      contents,
      encoding: encoding,
      flush: true,
    );
    await (replace ?? _replaceFile)(temporaryFile, file.path);
  } finally {
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
  }
}

Future<File> _replaceFile(File temporaryFile, String targetPath) {
  return temporaryFile.rename(targetPath);
}

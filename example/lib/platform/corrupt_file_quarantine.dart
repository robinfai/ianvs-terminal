import 'dart:io';

Future<File> quarantineCorruptFile(
  File file, {
  DateTime Function()? now,
}) async {
  final timestamp = (now ?? DateTime.now)().millisecondsSinceEpoch;
  for (var attempt = 0; ; attempt += 1) {
    final suffix = attempt == 0 ? '$timestamp' : '$timestamp-$attempt';
    final target = File('${file.path}.corrupt.$suffix');
    if (await FileSystemEntity.type(target.path) ==
        FileSystemEntityType.notFound) {
      return file.rename(target.path);
    }
  }
}

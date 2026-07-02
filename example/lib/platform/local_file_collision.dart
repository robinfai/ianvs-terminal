import 'dart:io';

Future<File> nextAvailableFile(File file) async {
  if (await _pathIsAvailable(file.path)) {
    return file;
  }

  final parts = _splitFilePath(file.path);
  for (var suffix = 1; ; suffix += 1) {
    final candidate = File(
      '${parts.directoryPrefix}${parts.stem}-$suffix${parts.extension}',
    );
    if (await _pathIsAvailable(candidate.path)) {
      return candidate;
    }
  }
}

Future<Directory> nextAvailableDirectory(Directory directory) async {
  if (await _pathIsAvailable(directory.path)) {
    return directory;
  }

  for (var suffix = 1; ; suffix += 1) {
    final candidate = Directory('${directory.path}-$suffix');
    if (await _pathIsAvailable(candidate.path)) {
      return candidate;
    }
  }
}

Future<bool> _pathIsAvailable(String path) async {
  return await FileSystemEntity.type(path) == FileSystemEntityType.notFound;
}

({String directoryPrefix, String stem, String extension}) _splitFilePath(
  String path,
) {
  final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
  final directoryPrefix = separatorIndex < 0
      ? ''
      : path.substring(0, separatorIndex + 1);
  final basename = separatorIndex < 0
      ? path
      : path.substring(separatorIndex + 1);
  final dotIndex = basename.lastIndexOf('.');
  if (dotIndex <= 0) {
    return (directoryPrefix: directoryPrefix, stem: basename, extension: '');
  }
  return (
    directoryPrefix: directoryPrefix,
    stem: basename.substring(0, dotIndex),
    extension: basename.substring(dotIndex),
  );
}

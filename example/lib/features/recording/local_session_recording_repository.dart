import 'dart:convert';
import 'dart:io';

import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/local_json_file.dart';

typedef LocalSessionRecordingDirectoryResolver = Future<Directory> Function();

const int _maxRecordingLibraryEntries = 1000;
const int _maxRecordingFileBytes = 128 * 1024 * 1024;
const String _recordingLibraryIndexFileName = 'library-v1.json';

final class LocalSessionRecordingEntry {
  const LocalSessionRecordingEntry({
    required this.path,
    required this.displayName,
    required this.createdAtUtc,
    required this.duration,
    required this.fileSizeBytes,
    this.sessionId,
    this.schemaVersion,
    this.inputPolicy,
    this.error,
  });

  final String path;
  final String displayName;
  final DateTime createdAtUtc;
  final Duration duration;
  final int fileSizeBytes;
  final String? sessionId;
  final int? schemaVersion;
  final TerminalRecordingInputPolicy? inputPolicy;
  final String? error;

  bool get isReadable => error == null;
}

final class LocalSessionRecordingDestination {
  const LocalSessionRecordingDestination(this.file);

  final File file;
}

final class LocalSessionOpenedRecording {
  const LocalSessionOpenedRecording({
    required this.entry,
    required this.recording,
  });

  final LocalSessionRecordingEntry entry;
  final TerminalRecording recording;
}

class LocalSessionRecordingRepository {
  LocalSessionRecordingRepository({
    LocalSessionRecordingDirectoryResolver? directoryResolver,
  }) : directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalSessionRecordingDirectoryResolver directoryResolver;
  final Set<String> _reservedPaths = <String>{};
  final TerminalRecordingCodec _codec = const TerminalRecordingCodec();

  Future<LocalSessionRecordingDestination> reserve({
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) async {
    final runtimeSegment = _identitySegment(
      runtimeSessionId,
      'Runtime session',
    );
    final rootDirectory = await _recordingRoot();
    await rootDirectory.create(recursive: true);

    final timestamp = createdAtUtc.toUtc().microsecondsSinceEpoch;
    final basename = '$timestamp-$runtimeSegment';
    var suffix = 1;
    while (true) {
      final candidateName = suffix == 1
          ? '$basename.ndjson'
          : '$basename-$suffix.ndjson';
      final candidate = File(
        '${rootDirectory.path}${Platform.pathSeparator}$candidateName',
      );
      final candidatePath = candidate.absolute.path;
      if (!_reservedPaths.contains(candidatePath) &&
          !await candidate.exists()) {
        _reservedPaths.add(candidatePath);
        return LocalSessionRecordingDestination(candidate.absolute);
      }
      suffix += 1;
    }
  }

  Future<String> save(
    LocalSessionRecordingDestination destination,
    TerminalRecording recording, {
    String? displayName,
  }) async {
    final contents = _codec.encode(recording);
    await writeStringAtomically(destination.file, contents);
    _reservedPaths.remove(destination.file.absolute.path);
    if (displayName case final String value) {
      try {
        await _setDisplayName(destination.file.absolute.path, value);
      } on Object {
        // An optional library label must not turn a durable capture into a
        // failed recording save.
      }
    }
    return destination.file.absolute.path;
  }

  void release(LocalSessionRecordingDestination destination) {
    _reservedPaths.remove(destination.file.absolute.path);
  }

  String saveSync(
    LocalSessionRecordingDestination destination,
    TerminalRecording recording, {
    String? displayName,
  }) {
    final contents = _codec.encode(recording);
    final file = destination.file.absolute;
    file.parent.createSync(recursive: true);
    final temporary = File(
      '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      temporary.writeAsStringSync(contents, encoding: utf8, flush: true);
      temporary.renameSync(file.path);
      _reservedPaths.remove(file.path);
      if (displayName case final String value) {
        _setDisplayNameSync(file.path, value);
      }
      return file.path;
    } finally {
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  Future<TerminalRecording> load(String recordingPath) async {
    final normalizedPath = recordingPath.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('Recording path must not be empty.');
    }
    final file = File(normalizedPath);
    final length = await file.length();
    if (length > _maxRecordingFileBytes) {
      throw const FormatException('Recording file exceeds the library limit.');
    }
    return _codec.decode(await file.readAsString());
  }

  Future<LocalSessionOpenedRecording> openRecording(
    String recordingPath,
  ) async {
    final file = File(recordingPath.trim()).absolute;
    final recording = await load(file.path);
    final stat = await file.stat();
    final duration = recording.events.isEmpty
        ? Duration.zero
        : recording.events.last.monotonicOffset;
    return LocalSessionOpenedRecording(
      entry: LocalSessionRecordingEntry(
        path: file.path,
        displayName: _basenameWithoutExtension(file.uri.pathSegments.last),
        createdAtUtc: recording.metadata.createdAtUtc,
        duration: duration,
        fileSizeBytes: stat.size,
        sessionId: recording.metadata.sessionId,
        schemaVersion: recording.metadata.schemaVersion,
        inputPolicy: recording.metadata.inputPolicy,
      ),
      recording: recording,
    );
  }

  Future<List<LocalSessionRecordingEntry>> listRecordings() async {
    final root = await _recordingRoot();
    if (!await root.exists()) {
      return const <LocalSessionRecordingEntry>[];
    }
    final displayNames = await _loadDisplayNames(root);
    final entries = <LocalSessionRecordingEntry>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entries.length >= _maxRecordingLibraryEntries) {
        break;
      }
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.ndjson') ||
          entity.path.contains('.tmp.')) {
        continue;
      }
      entries.add(await _entryFor(entity, root, displayNames));
    }
    entries.sort((left, right) {
      final byDate = right.createdAtUtc.compareTo(left.createdAtUtc);
      return byDate == 0
          ? left.displayName.compareTo(right.displayName)
          : byDate;
    });
    return List<LocalSessionRecordingEntry>.unmodifiable(entries);
  }

  Future<void> renameRecording(String recordingPath, String displayName) async {
    final normalizedName = _normalizedDisplayName(displayName);
    final root = await _recordingRoot();
    final path = _requireLibraryPath(recordingPath, root);
    if (!await File(path).exists()) {
      throw FileSystemException('Recording file does not exist', path);
    }
    final names = await _loadDisplayNames(root);
    names[path] = normalizedName;
    await _writeDisplayNames(root, names);
  }

  Future<LocalSessionRecordingEntry> importRecording({
    required String sourcePath,
    String? displayName,
  }) async {
    final source = File(sourcePath.trim());
    final recording = await load(source.path);
    final sourceName = source.uri.pathSegments.last;
    final destination = await reserve(
      runtimeSessionId: recording.metadata.sessionId,
      createdAtUtc: recording.metadata.createdAtUtc,
    );
    await save(
      destination,
      recording,
      displayName: displayName ?? _basenameWithoutExtension(sourceName),
    );
    final entries = await listRecordings();
    return entries.firstWhere(
      (entry) => entry.path == destination.file.absolute.path,
    );
  }

  Future<void> exportRecording(
    String recordingPath,
    String destinationPath,
  ) async {
    final normalizedDestination = destinationPath.trim();
    if (normalizedDestination.isEmpty) {
      throw const FormatException('Export path must not be empty.');
    }
    final recording = await load(recordingPath);
    await writeStringAtomically(
      File(normalizedDestination),
      _codec.encode(recording),
    );
  }

  Future<void> forgetRecording(String recordingPath) async {
    final root = await _recordingRoot();
    final path = _requireLibraryPath(recordingPath, root);
    final names = await _loadDisplayNames(root);
    if (names.remove(path) != null) {
      await _writeDisplayNames(root, names);
    }
  }

  Future<Directory> _recordingRoot() async {
    final supportDirectory = await directoryResolver();
    return Directory(
      '${supportDirectory.absolute.path}${Platform.pathSeparator}'
      'ianvs_recordings',
    ).absolute;
  }

  Future<LocalSessionRecordingEntry> _entryFor(
    File file,
    Directory root,
    Map<String, String> displayNames,
  ) async {
    final absolute = file.absolute;
    final stat = await absolute.stat();
    final fallbackName = _basenameWithoutExtension(
      absolute.uri.pathSegments.last,
    );
    final displayName = displayNames[absolute.path] ?? fallbackName;
    try {
      final recording = await load(absolute.path);
      final duration = recording.events.isEmpty
          ? Duration.zero
          : recording.events.last.monotonicOffset;
      return LocalSessionRecordingEntry(
        path: absolute.path,
        displayName: displayName,
        createdAtUtc: recording.metadata.createdAtUtc,
        duration: duration,
        fileSizeBytes: stat.size,
        sessionId: recording.metadata.sessionId,
        schemaVersion: recording.metadata.schemaVersion,
        inputPolicy: recording.metadata.inputPolicy,
      );
    } on Object catch (error) {
      return LocalSessionRecordingEntry(
        path: absolute.path,
        displayName: displayName,
        createdAtUtc: stat.modified.toUtc(),
        duration: Duration.zero,
        fileSizeBytes: stat.size,
        error: error.toString(),
      );
    }
  }

  Future<Map<String, String>> _loadDisplayNames(Directory root) async {
    final index = File(
      '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
    );
    if (!await index.exists()) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! Map<String, Object?> || decoded['names'] is! Map) {
        return <String, String>{};
      }
      final names = <String, String>{};
      for (final entry in (decoded['names']! as Map).entries) {
        if (entry.key is String && entry.value is String) {
          names[(entry.key as String)] = entry.value as String;
        }
      }
      return names;
    } on Object {
      return <String, String>{};
    }
  }

  Future<void> _setDisplayName(String path, String displayName) async {
    final root = await _recordingRoot();
    final normalizedPath = _requireLibraryPath(path, root);
    final names = await _loadDisplayNames(root);
    names[normalizedPath] = _normalizedDisplayName(displayName);
    await _writeDisplayNames(root, names);
  }

  void _setDisplayNameSync(String path, String displayName) {
    final recordingFile = File(path).absolute;
    final parent = recordingFile.parent;
    final parentName = parent.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    // Existing workspace-* directories remain readable migration input.
    final root = parentName.startsWith('workspace-')
        ? parent.parent.absolute
        : parent.absolute;
    final index = File(
      '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
    );
    final names = <String, String>{};
    if (index.existsSync()) {
      try {
        final decoded = jsonDecode(index.readAsStringSync());
        if (decoded is Map<String, Object?> && decoded['names'] is Map) {
          for (final entry in (decoded['names']! as Map).entries) {
            if (entry.key is String && entry.value is String) {
              names[entry.key as String] = entry.value as String;
            }
          }
        }
      } on Object {
        // A corrupt optional label index must not block recording durability.
      }
    }
    names[_requireLibraryPath(path, root)] = _normalizedDisplayName(
      displayName,
    );
    _writeDisplayNamesSync(root, names);
  }

  Future<void> _writeDisplayNames(
    Directory root,
    Map<String, String> names,
  ) async {
    final sorted = Map<String, String>.fromEntries(
      names.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
    await writeStringAtomically(
      File(
        '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
      ),
      jsonEncode(<String, Object?>{'schemaVersion': 1, 'names': sorted}),
    );
  }

  void _writeDisplayNamesSync(Directory root, Map<String, String> names) {
    root.createSync(recursive: true);
    final index = File(
      '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
    );
    final sorted = Map<String, String>.fromEntries(
      names.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
    index.writeAsStringSync(
      jsonEncode(<String, Object?>{'schemaVersion': 1, 'names': sorted}),
      encoding: utf8,
      flush: true,
    );
  }

  String _requireLibraryPath(String value, Directory root) {
    final path = File(value.trim()).absolute.path;
    final prefix = '${root.absolute.path}${Platform.pathSeparator}';
    if (!path.startsWith(prefix)) {
      throw FormatException('Recording path is outside the library: $path');
    }
    return path;
  }
}

String _normalizedDisplayName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    throw const FormatException('Recording name must not be empty.');
  }
  if (normalized.runes.length > 120) {
    throw const FormatException('Recording name is too long.');
  }
  return normalized;
}

String _basenameWithoutExtension(String value) {
  final trimmed = value.trim();
  if (trimmed.toLowerCase().endsWith('.ndjson')) {
    return trimmed.substring(0, trimmed.length - '.ndjson'.length);
  }
  return trimmed.isEmpty ? 'Untitled recording' : trimmed;
}

String _identitySegment(String value, String label) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw FormatException('$label identity must not be empty.');
  }
  final encoded = base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  if (encoded.isEmpty || encoded.length > 180) {
    throw FormatException('$label identity is too long.');
  }
  return encoded;
}

import 'dart:convert';
import 'dart:io';

import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/local_json_file.dart';

typedef LocalSessionRecordingDirectoryResolver = Future<Directory> Function();

final class LocalSessionRecordingDestination {
  const LocalSessionRecordingDestination(this.file);

  final File file;
}

class LocalSessionRecordingRepository {
  LocalSessionRecordingRepository({
    LocalSessionRecordingDirectoryResolver? directoryResolver,
  }) : directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final LocalSessionRecordingDirectoryResolver directoryResolver;
  final Set<String> _reservedPaths = <String>{};
  final TerminalRecordingCodec _codec = const TerminalRecordingCodec();

  Future<LocalSessionRecordingDestination> reserve({
    required String workspaceId,
    required String descriptorId,
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) async {
    final workspaceSegment = _identitySegment(workspaceId, 'Workspace');
    final descriptorSegment = _identitySegment(descriptorId, 'Descriptor');
    final runtimeSegment = _identitySegment(
      runtimeSessionId,
      'Runtime session',
    );
    final supportDirectory = await directoryResolver();
    final recordingDirectory = Directory(
      <String>[
        supportDirectory.absolute.path,
        'ianvs_recordings',
        'workspace-$workspaceSegment',
      ].join(Platform.pathSeparator),
    );
    await recordingDirectory.create(recursive: true);

    final timestamp = createdAtUtc.toUtc().microsecondsSinceEpoch;
    final basename = '$timestamp-$descriptorSegment-$runtimeSegment';
    var suffix = 1;
    while (true) {
      final candidateName = suffix == 1
          ? '$basename.ndjson'
          : '$basename-$suffix.ndjson';
      final candidate = File(
        '${recordingDirectory.path}${Platform.pathSeparator}$candidateName',
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
    TerminalRecording recording,
  ) async {
    final contents = _codec.encode(recording);
    await writeStringAtomically(destination.file, contents);
    _reservedPaths.remove(destination.file.absolute.path);
    return destination.file.absolute.path;
  }

  void release(LocalSessionRecordingDestination destination) {
    _reservedPaths.remove(destination.file.absolute.path);
  }

  String saveSync(
    LocalSessionRecordingDestination destination,
    TerminalRecording recording,
  ) {
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
    return _codec.decode(await File(normalizedPath).readAsString());
  }
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

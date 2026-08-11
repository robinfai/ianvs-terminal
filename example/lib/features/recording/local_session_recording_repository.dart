import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random, max, min;

import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';

typedef LocalSessionRecordingDirectoryResolver = Future<Directory> Function();
typedef LocalSessionRecordingEncoder =
    Future<String> Function(TerminalRecording recording);
typedef LocalSessionRecordingDecoder =
    Future<TerminalRecording> Function(String source);
typedef LocalSessionRecordingFileWriter =
    Future<void> Function(String path, TerminalRecording recording);
typedef LocalSessionRecordingFileReader =
    Future<TerminalRecording> Function(String path);
typedef LocalSessionRecordingHandoffWorker =
    Future<LocalSessionRecordingFinalizedMetadata> Function({
      required String handoffPath,
      required String destinationPath,
      required String expectedSessionId,
      required List<TerminalRecordingSemanticEvent> semanticEvents,
    });

const int _maxRecordingLibraryEntries = 1000;
const int _maxRecordingFileBytes = 128 * 1024 * 1024;
const int _recordingMetadataReadBytes = 64 * 1024;
const String _recordingLibraryIndexFileName = 'library-v1.json';
const int _recordingLibraryIndexSchemaVersion = 2;
const String _recordingHandoffDirectoryPrefix = '.ianvs-recording-handoff-v1-';
const String _recordingHandoffFilePrefix = '.ianvs-recording-handoff-';
const Duration _defaultRecordingFinalizeTimeout = Duration(seconds: 3);
const Duration _defaultRecordingFinalizePollInterval = Duration(
  milliseconds: 25,
);
const int _recordingHandoffManifestSchemaVersion = 1;

String _newHandoffJobId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

enum LocalSessionRecordingFinalizeFailure {
  cancelled,
  timedOut,
  nativeFailed,
  invalidHandoff,
  claimedByAnotherProcess,
}

final class LocalSessionRecordingFinalizeException implements Exception {
  const LocalSessionRecordingFinalizeException({
    required this.failure,
    required this.jobId,
    required this.message,
  });

  final LocalSessionRecordingFinalizeFailure failure;
  final String jobId;
  final String message;

  @override
  String toString() =>
      'LocalSessionRecordingFinalizeException('
      '${failure.name}, job $jobId): $message';
}

final class LocalSessionRecordingFinalizeCancellation {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

final class LocalSessionRecordingFinalizedMetadata {
  const LocalSessionRecordingFinalizedMetadata({
    required this.sessionId,
    required this.createdAtUtc,
    required this.duration,
    required this.schemaVersion,
    required this.inputPolicy,
  });

  final String sessionId;
  final DateTime createdAtUtc;
  final Duration duration;
  final int schemaVersion;
  final TerminalRecordingInputPolicy inputPolicy;
}

final class LocalSessionRecordingRecoveryFailure {
  const LocalSessionRecordingRecoveryFailure({
    required this.jobId,
    required this.message,
  });

  final String jobId;
  final String message;
}

final class LocalSessionRecordingRecoveryResult {
  const LocalSessionRecordingRecoveryResult({
    required this.recoveredPaths,
    required this.pendingJobIds,
    required this.orphanPaths,
    required this.failures,
  });

  final List<String> recoveredPaths;
  final List<String> pendingJobIds;
  final List<String> orphanPaths;
  final List<LocalSessionRecordingRecoveryFailure> failures;

  bool get hasIssues =>
      pendingJobIds.isNotEmpty || orphanPaths.isNotEmpty || failures.isNotEmpty;
}

final class _RecordingHandoffManifest {
  const _RecordingHandoffManifest({
    required this.job,
    required this.destinationPath,
    required this.semanticEvents,
    required this.createdAtUtc,
    required this.ownerPid,
    this.displayName,
  });

  final TerminalRecordingFinalizeJob job;
  final String destinationPath;
  final List<TerminalRecordingSemanticEvent> semanticEvents;
  final DateTime createdAtUtc;
  final int ownerPid;
  final String? displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _recordingHandoffManifestSchemaVersion,
    'jobId': job.jobId,
    'sessionId': job.sessionId,
    'handoffPath': job.handoffPath,
    'errorPath': job.errorPath,
    'destinationPath': destinationPath,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'ownerPid': ownerPid,
    if (displayName != null) 'displayName': displayName,
    'semanticEvents': semanticEvents
        .map(
          (event) => <String, Object?>{
            'monotonicOffsetMicros': event.monotonicOffset.inMicroseconds,
            'kind': event.kind.name,
            if (event.command != null) 'command': event.command,
            if (event.cwd != null) 'cwd': event.cwd,
            if (event.hostname != null) 'hostname': event.hostname,
            if (event.exitCode != null) 'exitCode': event.exitCode,
            'remote': event.remote,
          },
        )
        .toList(growable: false),
  };

  static _RecordingHandoffManifest fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Recording handoff manifest is invalid.');
    }
    final schemaVersion = value['schemaVersion'];
    final jobId = value['jobId'];
    final sessionId = value['sessionId'];
    final handoffPath = value['handoffPath'];
    final errorPath = value['errorPath'];
    final destinationPath = value['destinationPath'];
    final createdAtValue = value['createdAtUtc'];
    final ownerPid = value['ownerPid'];
    final displayName = value['displayName'];
    final rawSemantics = value['semanticEvents'];
    final createdAtUtc = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)?.toUtc()
        : null;
    if (schemaVersion != _recordingHandoffManifestSchemaVersion ||
        jobId is! String ||
        sessionId is! String ||
        handoffPath is! String ||
        errorPath is! String ||
        destinationPath is! String ||
        createdAtUtc == null ||
        ownerPid is! int ||
        ownerPid <= 0 ||
        (displayName != null && displayName is! String) ||
        rawSemantics is! List) {
      throw const FormatException('Recording handoff manifest is invalid.');
    }
    final semantics = <TerminalRecordingSemanticEvent>[];
    for (final rawEvent in rawSemantics) {
      if (rawEvent is! Map) {
        throw const FormatException(
          'Recording handoff semantic event is invalid.',
        );
      }
      final offsetMicros = rawEvent['monotonicOffsetMicros'];
      final kindName = rawEvent['kind'];
      final command = rawEvent['command'];
      final cwd = rawEvent['cwd'];
      final hostname = rawEvent['hostname'];
      final exitCode = rawEvent['exitCode'];
      final remote = rawEvent['remote'];
      final kind = kindName is String
          ? TerminalRecordingSemanticKind.values
                .where((candidate) => candidate.name == kindName)
                .firstOrNull
          : null;
      if (offsetMicros is! int ||
          offsetMicros < 0 ||
          kind == null ||
          (command != null && command is! String) ||
          (cwd != null && cwd is! String) ||
          (hostname != null && hostname is! String) ||
          (exitCode != null && exitCode is! int) ||
          remote is! bool) {
        throw const FormatException(
          'Recording handoff semantic event is invalid.',
        );
      }
      semantics.add(
        TerminalRecordingSemanticEvent(
          monotonicOffset: Duration(microseconds: offsetMicros),
          kind: kind,
          command: command as String?,
          cwd: cwd as String?,
          hostname: hostname as String?,
          exitCode: exitCode as int?,
          remote: remote,
        ),
      );
    }
    return _RecordingHandoffManifest(
      job: TerminalRecordingFinalizeJob(
        sessionId: sessionId,
        jobId: jobId,
        handoffPath: handoffPath,
        errorPath: errorPath,
      ),
      destinationPath: destinationPath,
      semanticEvents: List<TerminalRecordingSemanticEvent>.unmodifiable(
        semantics,
      ),
      createdAtUtc: createdAtUtc,
      ownerPid: ownerPid,
      displayName: displayName as String?,
    );
  }
}

final class _RecordingHandoffLease {
  _RecordingHandoffLease({required this.handle});

  final RandomAccessFile handle;
  bool finalizing = false;
}

Future<void> _encodeAndWriteRecordingInBackground(
  String path,
  TerminalRecording recording,
) {
  return Isolate.run(() async {
    final contents = const TerminalRecordingCodec().encode(recording);
    await writeStringAtomically(File(path), contents);
  });
}

Future<TerminalRecording> _readAndDecodeRecordingInBackground(String path) {
  return Isolate.run(() async {
    final file = File(path);
    final length = await file.length();
    if (length > _maxRecordingFileBytes) {
      throw const FormatException('Recording file exceeds the library limit.');
    }
    final source = await file.readAsString();
    return const TerminalRecordingCodec().decode(source);
  });
}

Future<LocalSessionRecordingFinalizedMetadata>
_finalizeRecordingHandoffInBackground({
  required String handoffPath,
  required String destinationPath,
  required String expectedSessionId,
  required List<TerminalRecordingSemanticEvent> semanticEvents,
}) {
  return Isolate.run(() async {
    final handoffFile = File(handoffPath);
    final length = await handoffFile.length();
    if (length > _maxRecordingFileBytes) {
      throw const FormatException('Recording file exceeds the library limit.');
    }
    final source = await handoffFile.readAsString();
    final recording = const TerminalRecordingCodec().decode(source);
    if (recording.metadata.sessionId != expectedSessionId) {
      throw const FormatException(
        'Native recording handoff used a different session id.',
      );
    }
    final enriched = const TerminalRecordingSemanticMerger().merge(
      recording,
      semanticEvents,
    );
    final encoded = const TerminalRecordingCodec().encode(enriched);
    await writeStringAtomically(File(destinationPath), encoded);
    await handoffFile.delete();
    return LocalSessionRecordingFinalizedMetadata(
      sessionId: enriched.metadata.sessionId,
      createdAtUtc: enriched.metadata.createdAtUtc,
      duration: enriched.events.isEmpty
          ? Duration.zero
          : enriched.events.last.monotonicOffset,
      schemaVersion: enriched.metadata.schemaVersion,
      inputPolicy: enriched.metadata.inputPolicy,
    );
  });
}

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

final class _RecordingIndexedMetadata {
  const _RecordingIndexedMetadata({
    required this.modifiedMicros,
    required this.fileSizeBytes,
    required this.createdAtUtc,
    required this.duration,
    this.sessionId,
    this.recordingSchemaVersion,
    this.inputPolicy,
    this.error,
  });

  final int modifiedMicros;
  final int fileSizeBytes;
  final DateTime createdAtUtc;
  final Duration duration;
  final String? sessionId;
  final int? recordingSchemaVersion;
  final TerminalRecordingInputPolicy? inputPolicy;
  final String? error;

  bool matches(FileStat stat) {
    return fileSizeBytes == stat.size &&
        modifiedMicros == stat.modified.toUtc().microsecondsSinceEpoch;
  }

  LocalSessionRecordingEntry toEntry({
    required String path,
    required String displayName,
  }) {
    return LocalSessionRecordingEntry(
      path: path,
      displayName: displayName,
      createdAtUtc: createdAtUtc,
      duration: duration,
      fileSizeBytes: fileSizeBytes,
      sessionId: sessionId,
      schemaVersion: recordingSchemaVersion,
      inputPolicy: inputPolicy,
      error: error,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'modifiedMicros': modifiedMicros,
    'fileSizeBytes': fileSizeBytes,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'durationMicros': duration.inMicroseconds,
    if (sessionId != null) 'sessionId': sessionId,
    if (recordingSchemaVersion != null)
      'recordingSchemaVersion': recordingSchemaVersion,
    if (inputPolicy != null) 'inputPolicy': inputPolicy!.name,
    if (error != null) 'error': error,
  };

  static _RecordingIndexedMetadata? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final modifiedMicros = value['modifiedMicros'];
    final fileSizeBytes = value['fileSizeBytes'];
    final createdAtValue = value['createdAtUtc'];
    final durationMicros = value['durationMicros'];
    final createdAtUtc = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)?.toUtc()
        : null;
    if (modifiedMicros is! int ||
        fileSizeBytes is! int ||
        fileSizeBytes < 0 ||
        durationMicros is! int ||
        durationMicros < 0 ||
        createdAtUtc == null) {
      return null;
    }
    final rawInputPolicy = value['inputPolicy'];
    final inputPolicy = switch (rawInputPolicy) {
      'record' => TerminalRecordingInputPolicy.record,
      'redact' => TerminalRecordingInputPolicy.redact,
      null => null,
      _ => null,
    };
    final rawSessionId = value['sessionId'];
    final rawSchemaVersion = value['recordingSchemaVersion'];
    final rawError = value['error'];
    if ((rawInputPolicy != null && inputPolicy == null) ||
        (rawSessionId != null && rawSessionId is! String) ||
        (rawSchemaVersion != null && rawSchemaVersion is! int) ||
        (rawError != null && rawError is! String)) {
      return null;
    }
    return _RecordingIndexedMetadata(
      modifiedMicros: modifiedMicros,
      fileSizeBytes: fileSizeBytes,
      createdAtUtc: createdAtUtc,
      duration: Duration(microseconds: durationMicros),
      sessionId: rawSessionId as String?,
      recordingSchemaVersion: rawSchemaVersion as int?,
      inputPolicy: inputPolicy,
      error: rawError as String?,
    );
  }
}

final class _RecordingLibraryIndex {
  _RecordingLibraryIndex({
    Map<String, String>? names,
    Map<String, _RecordingIndexedMetadata>? entries,
  }) : names = names ?? <String, String>{},
       entries = entries ?? <String, _RecordingIndexedMetadata>{};

  final Map<String, String> names;
  final Map<String, _RecordingIndexedMetadata> entries;
}

final class _RecordingLibraryIndexLoad {
  const _RecordingLibraryIndexLoad(this.index, {required this.needsWrite});

  final _RecordingLibraryIndex index;
  final bool needsWrite;
}

class LocalSessionRecordingRepository {
  LocalSessionRecordingRepository({
    LocalSessionRecordingDirectoryResolver? directoryResolver,
    LocalSessionRecordingEncoder? encoder,
    LocalSessionRecordingDecoder? decoder,
    LocalSessionRecordingFileWriter? fileWriter,
    LocalSessionRecordingFileReader? fileReader,
    LocalSessionRecordingHandoffWorker? handoffWorker,
    this.finalizeTimeout = _defaultRecordingFinalizeTimeout,
    this.finalizePollInterval = _defaultRecordingFinalizePollInterval,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  }) : directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _encoder = encoder,
       _decoder = decoder,
       _fileWriter = fileWriter ?? _encodeAndWriteRecordingInBackground,
       _fileReader = fileReader ?? _readAndDecodeRecordingInBackground,
       _handoffWorker = handoffWorker ?? _finalizeRecordingHandoffInBackground,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    if (finalizeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        finalizeTimeout,
        'finalizeTimeout',
        'Must be positive.',
      );
    }
    if (finalizePollInterval <= Duration.zero) {
      throw ArgumentError.value(
        finalizePollInterval,
        'finalizePollInterval',
        'Must be positive.',
      );
    }
  }

  final LocalSessionRecordingDirectoryResolver directoryResolver;
  final LocalSessionRecordingEncoder? _encoder;
  final LocalSessionRecordingDecoder? _decoder;
  final LocalSessionRecordingFileWriter _fileWriter;
  final LocalSessionRecordingFileReader _fileReader;
  final LocalSessionRecordingHandoffWorker _handoffWorker;
  final Duration finalizeTimeout;
  final Duration finalizePollInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;
  final Set<String> _reservedPaths = <String>{};
  final Map<String, _RecordingHandoffLease> _handoffLeases =
      <String, _RecordingHandoffLease>{};
  Future<void> _indexOperationTail = Future<void>.value();
  Future<Directory>? _handoffDirectoryFuture;

  Future<Directory> ensureRecordingDirectory() async {
    final directory = await _recordingRoot();
    await directory.create(recursive: true);
    return directory;
  }

  /// Creates one process-private native handoff directory.
  ///
  /// [Directory.createTemp] uses the platform's secure temporary-directory
  /// primitive (0700 on Unix). Rust independently validates mode, owner, and
  /// symlink status before accepting this directory.
  Future<Directory> ensureNativeHandoffDirectory() async {
    return _handoffDirectoryFuture ??= _createNativeHandoffDirectory();
  }

  Future<Directory> _createNativeHandoffDirectory() async {
    final root = await ensureRecordingDirectory();
    return (await root.createTemp(_recordingHandoffDirectoryPrefix)).absolute;
  }

  /// Atomically persists the complete recovery mapping and holds an OS-backed
  /// lease before native recording ownership is transferred to its worker.
  ///
  /// The caller must pass the returned job id to `TerminalLiveRecorder`.
  /// Should the process die after this method, the manifest remains durable and
  /// the operating system releases the lease for startup recovery.
  Future<TerminalRecordingFinalizeJob> reserveNativeRecordingJob({
    required String sessionId,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {
    if (sessionId.isEmpty || sessionId.length > 256) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Must be bounded.');
    }
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final jobId = _newHandoffJobId();
      final handoffPath =
          '${handoffDirectory.absolute.path}${Platform.pathSeparator}'
          '$_recordingHandoffFilePrefix$jobId.ndjson';
      final job = TerminalRecordingFinalizeJob(
        sessionId: sessionId,
        jobId: jobId,
        handoffPath: handoffPath,
        errorPath: '$handoffPath.error.json',
      );
      _validateHandoffJob(job, handoffDirectory);
      if (await _handoffJobArtifactExists(job)) {
        continue;
      }
      final lease = await _tryAcquireHandoffLease(job);
      if (lease == null) {
        continue;
      }
      try {
        await _ensureHandoffManifest(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: semanticEvents,
          displayName: displayName,
        );
        return job;
      } on Object {
        await _releaseHandoffLease(job, lease);
        rethrow;
      }
    }
    throw const LocalSessionRecordingFinalizeException(
      failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
      jobId: 'unallocated',
      message: 'Could not reserve a collision-free recording handoff job.',
    );
  }

  /// Awaits a native recording job, then performs the complete large-payload
  /// decode, semantic merge, encode, and atomic destination write in a worker
  /// isolate. Timeout and cancellation retain the handoff for recovery/retry.
  Future<void> registerNativeRecordingJob({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {
    final lease = await _tryAcquireHandoffLease(job);
    if (lease == null) {
      throw _handoffClaimUnavailable(job);
    }
    await _ensureHandoffManifest(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
    );
  }

  /// Removes an intent reservation only when native definitively rejected the
  /// transfer and therefore cannot still publish a handoff for this job.
  Future<void> abandonNativeRecordingJobReservation(
    TerminalRecordingFinalizeJob job,
  ) async {
    final lease = _handoffLeases[job.jobId];
    if (lease == null || lease.finalizing) {
      return;
    }
    await _deleteIfPresent(_handoffManifestFile(job));
    await _releaseHandoffLease(job, lease);
  }

  Future<String> finalizeNativeRecording({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
  }) async {
    final lease = await _beginHandoffFinalize(job);
    if (lease == null) {
      throw _handoffClaimUnavailable(job);
    }
    try {
      _validateHandoffJob(job, handoffDirectory);
      final root = await _recordingRoot();
      final destinationPath = _requireLibraryPath(
        destination.file.absolute.path,
        root,
      );
      if (await File(destinationPath).exists() &&
          !await File(job.handoffPath).exists()) {
        // A competing process may have completed this durable destination
        // after this owner timed out. Treat the retry as idempotent and never
        // recreate an intent manifest for an already-harvested handoff.
        await _deleteIfPresent(_handoffManifestFile(job));
        _reservedPaths.remove(destinationPath);
        return destinationPath;
      }
      final manifest = await _ensureHandoffManifest(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: semanticEvents,
        displayName: displayName,
      );
      final handoffFile = File(manifest.job.handoffPath);
      final errorFile = File(manifest.job.errorPath);
      final stopwatch = Stopwatch()..start();
      while (true) {
        if (cancellation?.isCancelled == true) {
          throw LocalSessionRecordingFinalizeException(
            failure: LocalSessionRecordingFinalizeFailure.cancelled,
            jobId: manifest.job.jobId,
            message: 'Recording finalize was cancelled.',
          );
        }
        final handoffType = await FileSystemEntity.type(
          handoffFile.path,
          followLinks: false,
        );
        if (handoffType == FileSystemEntityType.link) {
          throw LocalSessionRecordingFinalizeException(
            failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
            jobId: manifest.job.jobId,
            message: 'Recording handoff must not be a symbolic link.',
          );
        }
        if (handoffType == FileSystemEntityType.file) {
          break;
        }
        final errorType = await FileSystemEntity.type(
          errorFile.path,
          followLinks: false,
        );
        if (errorType == FileSystemEntityType.link) {
          throw LocalSessionRecordingFinalizeException(
            failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
            jobId: manifest.job.jobId,
            message: 'Recording finalize error must not be a symbolic link.',
          );
        }
        if (errorType == FileSystemEntityType.file) {
          throw await _nativeFinalizeFailure(manifest.job, errorFile);
        }
        if (stopwatch.elapsed >= finalizeTimeout) {
          throw LocalSessionRecordingFinalizeException(
            failure: LocalSessionRecordingFinalizeFailure.timedOut,
            jobId: manifest.job.jobId,
            message:
                'Native recording finalize did not complete within '
                '${finalizeTimeout.inMilliseconds} ms; handoff retained.',
          );
        }
        await _delay(finalizePollInterval);
      }

      final finalized = await _handoffWorker(
        handoffPath: handoffFile.path,
        destinationPath: destinationPath,
        expectedSessionId: manifest.job.sessionId,
        semanticEvents: manifest.semanticEvents,
      );
      await _deleteIfPresent(_handoffManifestFile(manifest.job));
      _reservedPaths.remove(destinationPath);
      try {
        await _indexFinalizedRecording(
          destination.file.absolute,
          finalized,
          displayName: manifest.displayName,
        );
      } on Object {
        // The destination is durable and the index can be rebuilt from its
        // lightweight metadata/tail scan.
      }
      return destinationPath;
    } finally {
      await _releaseHandoffLease(job, lease);
    }
  }

  /// Completes ready jobs left by a previous process and reports jobs that
  /// still have only a worker partial/error marker. Nothing pending is deleted.
  Future<LocalSessionRecordingRecoveryResult> recoverNativeRecordings() async {
    final root = await _recordingRoot();
    if (!await root.exists()) {
      return const LocalSessionRecordingRecoveryResult(
        recoveredPaths: <String>[],
        pendingJobIds: <String>[],
        orphanPaths: <String>[],
        failures: <LocalSessionRecordingRecoveryFailure>[],
      );
    }
    final recoveredPaths = <String>[];
    final pendingJobIds = <String>[];
    final orphanPaths = <String>[];
    final failures = <LocalSessionRecordingRecoveryFailure>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !_pathBasename(
            entity.path,
          ).startsWith(_recordingHandoffDirectoryPrefix)) {
        continue;
      }
      await for (final candidate in entity.list(followLinks: false)) {
        if (candidate is! File ||
            !candidate.path.endsWith('.ndjson.manifest.json')) {
          continue;
        }
        var jobId = _pathBasename(candidate.path);
        try {
          final manifest = await _readHandoffManifest(candidate);
          jobId = manifest.job.jobId;
          _validateHandoffJob(manifest.job, entity);
          _requireLibraryPath(manifest.destinationPath, root);
          final handoff = File(manifest.job.handoffPath);
          final error = File(manifest.job.errorPath);
          if (await handoff.exists()) {
            try {
              final path = await finalizeNativeRecording(
                job: manifest.job,
                handoffDirectory: entity,
                destination: LocalSessionRecordingDestination(
                  File(manifest.destinationPath),
                ),
                semanticEvents: manifest.semanticEvents,
                displayName: manifest.displayName,
              );
              recoveredPaths.add(path);
            } on LocalSessionRecordingFinalizeException catch (error) {
              if (error.failure !=
                  LocalSessionRecordingFinalizeFailure
                      .claimedByAnotherProcess) {
                rethrow;
              }
              pendingJobIds.add(jobId);
            }
          } else if (await File(manifest.destinationPath).exists()) {
            final lease = await _beginHandoffFinalize(manifest.job);
            if (lease == null) {
              pendingJobIds.add(jobId);
            } else {
              try {
                await _deleteIfPresent(candidate);
                recoveredPaths.add(manifest.destinationPath);
              } finally {
                await _releaseHandoffLease(manifest.job, lease);
              }
            }
          } else if (await error.exists()) {
            final failure = await _nativeFinalizeFailure(manifest.job, error);
            failures.add(
              LocalSessionRecordingRecoveryFailure(
                jobId: jobId,
                message: failure.message,
              ),
            );
          } else {
            pendingJobIds.add(jobId);
          }
        } on Object catch (error) {
          failures.add(
            LocalSessionRecordingRecoveryFailure(
              jobId: jobId,
              message: error.toString(),
            ),
          );
        }
      }
      await for (final candidate in entity.list(followLinks: false)) {
        if (candidate is! File || !await candidate.exists()) {
          continue;
        }
        final name = _pathBasename(candidate.path);
        if (!name.startsWith(_recordingHandoffFilePrefix) ||
            name.endsWith('.manifest.json') ||
            name.endsWith('.claim')) {
          continue;
        }
        final suffix = name.substring(_recordingHandoffFilePrefix.length);
        if (suffix.length < 32) {
          orphanPaths.add(candidate.path);
          continue;
        }
        final jobId = suffix.substring(0, 32);
        final manifest = File(
          '${entity.path}${Platform.pathSeparator}'
          '$_recordingHandoffFilePrefix$jobId.ndjson.manifest.json',
        );
        if (!await manifest.exists()) {
          orphanPaths.add(candidate.path);
        }
      }
    }
    return LocalSessionRecordingRecoveryResult(
      recoveredPaths: List<String>.unmodifiable(recoveredPaths),
      pendingJobIds: List<String>.unmodifiable(pendingJobIds),
      orphanPaths: List<String>.unmodifiable(orphanPaths),
      failures: List<LocalSessionRecordingRecoveryFailure>.unmodifiable(
        failures,
      ),
    );
  }

  Future<_RecordingHandoffManifest> _ensureHandoffManifest({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    required String? displayName,
  }) async {
    _validateHandoffJob(job, handoffDirectory);
    final root = await _recordingRoot();
    final destinationPath = _requireLibraryPath(
      destination.file.absolute.path,
      root,
    );
    final file = _handoffManifestFile(job);
    if (await file.exists()) {
      final existing = await _readHandoffManifest(file);
      if (existing.job.jobId != job.jobId ||
          existing.job.sessionId != job.sessionId ||
          existing.job.handoffPath != job.handoffPath ||
          existing.job.errorPath != job.errorPath ||
          existing.destinationPath != destinationPath) {
        throw LocalSessionRecordingFinalizeException(
          failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
          jobId: job.jobId,
          message: 'Recording handoff manifest does not match the native job.',
        );
      }
      return existing;
    }
    final manifest = _RecordingHandoffManifest(
      job: job,
      destinationPath: destinationPath,
      semanticEvents: List<TerminalRecordingSemanticEvent>.unmodifiable(
        semanticEvents,
      ),
      createdAtUtc: _now().toUtc(),
      ownerPid: pid,
      displayName: displayName,
    );
    final manifestPath = file.path;
    await Isolate.run(
      () => writeStringAtomically(
        File(manifestPath),
        jsonEncode(manifest.toJson()),
      ),
    );
    return manifest;
  }

  File _handoffManifestFile(TerminalRecordingFinalizeJob job) {
    return File('${job.handoffPath}.manifest.json');
  }

  Future<_RecordingHandoffManifest> _readHandoffManifest(File file) async {
    const maximumManifestBytes = 4 * 1024 * 1024;
    final manifestPath = file.path;
    return Isolate.run(() async {
      final manifestFile = File(manifestPath);
      if (await manifestFile.length() > maximumManifestBytes) {
        throw const FormatException('Recording handoff manifest is too large.');
      }
      return _RecordingHandoffManifest.fromJson(
        jsonDecode(await manifestFile.readAsString()),
      );
    });
  }

  Future<bool> _handoffJobArtifactExists(
    TerminalRecordingFinalizeJob job,
  ) async {
    final paths = <String>[
      job.handoffPath,
      '${job.handoffPath}.part',
      job.errorPath,
      '${job.errorPath}.part',
      _handoffManifestFile(job).path,
      _handoffLeaseFile(job).path,
    ];
    for (final path in paths) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return true;
      }
    }
    return false;
  }

  Future<_RecordingHandoffLease?> _tryAcquireHandoffLease(
    TerminalRecordingFinalizeJob job,
  ) async {
    final held = _handoffLeases[job.jobId];
    if (held != null) {
      return held;
    }
    final file = _handoffLeaseFile(job);
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message: 'Recording handoff claim must not be a symbolic link.',
      );
    }
    final RandomAccessFile handle;
    try {
      handle = await file.open(mode: FileMode.append);
    } on FileSystemException {
      return null;
    }
    try {
      // FileLock.exclusive is non-blocking. Unlike a PID marker, the OS drops
      // this claim automatically if its owning process exits unexpectedly.
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      return null;
    }
    final lease = _RecordingHandoffLease(handle: handle);
    _handoffLeases[job.jobId] = lease;
    return lease;
  }

  Future<_RecordingHandoffLease?> _beginHandoffFinalize(
    TerminalRecordingFinalizeJob job,
  ) async {
    final lease = await _tryAcquireHandoffLease(job);
    if (lease == null || lease.finalizing) {
      return null;
    }
    lease.finalizing = true;
    return lease;
  }

  Future<void> _releaseHandoffLease(
    TerminalRecordingFinalizeJob job,
    _RecordingHandoffLease lease,
  ) async {
    if (identical(_handoffLeases[job.jobId], lease)) {
      _handoffLeases.remove(job.jobId);
    }
    lease.finalizing = false;
    try {
      await lease.handle.unlock();
    } on FileSystemException {
      // Closing the descriptor below still releases the process claim.
    }
    try {
      await lease.handle.close();
    } on FileSystemException {
      // The descriptor is no longer reusable even when close reports failure.
    }
    // Never unlink a claim file. A contender may already have the same inode
    // open; unlinking and recreating it would allow a third process to lock a
    // different inode for the same job concurrently. The tiny file is a stable
    // tombstone inside the process-private handoff directory.
  }

  File _handoffLeaseFile(TerminalRecordingFinalizeJob job) {
    return File('${job.handoffPath}.claim');
  }

  LocalSessionRecordingFinalizeException _handoffClaimUnavailable(
    TerminalRecordingFinalizeJob job,
  ) {
    return LocalSessionRecordingFinalizeException(
      failure:
          LocalSessionRecordingFinalizeFailure.claimedByAnotherProcess,
      jobId: job.jobId,
      message:
          'Recording finalize is already claimed by another live process.',
    );
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A completed destination remains durable. A leftover manifest is
      // recognized as completed on the next startup recovery pass.
    }
  }

  void _validateHandoffJob(
    TerminalRecordingFinalizeJob job,
    Directory handoffDirectory,
  ) {
    final directory = handoffDirectory.absolute;
    final directoryName = _pathBasename(directory.path);
    final expectedHandoffName =
        '$_recordingHandoffFilePrefix${job.jobId}.ndjson';
    final expectedErrorName = '$expectedHandoffName.error.json';
    final handoff = File(job.handoffPath).absolute;
    final error = File(job.errorPath).absolute;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(job.jobId) ||
        !directoryName.startsWith(_recordingHandoffDirectoryPrefix) ||
        handoff.parent.path != directory.path ||
        error.parent.path != directory.path ||
        _pathBasename(handoff.path) != expectedHandoffName ||
        _pathBasename(error.path) != expectedErrorName) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message:
            'Native recording finalize paths escaped their private directory.',
      );
    }
  }

  Future<LocalSessionRecordingFinalizeException> _nativeFinalizeFailure(
    TerminalRecordingFinalizeJob job,
    File errorFile,
  ) async {
    const maximumErrorBytes = 64 * 1024;
    String message = 'Native recording finalize failed.';
    try {
      if (await errorFile.length() <= maximumErrorBytes) {
        final decoded = jsonDecode(await errorFile.readAsString());
        if (decoded is Map && decoded['message'] is String) {
          message = decoded['message']! as String;
        }
      }
    } on Object {
      // Preserve a bounded generic error for malformed native error files.
    }
    return LocalSessionRecordingFinalizeException(
      failure: LocalSessionRecordingFinalizeFailure.nativeFailed,
      jobId: job.jobId,
      message: message,
    );
  }

  Future<LocalSessionRecordingDestination> reserve({
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) async {
    final runtimeSegment = _identitySegment(
      runtimeSessionId,
      'Runtime session',
    );
    final rootDirectory = await ensureRecordingDirectory();

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
    final path = destination.file.absolute.path;
    final encoder = _encoder;
    if (encoder == null) {
      await _fileWriter(path, recording);
    } else {
      // Explicit test/custom seams retain their string contract. Production
      // defaults keep encode and atomic file IO together in the worker isolate.
      final contents = await encoder(recording);
      await writeStringAtomically(destination.file, contents);
    }
    _reservedPaths.remove(path);
    try {
      await _indexSavedRecording(
        destination.file.absolute,
        recording,
        displayName: displayName,
      );
    } on Object {
      // The recording is durable. A missing index entry is recoverable during
      // the next lightweight library scan and must not fail the capture.
    }
    return path;
  }

  void release(LocalSessionRecordingDestination destination) {
    _reservedPaths.remove(destination.file.absolute.path);
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
    final decoder = _decoder;
    if (decoder != null) {
      return decoder(await file.readAsString());
    }
    return _fileReader(file.absolute.path);
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
    return _withIndexLock(_listRecordingsUnlocked);
  }

  Future<List<LocalSessionRecordingEntry>> _listRecordingsUnlocked() async {
    final root = await _recordingRoot();
    if (!await root.exists()) {
      return const <LocalSessionRecordingEntry>[];
    }
    final loadedIndex = await _loadLibraryIndex(root);
    final index = loadedIndex.index;
    var indexChanged = loadedIndex.needsWrite;
    final entries = <LocalSessionRecordingEntry>[];
    final discoveredPaths = <String>{};
    var reachedLimit = false;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entries.length >= _maxRecordingLibraryEntries) {
        reachedLimit = true;
        break;
      }
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.ndjson') ||
          entity.path.contains('.tmp.')) {
        continue;
      }
      final file = entity.absolute;
      final path = file.path;
      discoveredPaths.add(path);
      final stat = await file.stat();
      var metadata = index.entries[path];
      if (metadata == null || !metadata.matches(stat)) {
        metadata = await _metadataForFile(file, stat);
        index.entries[path] = metadata;
        indexChanged = true;
      }
      entries.add(
        metadata.toEntry(
          path: path,
          displayName:
              index.names[path] ??
              _basenameWithoutExtension(file.uri.pathSegments.last),
        ),
      );
    }
    if (!reachedLimit) {
      final staleMetadata = index.entries.keys
          .where((path) => !discoveredPaths.contains(path))
          .toList(growable: false);
      final staleNames = index.names.keys
          .where((path) => !discoveredPaths.contains(path))
          .toList(growable: false);
      if (staleMetadata.isNotEmpty || staleNames.isNotEmpty) {
        indexChanged = true;
        for (final path in staleMetadata) {
          index.entries.remove(path);
        }
        for (final path in staleNames) {
          index.names.remove(path);
        }
      }
    }
    if (indexChanged) {
      await _writeLibraryIndex(root, index);
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
    await _withIndexLock(() async {
      final root = await _recordingRoot();
      final path = _requireLibraryPath(recordingPath, root);
      if (!await File(path).exists()) {
        throw FileSystemException('Recording file does not exist', path);
      }
      final index = (await _loadLibraryIndex(root)).index;
      index.names[path] = normalizedName;
      await _writeLibraryIndex(root, index);
    });
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
    final encoder = _encoder;
    if (encoder == null) {
      await _fileWriter(File(normalizedDestination).absolute.path, recording);
    } else {
      final contents = await encoder(recording);
      await writeStringAtomically(File(normalizedDestination), contents);
    }
  }

  Future<void> forgetRecording(String recordingPath) async {
    await _withIndexLock(() async {
      final root = await _recordingRoot();
      final path = _requireLibraryPath(recordingPath, root);
      final index = (await _loadLibraryIndex(root)).index;
      final changed =
          index.names.remove(path) != null ||
          index.entries.remove(path) != null;
      if (changed) {
        await _writeLibraryIndex(root, index);
      }
    });
  }

  Future<Directory> _recordingRoot() async {
    final supportDirectory = await directoryResolver();
    return Directory(
      '${supportDirectory.absolute.path}${Platform.pathSeparator}'
      'ianvs_recordings',
    ).absolute;
  }

  Future<_RecordingIndexedMetadata> _metadataForFile(
    File file,
    FileStat stat,
  ) async {
    try {
      if (stat.size > _maxRecordingFileBytes) {
        throw const FormatException(
          'Recording file exceeds the library limit.',
        );
      }
      final metadata = await _readRecordingMetadataLine(file, stat.size);
      return _RecordingIndexedMetadata(
        modifiedMicros: stat.modified.toUtc().microsecondsSinceEpoch,
        fileSizeBytes: stat.size,
        createdAtUtc: metadata.createdAtUtc,
        duration: await _readLastRecordingOffset(file, stat.size),
        sessionId: metadata.sessionId,
        recordingSchemaVersion: metadata.schemaVersion,
        inputPolicy: metadata.inputPolicy,
      );
    } on Object catch (error) {
      return _RecordingIndexedMetadata(
        modifiedMicros: stat.modified.toUtc().microsecondsSinceEpoch,
        fileSizeBytes: stat.size,
        createdAtUtc: stat.modified.toUtc(),
        duration: Duration.zero,
        error: error.toString(),
      );
    }
  }

  Future<TerminalRecordingMetadata> _readRecordingMetadataLine(
    File file,
    int fileSizeBytes,
  ) async {
    if (fileSizeBytes <= 0) {
      throw const FormatException('Recording file is empty.');
    }
    final firstLine = await file
        .openRead(0, min(fileSizeBytes, _recordingMetadataReadBytes))
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final decoded = jsonDecode(firstLine);
    if (decoded is! Map || decoded['record_type'] != 'metadata') {
      throw const FormatException(
        'Recording metadata must be the first NDJSON record.',
      );
    }
    final schemaVersion = decoded['schema_version'];
    final sessionId = decoded['session_id'];
    final createdAtValue = decoded['created_at_utc'];
    final createdAtUtc = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)
        : null;
    final inputPolicy = switch (decoded['input_policy']) {
      'record' => TerminalRecordingInputPolicy.record,
      'redact' => TerminalRecordingInputPolicy.redact,
      _ => null,
    };
    if (schemaVersion is! int ||
        schemaVersion <= 0 ||
        sessionId is! String ||
        sessionId.trim().isEmpty ||
        createdAtUtc == null ||
        !createdAtUtc.isUtc ||
        inputPolicy == null) {
      throw const FormatException('Recording metadata is invalid.');
    }
    return TerminalRecordingMetadata(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      createdAtUtc: createdAtUtc,
      inputPolicy: inputPolicy,
    );
  }

  Future<Duration> _readLastRecordingOffset(
    File file,
    int fileSizeBytes,
  ) async {
    if (fileSizeBytes <= 0) {
      return Duration.zero;
    }
    final handle = await file.open();
    try {
      final start = max(0, fileSizeBytes - _recordingMetadataReadBytes);
      await handle.setPosition(start);
      final bytes = await handle.read(fileSizeBytes - start);
      final lines = const LineSplitter().convert(
        utf8.decode(bytes, allowMalformed: true),
      );
      for (final line in lines.reversed) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map && decoded['record_type'] == 'event') {
            final offset = decoded['monotonic_offset_micros'];
            if (offset is int && offset >= 0) {
              return Duration(microseconds: offset);
            }
          }
        } on FormatException {
          // The first tail fragment can begin in the middle of a large line.
        }
      }
      return Duration.zero;
    } finally {
      await handle.close();
    }
  }

  Future<_RecordingLibraryIndexLoad> _loadLibraryIndex(Directory root) async {
    final file = File(
      '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
    );
    if (!await file.exists()) {
      return _RecordingLibraryIndexLoad(
        _RecordingLibraryIndex(),
        needsWrite: true,
      );
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException(
          'Recording library index is not an object.',
        );
      }
      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion != 1 &&
          schemaVersion != _recordingLibraryIndexSchemaVersion) {
        throw const FormatException(
          'Recording library index schema is unsupported.',
        );
      }
      final names = <String, String>{};
      final rawNames = decoded['names'];
      var needsWrite = schemaVersion == 1;
      if (rawNames != null && rawNames is! Map) {
        throw const FormatException('Recording library names are invalid.');
      }
      final namesJson = rawNames is Map ? rawNames : const <Object?, Object?>{};
      for (final entry in namesJson.entries) {
        if (entry case MapEntry(:final String key, :final String value)) {
          names[key] = value;
        } else {
          needsWrite = true;
        }
      }
      final metadata = <String, _RecordingIndexedMetadata>{};
      if (schemaVersion == _recordingLibraryIndexSchemaVersion) {
        final rawEntries = decoded['entries'];
        if (rawEntries != null && rawEntries is! Map) {
          throw const FormatException('Recording library entries are invalid.');
        }
        final entriesJson = rawEntries is Map
            ? rawEntries
            : const <Object?, Object?>{};
        for (final entry in entriesJson.entries) {
          final parsed = _RecordingIndexedMetadata.tryFromJson(entry.value);
          if (entry case MapEntry(:final String key) when parsed != null) {
            metadata[key] = parsed;
          } else {
            needsWrite = true;
          }
        }
      }
      return _RecordingLibraryIndexLoad(
        _RecordingLibraryIndex(names: names, entries: metadata),
        needsWrite: needsWrite,
      );
    } on Object {
      try {
        await quarantineCorruptFile(file);
      } on Object {
        // A failed quarantine still falls back to an in-memory rebuild.
      }
      return _RecordingLibraryIndexLoad(
        _RecordingLibraryIndex(),
        needsWrite: true,
      );
    }
  }

  Future<void> _indexSavedRecording(
    File file,
    TerminalRecording recording, {
    String? displayName,
  }) async {
    await _withIndexLock(() async {
      final stat = await file.stat();
      final root = await _recordingRoot();
      final path = _requireLibraryPath(file.path, root);
      final index = (await _loadLibraryIndex(root)).index;
      index.entries[path] = _metadataFromRecording(recording, stat);
      if (displayName != null) {
        index.names[path] = _normalizedDisplayName(displayName);
      }
      await _writeLibraryIndex(root, index);
    });
  }

  Future<void> _indexFinalizedRecording(
    File file,
    LocalSessionRecordingFinalizedMetadata finalized, {
    String? displayName,
  }) async {
    await _withIndexLock(() async {
      final stat = await file.stat();
      final root = await _recordingRoot();
      final path = _requireLibraryPath(file.path, root);
      final index = (await _loadLibraryIndex(root)).index;
      index.entries[path] = _RecordingIndexedMetadata(
        modifiedMicros: stat.modified.toUtc().microsecondsSinceEpoch,
        fileSizeBytes: stat.size,
        createdAtUtc: finalized.createdAtUtc,
        duration: finalized.duration,
        sessionId: finalized.sessionId,
        recordingSchemaVersion: finalized.schemaVersion,
        inputPolicy: finalized.inputPolicy,
      );
      if (displayName != null) {
        index.names[path] = _normalizedDisplayName(displayName);
      }
      await _writeLibraryIndex(root, index);
    });
  }

  _RecordingIndexedMetadata _metadataFromRecording(
    TerminalRecording recording,
    FileStat stat,
  ) {
    return _RecordingIndexedMetadata(
      modifiedMicros: stat.modified.toUtc().microsecondsSinceEpoch,
      fileSizeBytes: stat.size,
      createdAtUtc: recording.metadata.createdAtUtc,
      duration: recording.events.isEmpty
          ? Duration.zero
          : recording.events.last.monotonicOffset,
      sessionId: recording.metadata.sessionId,
      recordingSchemaVersion: recording.metadata.schemaVersion,
      inputPolicy: recording.metadata.inputPolicy,
    );
  }

  Future<void> _writeLibraryIndex(
    Directory root,
    _RecordingLibraryIndex index,
  ) async {
    final sortedNames = Map<String, String>.fromEntries(
      index.names.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
    final entryList = index.entries.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedEntries = Map<String, Object?>.fromEntries(
      entryList.map(
        (entry) => MapEntry<String, Object?>(entry.key, entry.value.toJson()),
      ),
    );
    await writeStringAtomically(
      File(
        '${root.path}${Platform.pathSeparator}$_recordingLibraryIndexFileName',
      ),
      jsonEncode(<String, Object?>{
        'schemaVersion': _recordingLibraryIndexSchemaVersion,
        'names': sortedNames,
        'entries': sortedEntries,
      }),
    );
  }

  Future<T> _withIndexLock<T>(Future<T> Function() operation) {
    final result = _indexOperationTail.then((_) => operation());
    _indexOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
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

String _pathBasename(String value) {
  final segments = value.split(Platform.pathSeparator);
  return segments.isEmpty ? value : segments.last;
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random, max, min;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
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
typedef LocalSessionRecordingNativeJobStatusProbe =
    TerminalRecordingFinalizeJobStatus Function(
      TerminalRecordingFinalizeJob job, {
      required bool consumeTerminal,
    });
typedef LocalSessionRecordingDestinationIdentityReader =
    Future<(int, String)> Function(String destinationPath);
typedef LocalSessionRecordingDestinationCleanupBarrier =
    Future<void> Function(String destinationPath);
typedef LocalSessionRecordingSettlementPersistenceBarrier =
    Future<void> Function(String jobId);
typedef LocalSessionRecordingDestinationGcPreLockBarrier =
    Future<void> Function(Directory indexRoot);

const int _maxRecordingLibraryEntries = 1000;
const int _maxRecordingFileBytes = 128 * 1024 * 1024;
const int _recordingMetadataReadBytes = 64 * 1024;
const String _recordingLibraryIndexFileName = 'library.json';
// This is the repository index contract, independent of recording payloads.
const int _recordingLibraryIndexSchemaVersion = 1;
const String _recordingHandoffDirectoryPrefix = '.ianvs-recording-handoff-';
const String _recordingHandoffFilePrefix = '.ianvs-recording-handoff-';
const Duration _defaultRecordingFinalizeTimeout = Duration(seconds: 3);
const Duration _defaultRecordingFinalizePollInterval = Duration(
  milliseconds: 25,
);
const Duration _defaultRecordingSettlementObservationTimeout = Duration(
  minutes: 2,
);
// This is the native handoff contract, independent of recording payloads.
const int _recordingHandoffManifestSchemaVersion = 1;
const int _maximumRecordingHandoffManifestBytes = 4 * 1024 * 1024;
const int _maximumNativeSettlementDiagnosticBytes = 2048;
const int _maximumRecordingDestinationMarkerBytes = 16 * 1024;
const int _maximumOrphanDestinationSidecarsPerPass = 32;
const int _destinationSidecarBucketCount = 256;
const int _destinationSidecarMetadataSchemaVersion = 1;
const int _maximumDestinationSidecarQuarantineEntries = 32;
const Duration _destinationSidecarQuarantineMaximumAge = Duration(days: 7);
const int _defaultDestinationLockRetryLimit = 4;
const Duration _defaultDestinationLockRetryDelay = Duration(milliseconds: 5);

final class LocalSessionRecordingDestinationBusyException implements Exception {
  const LocalSessionRecordingDestinationBusyException(this.path);

  final String path;

  @override
  String toString() => 'Recording destination is busy: $path';
}

final class LocalSessionRecordingUnsupportedSidecarSchemaException
    implements Exception {
  const LocalSessionRecordingUnsupportedSidecarSchemaException({
    required this.path,
    required this.schemaVersion,
  });

  final String path;
  final Object schemaVersion;

  @override
  String toString() =>
      'Unsupported recording destination sidecar schema $schemaVersion: $path';
}

final class LocalSessionRecordingUnsupportedSchemaException
    implements Exception {
  const LocalSessionRecordingUnsupportedSchemaException({
    required this.path,
    required this.schemaVersion,
  });

  final String path;
  final int schemaVersion;

  @override
  String toString() => 'Unsupported recording schema $schemaVersion: $path';
}

enum _RecordingHandoffPhase {
  reserved,
  capturing,
  preparing,
  nativePrepared,
  nativeTerminationUnknown,
}

int _synchronousManifestWriteSerial = 0;
final Map<String, Object> _processHandoffClaimOwners = <String, Object>{};
final Map<String, Object> _processDestinationClaimOwners = <String, Object>{};

String _newHandoffJobId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _rejectUnsupportedDestinationSidecarSchema(
  Object? decoded, {
  required String path,
}) {
  final schemaVersion = decoded is Map ? decoded['schemaVersion'] : null;
  if (schemaVersion == _destinationSidecarMetadataSchemaVersion) {
    return;
  }
  throw LocalSessionRecordingUnsupportedSidecarSchemaException(
    path: path,
    schemaVersion: schemaVersion is Object
        ? schemaVersion
        : 'missing-or-unrecognized',
  );
}

enum LocalSessionRecordingFinalizeFailure {
  cancelled,
  timedOut,
  nativeFailed,
  invalidHandoff,
  unsupportedManifestSchema,
  claimedByAnotherProcess,
  nativeTerminationUnknown,
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
    this.failure,
  });

  final String jobId;
  final String message;
  final LocalSessionRecordingFinalizeFailure? failure;
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
    required this.phase,
    required this.destinationReservationNonce,
    this.displayName,
    this.nativeSettlementDiagnostic,
  });

  final TerminalRecordingFinalizeJob job;
  final String destinationPath;
  final List<TerminalRecordingSemanticEvent> semanticEvents;
  final DateTime createdAtUtc;
  final int ownerPid;
  final _RecordingHandoffPhase phase;
  final String destinationReservationNonce;
  final String? displayName;
  final String? nativeSettlementDiagnostic;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _recordingHandoffManifestSchemaVersion,
    'jobId': job.jobId,
    'sessionId': job.sessionId,
    'handoffPath': job.handoffPath,
    'errorPath': job.errorPath,
    'destinationPath': destinationPath,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'ownerPid': ownerPid,
    'phase': phase.name,
    'destinationReservationNonce': destinationReservationNonce,
    if (displayName != null) 'displayName': displayName,
    if (nativeSettlementDiagnostic != null)
      'nativeSettlementDiagnostic': nativeSettlementDiagnostic,
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
    final phaseName = value['phase'];
    final displayName = value['displayName'];
    final nativeSettlementDiagnostic = value['nativeSettlementDiagnostic'];
    final destinationReservationNonce = value['destinationReservationNonce'];
    final rawSemantics = value['semanticEvents'];
    final createdAtUtc = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)?.toUtc()
        : null;
    if (schemaVersion != _recordingHandoffManifestSchemaVersion) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.unsupportedManifestSchema,
        jobId: jobId is String ? jobId : 'unknown',
        message:
            'Recording handoff manifest schema $schemaVersion is unsupported.',
      );
    }
    final phase = phaseName is String
        ? _RecordingHandoffPhase.values
              .where((candidate) => candidate.name == phaseName)
              .firstOrNull
        : null;
    if (jobId is! String ||
        sessionId is! String ||
        handoffPath is! String ||
        errorPath is! String ||
        destinationPath is! String ||
        createdAtUtc == null ||
        ownerPid is! int ||
        ownerPid <= 0 ||
        phase == null ||
        destinationReservationNonce is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(destinationReservationNonce) ||
        (displayName != null && displayName is! String) ||
        (nativeSettlementDiagnostic != null &&
            (nativeSettlementDiagnostic is! String ||
                utf8.encode(nativeSettlementDiagnostic).length >
                    _maximumNativeSettlementDiagnosticBytes)) ||
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
      phase: phase,
      destinationReservationNonce: destinationReservationNonce,
      displayName: displayName as String?,
      nativeSettlementDiagnostic: nativeSettlementDiagnostic as String?,
    );
  }
}

final class _RecordingHandoffLease {
  _RecordingHandoffLease({required this.handle, required this.claimKey});

  final RandomAccessFile handle;
  final String claimKey;
  bool finalizing = false;
}

final class _RecordingHandoffSettlementObserver {
  final Completer<void> termination = Completer<void>();
  late final Future<void> future;
  bool abandonRequested = false;

  void terminate() {
    abandonRequested = true;
    if (!termination.isCompleted) {
      termination.complete();
    }
  }
}

String _nativeTerminalStatusMessage(TerminalRecordingFinalizeJobStatus status) {
  final detail = [?status.errorCode, ?status.message].join(': ');
  return 'Native recording finalize reached ${status.state.name} without a '
      'recoverable artifact${detail.isEmpty ? '.' : ': $detail'}';
}

String _boundedUtf8Prefix(String value, int maximumBytes) {
  if (utf8.encode(value).length <= maximumBytes) {
    return value;
  }
  final buffer = StringBuffer();
  var usedBytes = 0;
  for (final rune in value.runes) {
    final scalar = String.fromCharCode(rune);
    final scalarBytes = utf8.encode(scalar).length;
    if (usedBytes + scalarBytes > maximumBytes) {
      break;
    }
    buffer.write(scalar);
    usedBytes += scalarBytes;
  }
  return buffer.toString();
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

Future<(int, String)> _expectedRecordingHandoffIdentityInBackground({
  required String handoffPath,
  required String expectedSessionId,
  required List<TerminalRecordingSemanticEvent> semanticEvents,
}) {
  return Isolate.run(() async {
    final handoffFile = File(handoffPath);
    final handoffLength = await handoffFile.length();
    if (handoffLength > _maxRecordingFileBytes) {
      throw const FormatException(
        'Recording handoff exceeds the library limit.',
      );
    }
    final recording = const TerminalRecordingCodec().decode(
      await handoffFile.readAsString(),
    );
    if (recording.metadata.sessionId != expectedSessionId) {
      throw const FormatException(
        'Recording handoff used a different session id.',
      );
    }
    final enriched = const TerminalRecordingSemanticMerger().merge(
      recording,
      semanticEvents,
    );
    final expectedBytes = utf8.encode(
      const TerminalRecordingCodec().encode(enriched),
    );
    final expectedHash = await Sha256().hash(expectedBytes);
    return (
      expectedBytes.length,
      expectedHash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  });
}

Future<(int, String)> _recordingDestinationContentIdentityInBackground(
  String destinationPath,
) {
  return Isolate.run(() async {
    final file = File(destinationPath);
    final initialLength = await file.length();
    if (initialLength > _maxRecordingFileBytes) {
      throw const FormatException(
        'Recording destination exceeds the library limit.',
      );
    }
    final sink = Sha256().toSync().newHashSink();
    await for (final chunk in file.openRead(0, initialLength)) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    if (await file.length() != initialLength) {
      throw const FormatException(
        'Recording destination changed while its identity was computed.',
      );
    }
    return (
      initialLength,
      hash.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
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
  const LocalSessionRecordingDestination(
    this.file, {
    required this.reservationNonce,
  });

  final File file;
  final String reservationNonce;
}

final class _RecordingDestinationReservation {
  _RecordingDestinationReservation({
    required this.destinationPath,
    required this.sessionId,
    required this.nonce,
    required this.claimKey,
    required this.handle,
  });

  final String destinationPath;
  final String sessionId;
  final String nonce;
  final String claimKey;
  final RandomAccessFile handle;
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
        (rawError != null && rawError is! String) ||
        (rawError == null &&
            (rawSchemaVersion != terminalRecordingSchemaVersion ||
                rawSessionId is! String ||
                rawSessionId.trim().isEmpty ||
                inputPolicy == null))) {
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
    this.settlementObservationTimeout =
        _defaultRecordingSettlementObservationTimeout,
    LocalSessionRecordingDestinationIdentityReader? destinationIdentityReader,
    LocalSessionRecordingDestinationCleanupBarrier? destinationCleanupBarrier,
    LocalSessionRecordingSettlementPersistenceBarrier?
    settlementPersistenceBarrier,
    LocalSessionRecordingDestinationGcPreLockBarrier?
    destinationGcPreLockBarrier,
    this.destinationLockRetryLimit = _defaultDestinationLockRetryLimit,
    this.destinationLockRetryDelay = _defaultDestinationLockRetryDelay,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  }) : directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _encoder = encoder,
       _decoder = decoder,
       _fileWriter = fileWriter ?? _encodeAndWriteRecordingInBackground,
       _fileReader = fileReader ?? _readAndDecodeRecordingInBackground,
       _handoffWorker = handoffWorker ?? _finalizeRecordingHandoffInBackground,
       _destinationIdentityReader =
           destinationIdentityReader ??
           _recordingDestinationContentIdentityInBackground,
       _destinationCleanupBarrier = destinationCleanupBarrier,
       _settlementPersistenceBarrier = settlementPersistenceBarrier,
       _destinationGcPreLockBarrier = destinationGcPreLockBarrier,
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
    if (settlementObservationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        settlementObservationTimeout,
        'settlementObservationTimeout',
        'Must be positive.',
      );
    }
    if (destinationLockRetryLimit <= 0) {
      throw ArgumentError.value(
        destinationLockRetryLimit,
        'destinationLockRetryLimit',
        'Must be positive.',
      );
    }
    if (destinationLockRetryDelay.isNegative) {
      throw ArgumentError.value(
        destinationLockRetryDelay,
        'destinationLockRetryDelay',
        'Must not be negative.',
      );
    }
  }

  final LocalSessionRecordingDirectoryResolver directoryResolver;
  final LocalSessionRecordingEncoder? _encoder;
  final LocalSessionRecordingDecoder? _decoder;
  final LocalSessionRecordingFileWriter _fileWriter;
  final LocalSessionRecordingFileReader _fileReader;
  final LocalSessionRecordingHandoffWorker _handoffWorker;
  final LocalSessionRecordingDestinationIdentityReader
  _destinationIdentityReader;
  final LocalSessionRecordingDestinationCleanupBarrier?
  _destinationCleanupBarrier;
  final LocalSessionRecordingSettlementPersistenceBarrier?
  _settlementPersistenceBarrier;
  final LocalSessionRecordingDestinationGcPreLockBarrier?
  _destinationGcPreLockBarrier;
  final Duration finalizeTimeout;
  final Duration finalizePollInterval;
  final Duration settlementObservationTimeout;
  final int destinationLockRetryLimit;
  final Duration destinationLockRetryDelay;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;
  final Set<String> _reservedPaths = <String>{};
  final Object _handoffClaimOwner = Object();
  final Object _destinationClaimOwner = Object();
  final Map<String, _RecordingDestinationReservation> _destinationReservations =
      <String, _RecordingDestinationReservation>{};
  final Map<String, _RecordingHandoffLease> _handoffLeases =
      <String, _RecordingHandoffLease>{};
  final Map<String, _RecordingHandoffSettlementObserver>
  _handoffSettlementObservers = <String, _RecordingHandoffSettlementObserver>{};
  final Map<String, LocalSessionRecordingRecoveryFailure>
  _nativeSettlementFailures = <String, LocalSessionRecordingRecoveryFailure>{};
  Future<void> _indexOperationTail = Future<void>.value();
  Future<Directory>? _handoffDirectoryFuture;
  int _destinationSidecarReferencesInspected = 0;

  @visibleForTesting
  Future<void>? nativeSettlementFutureForTesting(String jobId) =>
      _handoffSettlementObservers[jobId]?.future;

  @visibleForTesting
  int get destinationSidecarReferencesInspectedForTesting =>
      _destinationSidecarReferencesInspected;

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
    final created = await root.createTemp(_recordingHandoffDirectoryPrefix);
    return _canonicalHandoffDirectory(created, jobId: 'unallocated');
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
    final canonicalHandoffDirectory = await _canonicalHandoffDirectory(
      handoffDirectory,
      jobId: 'unallocated',
    );
    final root = await _recordingRoot();
    final destinationPath = await _validateNativeRecordingDestination(
      value: destination.file.absolute.path,
      libraryRoot: root,
      jobId: 'unallocated',
    );
    await _rejectUnsupportedDestinationMetadataForOperation(
      destinationPath: destinationPath,
      nonce: destination.reservationNonce,
    );
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final jobId = _newHandoffJobId();
      final handoffPath =
          '${canonicalHandoffDirectory.path}${Platform.pathSeparator}'
          '$_recordingHandoffFilePrefix$jobId.ndjson';
      final job = TerminalRecordingFinalizeJob(
        sessionId: sessionId,
        jobId: jobId,
        handoffPath: handoffPath,
        errorPath: '$handoffPath.error.json',
      );
      _validateHandoffJob(job, canonicalHandoffDirectory);
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
          handoffDirectory: canonicalHandoffDirectory,
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
    final root = await _recordingRoot();
    final destinationPath = await _validateNativeRecordingDestination(
      value: destination.file.absolute.path,
      libraryRoot: root,
      jobId: job.jobId,
    );
    await _rejectUnsupportedDestinationMetadataForOperation(
      destinationPath: destinationPath,
      nonce: destination.reservationNonce,
    );
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
      refreshMetadata: true,
      phase: _RecordingHandoffPhase.nativePrepared,
    );
  }

  /// Transfers a confirmed detached native prepare into the repository's
  /// durable settlement owner during application shutdown.
  ///
  /// The caller may stop waiting for a normal finalize timeout, but this
  /// method does not settle until the retained OS lease has observed an
  /// artifact/error or persisted a typed termination-unknown diagnostic. This
  /// prevents a replacement runtime graph from claiming a still-live worker.
  Future<void> settleDetachedNativeRecordingForShutdown({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    Object? finalizeError;
    StackTrace? finalizeStackTrace;
    try {
      await registerNativeRecordingJob(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: semanticEvents,
        displayName: displayName,
      );
      await finalizeNativeRecording(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: semanticEvents,
        displayName: displayName,
        nativeJobStatusProbe: nativeJobStatusProbe,
      );
      return;
    } on Object catch (error, stackTrace) {
      finalizeError = error;
      finalizeStackTrace = stackTrace;
    }

    final observer = _handoffSettlementObservers[job.jobId];
    if (observer != null) {
      await observer.future;
    }
    final settlementFailure = _nativeSettlementFailures[job.jobId];
    if (settlementFailure != null) {
      return;
    }
    var hasDurableDestinationCompletion = false;
    try {
      final manifest = await _readHandoffManifest(_handoffManifestFile(job));
      final root = await _recordingRoot();
      final destinationPath = await _validateNativeRecordingDestination(
        value: destination.file.absolute.path,
        libraryRoot: root,
        jobId: job.jobId,
      );
      hasDurableDestinationCompletion = await _hasMatchingDestinationCompletion(
        manifest: manifest,
        destinationPath: destinationPath,
      );
    } on LocalSessionRecordingUnsupportedSidecarSchemaException {
      rethrow;
    } on Object {
      // A bare destination is not proof that this job completed. Keep the
      // original settlement error unless its job/session/content marker is
      // both present and valid.
    }
    if (await File(job.handoffPath).exists() ||
        await File(job.errorPath).exists() ||
        hasDurableDestinationCompletion) {
      return;
    }
    if (finalizeError case LocalSessionRecordingFinalizeException(
      failure: LocalSessionRecordingFinalizeFailure.claimedByAnotherProcess,
    )) {
      return;
    }
    final heldLease = _handoffLeases[job.jobId];
    if (heldLease != null && !heldLease.finalizing) {
      await _recordNativeSettlementFailure(
        job,
        LocalSessionRecordingRecoveryFailure(
          jobId: job.jobId,
          message:
              'Native recording ownership could not be settled during '
              'shutdown: $finalizeError',
          failure:
              LocalSessionRecordingFinalizeFailure.nativeTerminationUnknown,
        ),
        nativeJobStatusProbe,
      );
      await _releaseHandoffLease(job, heldLease);
      return;
    }
    Error.throwWithStackTrace(finalizeError, finalizeStackTrace);
  }

  /// Marks the intent as transferred to an active native recorder.
  ///
  /// This bounded synchronous write closes the crash window between the
  /// synchronous native start request and publishing product recording state.
  void markNativeRecordingCaptureStartedSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
  }) {
    _refreshHandoffManifestSynchronously(
      job: job,
      handoffDirectory: handoffDirectory,
      phase: _RecordingHandoffPhase.capturing,
    );
  }

  /// Atomically persists all bounded semantic metadata before native prepare.
  ///
  /// Native prepare can make the PTY immediately releasable, so an async write
  /// after that boundary would leave a crash-recovered recording without its
  /// captured shell semantics.
  void prepareNativeRecordingJobMetadataSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) {
    _refreshHandoffManifestSynchronously(
      job: job,
      handoffDirectory: handoffDirectory,
      semanticEvents: semanticEvents,
      displayName: displayName,
      phase: _RecordingHandoffPhase.preparing,
    );
  }

  /// Removes an intent reservation only when native definitively rejected the
  /// transfer and therefore cannot still publish a handoff for this job.
  Future<void> abandonNativeRecordingJobReservation(
    TerminalRecordingFinalizeJob job,
  ) async {
    final manifestFile = _handoffManifestFile(job);
    final manifestType = await FileSystemEntity.type(
      manifestFile.path,
      followLinks: false,
    );
    if (manifestType == FileSystemEntityType.notFound) {
      return;
    }
    if (manifestType != FileSystemEntityType.file) {
      throw _invalidHandoff(
        job,
        'Recording handoff manifest is not a regular file.',
      );
    }

    final heldLease = _handoffLeases[job.jobId];
    final lease = heldLease ?? await _tryAcquireHandoffLease(job);
    if (lease == null) {
      throw _handoffClaimUnavailable(job);
    }
    var mayReleaseLease = !lease.finalizing;
    try {
      var manifest = await _readHandoffManifest(manifestFile);
      _validateAbandonedJobManifest(manifest, job);
      final reservation = _destinationReservations[manifest.destinationPath];
      if (reservation == null ||
          reservation.sessionId != job.sessionId ||
          reservation.nonce != manifest.destinationReservationNonce) {
        throw LocalSessionRecordingDestinationBusyException(
          manifest.destinationPath,
        );
      }
      _validateBoundDestinationReservation(reservation, job);

      if (lease.finalizing) {
        final observer = _handoffSettlementObservers[job.jobId];
        if (observer == null) {
          throw LocalSessionRecordingDestinationBusyException(
            manifest.destinationPath,
          );
        }
        observer.terminate();
        // terminate transfers the still-locked handoff lease from the
        // observer to this cleanup path. Its finally block can no longer
        // release the descriptor or race a late diagnostic manifest write.
        mayReleaseLease = true;
        try {
          await observer.future;
        } on Object {
          // A requested abandon makes any observer diagnostic obsolete. Its
          // future settling is the ownership barrier; cleanup below still
          // revalidates every durable identity before mutating artifacts.
        }
        if (!identical(_handoffLeases[job.jobId], lease)) {
          throw _invalidHandoff(
            job,
            'Stopped recording observer lost its handoff ownership.',
          );
        }
        manifest = await _readHandoffManifest(manifestFile);
        _validateAbandonedJobManifest(manifest, job);
        if (manifest.destinationPath != reservation.destinationPath ||
            manifest.destinationReservationNonce != reservation.nonce) {
          throw _invalidHandoff(
            job,
            'Stopped recording observer changed destination ownership.',
          );
        }
        _validateBoundDestinationReservation(reservation, job);
      }

      await _rejectUnsupportedDestinationMetadataForOperation(
        destinationPath: manifest.destinationPath,
        nonce: manifest.destinationReservationNonce,
      );
      await _deleteIfPresent(manifestFile);
      if (await FileSystemEntity.type(manifestFile.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw _invalidHandoff(
          job,
          'Recording handoff manifest could not be removed.',
        );
      }
      final released = _releaseDestinationReservation(
        manifest.destinationPath,
        expectedNonce: manifest.destinationReservationNonce,
      );
      if (!released) {
        throw LocalSessionRecordingDestinationBusyException(
          manifest.destinationPath,
        );
      }
      _reservedPaths.remove(manifest.destinationPath);
      await _cleanupDestinationSidecars(manifest.destinationPath);
      _nativeSettlementFailures.remove(job.jobId);
    } finally {
      if (mayReleaseLease) {
        await _releaseHandoffLease(job, lease);
      }
    }
  }

  void _validateAbandonedJobManifest(
    _RecordingHandoffManifest manifest,
    TerminalRecordingFinalizeJob job,
  ) {
    if (manifest.job.jobId != job.jobId ||
        manifest.job.sessionId != job.sessionId ||
        manifest.job.handoffPath != job.handoffPath ||
        manifest.job.errorPath != job.errorPath) {
      throw _invalidHandoff(
        job,
        'Recording handoff manifest belongs to another job.',
      );
    }
  }

  LocalSessionRecordingFinalizeException _invalidHandoff(
    TerminalRecordingFinalizeJob job,
    String message,
  ) {
    return LocalSessionRecordingFinalizeException(
      failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
      jobId: job.jobId,
      message: message,
    );
  }

  Future<String> finalizeNativeRecording({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    final root = await _recordingRoot();
    final destinationPath = await _validateNativeRecordingDestination(
      value: destination.file.absolute.path,
      libraryRoot: root,
      jobId: job.jobId,
    );
    await _rejectUnsupportedDestinationMetadataForOperation(
      destinationPath: destinationPath,
      nonce: destination.reservationNonce,
    );
    final lease = await _beginHandoffFinalize(job);
    if (lease == null) {
      throw _handoffClaimUnavailable(job);
    }
    var leaseTransferredToSettlementObserver = false;
    try {
      _validateHandoffJob(job, handoffDirectory);
      final manifest = await _ensureHandoffManifest(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: semanticEvents,
        displayName: displayName,
      );
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
        _destinationCompletionMarkerFile(destinationPath),
      );
      final destinationType = await FileSystemEntity.type(
        destinationPath,
        followLinks: false,
      );
      if (destinationType == FileSystemEntityType.file) {
        var hasMatchingCompletion = await _hasMatchingDestinationCompletion(
          manifest: manifest,
          destinationPath: destinationPath,
        );
        if (!hasMatchingCompletion &&
            await FileSystemEntity.type(
                  _destinationCompletionMarkerFile(destinationPath).path,
                  followLinks: false,
                ) ==
                FileSystemEntityType.notFound &&
            await FileSystemEntity.type(
                  manifest.job.handoffPath,
                  followLinks: false,
                ) ==
                FileSystemEntityType.file) {
          final expectedIdentity =
              await _expectedRecordingHandoffIdentityInBackground(
                handoffPath: manifest.job.handoffPath,
                expectedSessionId: manifest.job.sessionId,
                semanticEvents: manifest.semanticEvents,
              );
          await _writeDestinationCompletionMarker(
            manifest: manifest,
            destinationPath: destinationPath,
            expectedIdentity: expectedIdentity,
          );
          hasMatchingCompletion = await _hasMatchingDestinationCompletion(
            manifest: manifest,
            destinationPath: destinationPath,
          );
        }
        if (!hasMatchingCompletion) {
          throw LocalSessionRecordingFinalizeException(
            failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
            jobId: job.jobId,
            message:
                'Recording destination already exists without matching '
                'durable completion ownership.',
          );
        }
        await _deleteIfPresent(File(job.handoffPath));
        await _deleteIfPresent(File(job.errorPath));
        await _deleteIfPresent(_handoffManifestFile(job));
        final released = _releaseDestinationReservation(
          destinationPath,
          expectedNonce: manifest.destinationReservationNonce,
        );
        if (released) {
          _reservedPaths.remove(destinationPath);
        }
        _nativeSettlementFailures.remove(job.jobId);
        return destinationPath;
      }
      final handoffFile = File(manifest.job.handoffPath);
      final errorFile = File(manifest.job.errorPath);
      final stopwatch = Stopwatch()..start();
      while (true) {
        if (cancellation?.isCancelled == true) {
          final handoffType = await FileSystemEntity.type(
            handoffFile.path,
            followLinks: false,
          );
          final errorType = await FileSystemEntity.type(
            errorFile.path,
            followLinks: false,
          );
          final nativeWorkerIsStillLive =
              handoffType == FileSystemEntityType.notFound &&
              errorType == FileSystemEntityType.notFound;
          if (manifest.phase == _RecordingHandoffPhase.nativePrepared &&
              nativeWorkerIsStillLive) {
            _retainHandoffLeaseUntilNativeSettlement(
              job: manifest.job,
              handoffFile: handoffFile,
              errorFile: errorFile,
              lease: lease,
              nativeJobStatusProbe: nativeJobStatusProbe,
            );
            leaseTransferredToSettlementObserver = true;
          }
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
          await _consumeNativeFinalizeStatus(
            nativeJobStatusProbe,
            manifest.job,
          );
          throw await _nativeFinalizeFailure(manifest.job, errorFile);
        }
        if (stopwatch.elapsed >= finalizeTimeout) {
          if (manifest.phase == _RecordingHandoffPhase.nativePrepared) {
            _retainHandoffLeaseUntilNativeSettlement(
              job: manifest.job,
              handoffFile: handoffFile,
              errorFile: errorFile,
              lease: lease,
              nativeJobStatusProbe: nativeJobStatusProbe,
            );
            leaseTransferredToSettlementObserver = true;
          }
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

      // Revalidate immediately before the worker creates its sibling temp
      // file and atomically renames it. dart:io has no portable directory-FD
      // openat API, so keeping the canonical parent fixed and rejecting both
      // parent/leaf symlinks is the narrowest portable write boundary.
      final writeDestinationPath = await _validateNativeRecordingDestination(
        value: destinationPath,
        libraryRoot: root,
        jobId: manifest.job.jobId,
      );
      if (await FileSystemEntity.type(
            writeDestinationPath,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw LocalSessionRecordingFinalizeException(
          failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
          jobId: manifest.job.jobId,
          message:
              'Recording destination appeared after reservation and will not '
              'be overwritten.',
        );
      }
      final expectedIdentity =
          await _expectedRecordingHandoffIdentityInBackground(
            handoffPath: handoffFile.path,
            expectedSessionId: manifest.job.sessionId,
            semanticEvents: manifest.semanticEvents,
          );
      final finalized = await _handoffWorker(
        handoffPath: handoffFile.path,
        destinationPath: writeDestinationPath,
        expectedSessionId: manifest.job.sessionId,
        semanticEvents: manifest.semanticEvents,
      );
      await _writeDestinationCompletionMarker(
        manifest: manifest,
        destinationPath: writeDestinationPath,
        expectedIdentity: expectedIdentity,
      );
      if (!await _hasMatchingDestinationCompletion(
        manifest: manifest,
        destinationPath: writeDestinationPath,
      )) {
        throw LocalSessionRecordingFinalizeException(
          failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
          jobId: manifest.job.jobId,
          message:
              'Recording destination changed before completion was durable.',
        );
      }
      // Retain the native artifact until destination content ownership is
      // durably bound. A marker write failure then leaves both sides available
      // for explicit recovery instead of an unprovable destination alone.
      await _deleteIfPresent(handoffFile);
      await _consumeNativeFinalizeStatus(nativeJobStatusProbe, manifest.job);
      await _deleteIfPresent(_handoffManifestFile(manifest.job));
      final released = _releaseDestinationReservation(
        writeDestinationPath,
        expectedNonce: manifest.destinationReservationNonce,
      );
      if (released) {
        _reservedPaths.remove(destinationPath);
        _reservedPaths.remove(destination.file.absolute.path);
      }
      _nativeSettlementFailures.remove(job.jobId);
      try {
        await _indexFinalizedRecording(
          File(writeDestinationPath),
          finalized,
          displayName: manifest.displayName,
        );
      } on Object {
        // The destination is durable and the index can be rebuilt from its
        // lightweight metadata/tail scan.
      }
      return writeDestinationPath;
    } finally {
      if (!leaseTransferredToSettlementObserver) {
        await _releaseHandoffLease(job, lease);
      }
    }
  }

  Future<void> _consumeNativeFinalizeStatus(
    LocalSessionRecordingNativeJobStatusProbe? probe,
    TerminalRecordingFinalizeJob job,
  ) async {
    if (probe == null) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        final status = probe(job, consumeTerminal: true);
        if (status.state != TerminalRecordingFinalizeJobState.running) {
          return;
        }
      } on Object {
        // Artifact/error durability is authoritative. Native status is an
        // in-process liveness channel and must not invalidate a completed
        // file or delay settlement when its query transport is unavailable.
        return;
      }
      if (stopwatch.elapsed >= finalizeTimeout) {
        return;
      }
      await _delay(finalizePollInterval);
    }
  }

  /// Keeps the process claim alive after a bounded caller stops waiting.
  ///
  /// Native recording work is not cancelled by a Dart-side timeout or
  /// cancellation token. The observer therefore retains the same locked file
  /// descriptor until the worker publishes an artifact/error, reports a
  /// terminal native status, or reaches the bounded termination-unknown
  /// deadline. If this process exits first, the OS releases the lock.
  void _retainHandoffLeaseUntilNativeSettlement({
    required TerminalRecordingFinalizeJob job,
    required File handoffFile,
    required File errorFile,
    required _RecordingHandoffLease lease,
    required LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) {
    if (_handoffSettlementObservers.containsKey(job.jobId)) {
      return;
    }
    final observer = _RecordingHandoffSettlementObserver();
    _handoffSettlementObservers[job.jobId] = observer;
    observer.future = _observeNativeHandoffSettlement(
      job: job,
      handoffFile: handoffFile,
      errorFile: errorFile,
      lease: lease,
      observer: observer,
      nativeJobStatusProbe: nativeJobStatusProbe,
    );
    unawaited(
      observer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _observeNativeHandoffSettlement({
    required TerminalRecordingFinalizeJob job,
    required File handoffFile,
    required File errorFile,
    required _RecordingHandoffLease lease,
    required _RecordingHandoffSettlementObserver observer,
    required LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      while (true) {
        if (observer.termination.isCompleted) {
          return;
        }
        try {
          final handoffType = await FileSystemEntity.type(
            handoffFile.path,
            followLinks: false,
          );
          final errorType = await FileSystemEntity.type(
            errorFile.path,
            followLinks: false,
          );
          if (handoffType != FileSystemEntityType.notFound ||
              errorType != FileSystemEntityType.notFound) {
            return;
          }
          final status = nativeJobStatusProbe?.call(
            job,
            consumeTerminal: false,
          );
          if (status != null && status.isTerminal) {
            await _recordNativeSettlementFailure(
              job,
              LocalSessionRecordingRecoveryFailure(
                jobId: job.jobId,
                message: _nativeTerminalStatusMessage(status),
                failure: LocalSessionRecordingFinalizeFailure
                    .nativeTerminationUnknown,
              ),
              nativeJobStatusProbe,
            );
            return;
          }
        } on FileSystemException {
          // A transient metadata read is not proof that the native worker is
          // gone. Keep the stable claim and retry instead of exposing the job
          // to another process.
        } on Object {
          // Status transport may be transiently unavailable while the native
          // worker is still live. The bounded observation deadline below is
          // the fail-closed terminal fallback.
        }
        if (stopwatch.elapsed >= settlementObservationTimeout) {
          await _recordNativeSettlementFailure(
            job,
            LocalSessionRecordingRecoveryFailure(
              jobId: job.jobId,
              message:
                  'Native recording finalize termination is unknown after '
                  '${settlementObservationTimeout.inMilliseconds} ms; '
                  'manifest retained for explicit recovery.',
              failure:
                  LocalSessionRecordingFinalizeFailure.nativeTerminationUnknown,
            ),
            nativeJobStatusProbe,
          );
          return;
        }
        await Future.any<void>(<Future<void>>[
          _delay(finalizePollInterval),
          observer.termination.future,
        ]);
      }
    } finally {
      if (identical(_handoffSettlementObservers[job.jobId], observer)) {
        _handoffSettlementObservers.remove(job.jobId);
      }
      if (!observer.abandonRequested) {
        await _releaseHandoffLease(job, lease);
      }
    }
  }

  Future<void> _recordNativeSettlementFailure(
    TerminalRecordingFinalizeJob job,
    LocalSessionRecordingRecoveryFailure failure,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  ) async {
    final observer = _handoffSettlementObservers[job.jobId];
    if (observer?.abandonRequested ?? false) {
      return;
    }
    _nativeSettlementFailures.putIfAbsent(job.jobId, () => failure);
    await _persistNativeSettlementFailure(job, failure.message);
    if (observer?.abandonRequested ?? false) {
      _nativeSettlementFailures.remove(job.jobId);
      return;
    }
    try {
      nativeJobStatusProbe?.call(job, consumeTerminal: true);
    } on Object {
      // The manifest is now the durable terminal diagnostic. Native's bounded
      // in-process registry can evict this terminal entry independently.
    }
  }

  Future<void> _persistNativeSettlementFailure(
    TerminalRecordingFinalizeJob job,
    String diagnostic,
  ) async {
    final file = _handoffManifestFile(job);
    final existing = await _readHandoffManifest(file);
    if (existing.job.jobId != job.jobId ||
        existing.job.sessionId != job.sessionId ||
        existing.job.handoffPath != job.handoffPath ||
        existing.job.errorPath != job.errorPath) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message: 'Recording handoff manifest does not match the native job.',
      );
    }
    final refreshed = _RecordingHandoffManifest(
      job: existing.job,
      destinationPath: existing.destinationPath,
      semanticEvents: existing.semanticEvents,
      createdAtUtc: existing.createdAtUtc,
      ownerPid: existing.ownerPid,
      phase: _RecordingHandoffPhase.nativeTerminationUnknown,
      destinationReservationNonce: existing.destinationReservationNonce,
      displayName: existing.displayName,
      nativeSettlementDiagnostic: _boundedUtf8Prefix(
        diagnostic,
        _maximumNativeSettlementDiagnosticBytes,
      ),
    );
    final encoded = jsonEncode(refreshed.toJson());
    final path = file.path;
    await _settlementPersistenceBarrier?.call(job.jobId);
    await Isolate.run(() => writeStringAtomically(File(path), encoded));
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
    await _collectOrphanDestinationSidecars(root);
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
          var manifest = await _readHandoffManifest(candidate);
          _validateHandoffJob(manifest.job, entity);
          manifest = await _normalizeCurrentHandoffManifestDestination(
            manifest: manifest,
            manifestFile: candidate,
            libraryRoot: root,
          );
          jobId = manifest.job.jobId;
          _validateHandoffJob(manifest.job, entity);
          final completedDestinationPath =
              await _validateNativeRecordingDestination(
                value: manifest.destinationPath,
                libraryRoot: root,
                jobId: manifest.job.jobId,
              );
          final completedDestinationType = await FileSystemEntity.type(
            completedDestinationPath,
            followLinks: false,
          );
          final handoff = File(manifest.job.handoffPath);
          final error = File(manifest.job.errorPath);
          if (await handoff.exists() ||
              completedDestinationType == FileSystemEntityType.file) {
            try {
              final path = await finalizeNativeRecording(
                job: manifest.job,
                handoffDirectory: entity,
                destination: LocalSessionRecordingDestination(
                  File(manifest.destinationPath),
                  reservationNonce: manifest.destinationReservationNonce,
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
          } else if (await error.exists()) {
            final failure = await _nativeFinalizeFailure(manifest.job, error);
            failures.add(
              LocalSessionRecordingRecoveryFailure(
                jobId: jobId,
                message: failure.message,
              ),
            );
          } else {
            final nativeSettlementFailure = _nativeSettlementFailures[jobId];
            final persistedNativeSettlementFailure =
                manifest.phase ==
                    _RecordingHandoffPhase.nativeTerminationUnknown
                ? LocalSessionRecordingRecoveryFailure(
                    jobId: jobId,
                    message:
                        manifest.nativeSettlementDiagnostic ??
                        'Native recording finalize termination is unknown; '
                            'manifest retained for explicit recovery.',
                    failure: LocalSessionRecordingFinalizeFailure
                        .nativeTerminationUnknown,
                  )
                : null;
            final ownedHere = _handoffLeases.containsKey(jobId);
            final orphanLease = ownedHere
                ? null
                : await _tryAcquireHandoffLease(manifest.job);
            if (ownedHere || orphanLease == null) {
              pendingJobIds.add(jobId);
            } else {
              try {
                failures.add(
                  nativeSettlementFailure ??
                      persistedNativeSettlementFailure ??
                      LocalSessionRecordingRecoveryFailure(
                        jobId: jobId,
                        message:
                            'Recording handoff ${manifest.phase.name} intent '
                            'was abandoned before a native artifact was '
                            'published.',
                      ),
                );
              } finally {
                await _releaseHandoffLease(manifest.job, orphanLease);
              }
            }
          }
        } on LocalSessionRecordingUnsupportedSidecarSchemaException {
          rethrow;
        } on LocalSessionRecordingFinalizeException catch (error) {
          failures.add(
            LocalSessionRecordingRecoveryFailure(
              jobId: error.jobId,
              message: error.message,
              failure: error.failure,
            ),
          );
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
    bool refreshMetadata = false,
    _RecordingHandoffPhase? phase,
  }) async {
    _validateHandoffJob(job, handoffDirectory);
    final root = await _recordingRoot();
    final destinationPath = await _validateNativeRecordingDestination(
      value: destination.file.absolute.path,
      libraryRoot: root,
      jobId: job.jobId,
    );
    final destinationReservation = await _acquireDestinationReservation(
      destinationPath: destinationPath,
      sessionId: job.sessionId,
      expectedNonce: destination.reservationNonce,
      requireDestinationAbsent: false,
    );
    if (destinationReservation == null) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message: 'Recording destination is reserved by another live recording.',
      );
    }
    final file = _handoffManifestFile(job);
    if (await file.exists()) {
      var existing = await _readHandoffManifest(file);
      existing = await _normalizeCurrentHandoffManifestDestination(
        manifest: existing,
        manifestFile: file,
        libraryRoot: root,
      );
      if (existing.job.jobId != job.jobId ||
          existing.job.sessionId != job.sessionId ||
          existing.job.handoffPath != job.handoffPath ||
          existing.job.errorPath != job.errorPath ||
          existing.destinationPath != destinationPath ||
          existing.destinationReservationNonce !=
              destinationReservation.nonce) {
        throw LocalSessionRecordingFinalizeException(
          failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
          jobId: job.jobId,
          message: 'Recording handoff manifest does not match the native job.',
        );
      }
      _bindDestinationReservationToJob(destinationReservation, job);
      if (refreshMetadata) {
        final refreshed = _RecordingHandoffManifest(
          job: existing.job,
          destinationPath: existing.destinationPath,
          semanticEvents: List<TerminalRecordingSemanticEvent>.unmodifiable(
            semanticEvents,
          ),
          createdAtUtc: existing.createdAtUtc,
          ownerPid: existing.ownerPid,
          phase: phase ?? existing.phase,
          destinationReservationNonce: destinationReservation.nonce,
          displayName: displayName ?? existing.displayName,
          nativeSettlementDiagnostic: existing.nativeSettlementDiagnostic,
        );
        final manifestPath = file.path;
        await Isolate.run(
          () => writeStringAtomically(
            File(manifestPath),
            jsonEncode(refreshed.toJson()),
          ),
        );
        return refreshed;
      }
      return existing;
    }
    _bindDestinationReservationToJob(destinationReservation, job);
    final manifest = _RecordingHandoffManifest(
      job: job,
      destinationPath: destinationPath,
      semanticEvents: List<TerminalRecordingSemanticEvent>.unmodifiable(
        semanticEvents,
      ),
      createdAtUtc: _now().toUtc(),
      ownerPid: pid,
      phase: phase ?? _RecordingHandoffPhase.reserved,
      destinationReservationNonce: destinationReservation.nonce,
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

  void _refreshHandoffManifestSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required _RecordingHandoffPhase phase,
    List<TerminalRecordingSemanticEvent>? semanticEvents,
    String? displayName,
  }) {
    _validateHandoffJob(job, handoffDirectory);
    final file = _handoffManifestFile(job);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message: 'Recording handoff manifest is unavailable.',
      );
    }
    if (file.lengthSync() > _maximumRecordingHandoffManifestBytes) {
      throw const FormatException('Recording handoff manifest is too large.');
    }
    final existing = _RecordingHandoffManifest.fromJson(
      jsonDecode(file.readAsStringSync()),
    );
    if (existing.job.jobId != job.jobId ||
        existing.job.sessionId != job.sessionId ||
        existing.job.handoffPath != job.handoffPath ||
        existing.job.errorPath != job.errorPath) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message: 'Recording handoff manifest does not match the native job.',
      );
    }
    final refreshed = _RecordingHandoffManifest(
      job: existing.job,
      destinationPath: existing.destinationPath,
      semanticEvents: List<TerminalRecordingSemanticEvent>.unmodifiable(
        semanticEvents ?? existing.semanticEvents,
      ),
      createdAtUtc: existing.createdAtUtc,
      ownerPid: existing.ownerPid,
      phase: phase,
      destinationReservationNonce: existing.destinationReservationNonce,
      displayName: displayName ?? existing.displayName,
      nativeSettlementDiagnostic: existing.nativeSettlementDiagnostic,
    );
    _writeHandoffManifestSynchronously(file, refreshed);
  }

  void _writeHandoffManifestSynchronously(
    File file,
    _RecordingHandoffManifest manifest,
  ) {
    final serial = _synchronousManifestWriteSerial++;
    final nonce = _newHandoffJobId();
    final temporary = File('${file.path}.metadata.$pid.$serial.$nonce.part');
    RandomAccessFile? handle;
    try {
      handle = temporary.openSync(mode: FileMode.writeOnly);
      handle.writeStringSync(jsonEncode(manifest.toJson()));
      handle.flushSync();
      handle.closeSync();
      handle = null;
      temporary.renameSync(file.path);
    } finally {
      handle?.closeSync();
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  File _handoffManifestFile(TerminalRecordingFinalizeJob job) {
    return File('${job.handoffPath}.manifest.json');
  }

  Future<_RecordingHandoffManifest> _readHandoffManifest(File file) async {
    final manifestPath = file.path;
    return Isolate.run(() async {
      final manifestFile = File(manifestPath);
      if (await manifestFile.length() > _maximumRecordingHandoffManifestBytes) {
        throw const FormatException('Recording handoff manifest is too large.');
      }
      return _RecordingHandoffManifest.fromJson(
        jsonDecode(await manifestFile.readAsString()),
      );
    });
  }

  Future<_RecordingHandoffManifest>
  _normalizeCurrentHandoffManifestDestination({
    required _RecordingHandoffManifest manifest,
    required File manifestFile,
    required Directory libraryRoot,
  }) async {
    final canonicalDestination = await _validateNativeRecordingDestination(
      value: manifest.destinationPath,
      libraryRoot: libraryRoot,
      jobId: manifest.job.jobId,
    );
    if (canonicalDestination == manifest.destinationPath) {
      return manifest;
    }
    final normalized = _RecordingHandoffManifest(
      job: manifest.job,
      destinationPath: canonicalDestination,
      semanticEvents: manifest.semanticEvents,
      createdAtUtc: manifest.createdAtUtc,
      ownerPid: manifest.ownerPid,
      phase: manifest.phase,
      destinationReservationNonce: manifest.destinationReservationNonce,
      displayName: manifest.displayName,
      nativeSettlementDiagnostic: manifest.nativeSettlementDiagnostic,
    );
    final path = manifestFile.path;
    final encoded = jsonEncode(normalized.toJson());
    await Isolate.run(() => writeStringAtomically(File(path), encoded));
    return normalized;
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
    final file = _handoffLeaseFile(job);
    final claimPath = await _canonicalHandoffClaimKey(job);
    final held = _handoffLeases[job.jobId];
    if (held != null) {
      return held.claimKey == claimPath ? held : null;
    }
    final processOwner = _processHandoffClaimOwners[claimPath];
    if (processOwner != null && !identical(processOwner, _handoffClaimOwner)) {
      return null;
    }
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
    final lease = _RecordingHandoffLease(handle: handle, claimKey: claimPath);
    _handoffLeases[job.jobId] = lease;
    _processHandoffClaimOwners[claimPath] = _handoffClaimOwner;
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
    if (identical(
      _processHandoffClaimOwners[lease.claimKey],
      _handoffClaimOwner,
    )) {
      _processHandoffClaimOwners.remove(lease.claimKey);
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
      failure: LocalSessionRecordingFinalizeFailure.claimedByAnotherProcess,
      jobId: job.jobId,
      message: 'Recording finalize is already claimed by another live process.',
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
    final directory = _canonicalHandoffDirectorySync(
      handoffDirectory,
      jobId: job.jobId,
    );
    final directoryName = _pathBasename(directory.path);
    final expectedHandoffName =
        '$_recordingHandoffFilePrefix${job.jobId}.ndjson';
    final expectedErrorName = '$expectedHandoffName.error.json';
    final expectedHandoffPath = File(
      '${directory.path}${Platform.pathSeparator}$expectedHandoffName',
    ).absolute.path;
    final expectedErrorPath = File(
      '${directory.path}${Platform.pathSeparator}$expectedErrorName',
    ).absolute.path;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(job.jobId) ||
        !directoryName.startsWith(_recordingHandoffDirectoryPrefix) ||
        job.handoffPath != expectedHandoffPath ||
        job.errorPath != expectedErrorPath) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: job.jobId,
        message:
            'Native recording finalize paths escaped their private directory.',
      );
    }
  }

  Future<Directory> _canonicalHandoffDirectory(
    Directory directory, {
    required String jobId,
  }) async {
    try {
      final canonical = Directory(await directory.resolveSymbolicLinks());
      if (await FileSystemEntity.type(canonical.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          !_pathBasename(
            canonical.path,
          ).startsWith(_recordingHandoffDirectoryPrefix)) {
        throw const FileSystemException(
          'Handoff directory identity is invalid.',
        );
      }
      return canonical.absolute;
    } on Object catch (error) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: jobId,
        message:
            'Recording handoff directory could not be canonicalized: '
            '$error',
      );
    }
  }

  Directory _canonicalHandoffDirectorySync(
    Directory directory, {
    required String jobId,
  }) {
    try {
      final canonical = Directory(directory.resolveSymbolicLinksSync());
      if (FileSystemEntity.typeSync(canonical.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          !_pathBasename(
            canonical.path,
          ).startsWith(_recordingHandoffDirectoryPrefix)) {
        throw const FileSystemException(
          'Handoff directory identity is invalid.',
        );
      }
      return canonical.absolute;
    } on Object catch (error) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: jobId,
        message:
            'Recording handoff directory could not be canonicalized: '
            '$error',
      );
    }
  }

  Future<String> _canonicalHandoffClaimKey(
    TerminalRecordingFinalizeJob job,
  ) async {
    final directory = await _canonicalHandoffDirectory(
      File(job.handoffPath).parent,
      jobId: job.jobId,
    );
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '${_pathBasename(_handoffLeaseFile(job).path)}',
    ).absolute.path;
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
      final candidatePath = await _validateNativeRecordingDestination(
        value: candidate.absolute.path,
        libraryRoot: rootDirectory,
        jobId: 'unallocated',
      );
      if (!_reservedPaths.contains(candidatePath)) {
        final nonce = _newHandoffJobId();
        _RecordingDestinationReservation? reservation;
        try {
          reservation = await _acquireDestinationReservation(
            destinationPath: candidatePath,
            sessionId: runtimeSessionId,
            expectedNonce: nonce,
            initializeReservation: true,
            requireDestinationAbsent: true,
          );
        } on LocalSessionRecordingDestinationBusyException catch (error) {
          if (error.path ==
              _destinationReservationRegistryFile(candidatePath).path) {
            rethrow;
          }
          reservation = null;
        }
        if (reservation != null) {
          _reservedPaths.add(candidatePath);
          return LocalSessionRecordingDestination(
            File(candidatePath),
            reservationNonce: reservation.nonce,
          );
        }
      }
      suffix += 1;
    }
  }

  Future<String> save(
    LocalSessionRecordingDestination destination,
    TerminalRecording recording, {
    String? displayName,
  }) async {
    _requireCurrentRecording(recording, path: destination.file.path);
    final path = destination.file.absolute.path;
    final reservation = _destinationReservations[path];
    if (reservation == null ||
        reservation.nonce != destination.reservationNonce) {
      throw StateError(
        'Recording destination is not owned by this repository.',
      );
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Recording destination already exists and will not be overwritten.',
        path,
      );
    }
    final encoder = _encoder;
    if (encoder == null) {
      await _fileWriter(path, recording);
    } else {
      // Explicit test/custom seams retain their string contract. Production
      // defaults keep encode and atomic file IO together in the worker isolate.
      final contents = await encoder(recording);
      await writeStringAtomically(destination.file, contents);
    }
    final released = _releaseDestinationReservation(
      path,
      expectedNonce: destination.reservationNonce,
    );
    if (released) {
      _reservedPaths.remove(path);
    }
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

  bool release(LocalSessionRecordingDestination destination) {
    final path = destination.file.absolute.path;
    final released = _releaseDestinationReservation(
      path,
      expectedNonce: destination.reservationNonce,
    );
    if (released) {
      _reservedPaths.remove(path);
    }
    return released;
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
      final recording = await decoder(await file.readAsString());
      _requireCurrentRecording(recording, path: file.path);
      return recording;
    }
    final recording = await _fileReader(file.absolute.path);
    _requireCurrentRecording(recording, path: file.path);
    return recording;
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
    await _collectOrphanDestinationSidecars(root);
    final loadedIndex = await _loadLibraryIndex(root);
    final index = loadedIndex.index;
    var indexChanged = loadedIndex.needsWrite;
    final entries = <LocalSessionRecordingEntry>[];
    final discoveredPaths = <String>{};
    var reachedLimit = false;
    await for (final entity in root.list(followLinks: false)) {
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
      if (metadata != null) {
        if (metadata.error != null) {
          // Error entries are never authoritative schema evidence. Repeating
          // the bounded head/tail scan prevents a matching stat tuple from
          // hiding a parseable non-current recording behind a cached error.
          metadata = null;
        } else {
          final schemaVersion = metadata.recordingSchemaVersion;
          if (schemaVersion is int &&
              schemaVersion != terminalRecordingSchemaVersion) {
            throw LocalSessionRecordingUnsupportedSchemaException(
              path: path,
              schemaVersion: schemaVersion,
            );
          }
          if (schemaVersion == null) {
            metadata = null;
          }
        }
      }
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

  Future<bool> moveRecordingToTrash(
    String recordingPath,
    Future<bool> Function(String path) mover,
  ) async {
    final root = await _recordingRoot();
    final path = await _validateNativeRecordingDestination(
      value: recordingPath,
      libraryRoot: root,
      jobId: 'trash',
    );
    final reservation = await _acquirePersistedDestinationReservation(path);
    if (reservation == null) {
      throw LocalSessionRecordingDestinationBusyException(path);
    }
    try {
      await _rejectUnsupportedDestinationMetadataForOperation(
        destinationPath: path,
        nonce: reservation.nonce,
      );
      return await mover(path);
    } finally {
      _releaseOwnedDestinationReservation(reservation);
    }
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
      await _cleanupDestinationSidecars(path);
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
    final resolvedSupportDirectory = await directoryResolver();
    final supportDirectory =
        await FileSystemEntity.type(
              resolvedSupportDirectory.absolute.path,
              followLinks: false,
            ) ==
            FileSystemEntityType.directory
        ? Directory(await resolvedSupportDirectory.resolveSymbolicLinks())
        : resolvedSupportDirectory.absolute;
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
    } on LocalSessionRecordingUnsupportedSchemaException {
      rethrow;
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
    if (schemaVersion is int &&
        schemaVersion != terminalRecordingSchemaVersion) {
      throw LocalSessionRecordingUnsupportedSchemaException(
        path: file.path,
        schemaVersion: schemaVersion,
      );
    }
    if (schemaVersion is! int ||
        schemaVersion != terminalRecordingSchemaVersion ||
        sessionId is! String ||
        sessionId.trim().isEmpty ||
        createdAtUtc == null ||
        !createdAtUtc.isUtc ||
        inputPolicy == null) {
      throw const FormatException('Recording metadata is invalid.');
    }
    return TerminalRecordingMetadata(
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
      if (schemaVersion != _recordingLibraryIndexSchemaVersion) {
        throw UnsupportedError(
          'Recording library index schema is unsupported.',
        );
      }
      final names = <String, String>{};
      final rawNames = decoded['names'];
      var needsWrite = false;
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
      return _RecordingLibraryIndexLoad(
        _RecordingLibraryIndex(names: names, entries: metadata),
        needsWrite: needsWrite,
      );
    } on UnsupportedError {
      rethrow;
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
    if (finalized.schemaVersion != terminalRecordingSchemaVersion) {
      throw LocalSessionRecordingUnsupportedSchemaException(
        path: file.path,
        schemaVersion: finalized.schemaVersion,
      );
    }
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
    _requireCurrentRecording(recording, path: 'in-memory recording');
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

  void _requireCurrentRecording(
    TerminalRecording recording, {
    required String path,
  }) {
    if (recording.metadata.schemaVersion != terminalRecordingSchemaVersion ||
        recording.events.any(
          (event) => event.schemaVersion != terminalRecordingSchemaVersion,
        )) {
      throw LocalSessionRecordingUnsupportedSchemaException(
        path: path,
        schemaVersion: recording.metadata.schemaVersion,
      );
    }
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

  Future<String> _validateNativeRecordingDestination({
    required String value,
    required Directory libraryRoot,
    required String jobId,
  }) async {
    try {
      final rawValue = value.trim();
      final rawFile = File(rawValue);
      final basename = _pathBasename(rawFile.path);
      final components = rawFile.path.split(RegExp(r'[/\\]+'));
      if (rawValue != value ||
          rawFile.absolute.path != rawValue ||
          basename == '.' ||
          basename == '..' ||
          !basename.endsWith('.ndjson') ||
          utf8.encode(basename).length > 255 ||
          components.contains('.') ||
          components.contains('..')) {
        throw const FileSystemException(
          'Destination spelling or basename is invalid.',
        );
      }

      final rawRootType = await FileSystemEntity.type(
        libraryRoot.absolute.path,
        followLinks: false,
      );
      final rawParentType = await FileSystemEntity.type(
        rawFile.parent.path,
        followLinks: false,
      );
      if (rawRootType != FileSystemEntityType.directory ||
          rawParentType != FileSystemEntityType.directory) {
        throw const FileSystemException(
          'Destination parent must be the recording library directory.',
        );
      }

      final canonicalRoot = Directory(
        await libraryRoot.resolveSymbolicLinks(),
      ).absolute;
      final canonicalParent = Directory(
        await rawFile.parent.resolveSymbolicLinks(),
      ).absolute;
      if (canonicalRoot.path != canonicalParent.path) {
        throw const FileSystemException(
          'Destination parent escaped the recording library.',
        );
      }

      final leafType = await FileSystemEntity.type(
        rawFile.path,
        followLinks: false,
      );
      if (leafType != FileSystemEntityType.notFound &&
          leafType != FileSystemEntityType.file) {
        throw const FileSystemException(
          'Destination must be absent or an existing regular file.',
        );
      }
      return File(
        '${canonicalRoot.path}${Platform.pathSeparator}$basename',
      ).absolute.path;
    } on Object catch (error) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: jobId,
        message:
            'Recording destination is outside its canonical library: '
            '$error',
      );
    }
  }

  File _destinationReservationFile(String destinationPath) {
    return File('$destinationPath.ianvs-reservation.lock');
  }

  File _destinationReservationRegistryFile(String destinationPath) {
    return File(
      '${File(destinationPath).parent.path}${Platform.pathSeparator}'
      '.ianvs-destination-reservations.lock',
    );
  }

  Directory _destinationSidecarIndexRoot(String destinationPath) {
    return Directory(
      '${File(destinationPath).parent.path}${Platform.pathSeparator}'
      '.ianvs-destination-sidecars',
    );
  }

  File _destinationSidecarGcLockFile(Directory indexRoot) =>
      File('${indexRoot.path}${Platform.pathSeparator}.gc.lock');

  File _destinationSidecarReferenceFile(String destinationPath, String nonce) {
    return File(
      '${_destinationSidecarIndexRoot(destinationPath).path}'
      '${Platform.pathSeparator}buckets'
      '${Platform.pathSeparator}${nonce.substring(0, 2)}'
      '${Platform.pathSeparator}$nonce.json',
    );
  }

  Future<File> _ensureDestinationSidecarReference({
    required String destinationPath,
    required String sessionId,
    required String nonce,
  }) async {
    final reference = _destinationSidecarReferenceFile(destinationPath, nonce);
    final referenceType = await FileSystemEntity.type(
      reference.path,
      followLinks: false,
    );
    if (referenceType == FileSystemEntityType.file) {
      try {
        await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
          reference,
        );
        final decoded = jsonDecode(await reference.readAsString());
        _rejectUnsupportedDestinationSidecarSchema(
          decoded,
          path: reference.path,
        );
        if (decoded is Map &&
            decoded['schemaVersion'] ==
                _destinationSidecarMetadataSchemaVersion &&
            decoded['destinationPath'] == destinationPath &&
            decoded['sessionId'] == sessionId &&
            decoded['nonce'] == nonce) {
          return reference;
        }
      } on LocalSessionRecordingUnsupportedSidecarSchemaException {
        rethrow;
      } on FormatException {
        // Refuse to overwrite an untrusted pre-existing reference below.
      }
      throw FileSystemException(
        'Destination sidecar reference belongs to another recording.',
        reference.path,
      );
    }
    if (referenceType != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Destination sidecar reference is not a regular file.',
        reference.path,
      );
    }
    await _ensureDestinationGcLockForWrite(
      _destinationSidecarIndexRoot(destinationPath),
    );
    var bucketEntries = 0;
    if (await reference.parent.exists()) {
      await for (final entity in reference.parent.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.json')) {
          bucketEntries += 1;
          if (bucketEntries >= _maximumOrphanDestinationSidecarsPerPass) {
            throw LocalSessionRecordingDestinationBusyException(
              reference.parent.path,
            );
          }
        }
      }
    }
    await writeStringAtomically(
      reference,
      jsonEncode(<String, Object?>{
        'schemaVersion': _destinationSidecarMetadataSchemaVersion,
        'destinationPath': destinationPath,
        'sessionId': sessionId,
        'nonce': nonce,
        'createdAtUtc': _now().toUtc().toIso8601String(),
      }),
    );
    return reference;
  }

  Future<void> _ensureDestinationGcLockForWrite(Directory indexRoot) async {
    await indexRoot.create(recursive: true);
    final lockFile = _destinationSidecarGcLockFile(indexRoot);
    final type = await FileSystemEntity.type(lockFile.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound)) {
      throw FileSystemException(
        'Recording sidecar GC lock must be a regular file.',
        lockFile.path,
      );
    }
    final handle = await lockFile.open(mode: FileMode.append);
    await handle.close();
  }

  File _destinationCompletionMarkerFile(String destinationPath) {
    return File('$destinationPath.ianvs-completed.json');
  }

  Future<(int, String)> _recordingDestinationContentIdentity(
    String destinationPath,
  ) {
    return _destinationIdentityReader(destinationPath);
  }

  Future<void> _writeDestinationCompletionMarker({
    required _RecordingHandoffManifest manifest,
    required String destinationPath,
    required (int, String) expectedIdentity,
  }) async {
    final nonce = manifest.destinationReservationNonce;
    final marker = _destinationCompletionMarkerFile(destinationPath);
    if (await FileSystemEntity.type(marker.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: manifest.job.jobId,
        message: 'Recording completion marker must not be a symbolic link.',
      );
    }
    await _rejectUnsupportedDestinationMarkerSchemaIfPresent(marker);
    final currentIdentity = await _recordingDestinationContentIdentity(
      destinationPath,
    );
    if (currentIdentity != expectedIdentity) {
      throw LocalSessionRecordingFinalizeException(
        failure: LocalSessionRecordingFinalizeFailure.invalidHandoff,
        jobId: manifest.job.jobId,
        message:
            'Recording destination content does not match its retained '
            'handoff.',
      );
    }
    final (byteLength, sha256) = expectedIdentity;
    await writeStringAtomically(
      marker,
      jsonEncode(<String, Object?>{
        'schemaVersion': _destinationSidecarMetadataSchemaVersion,
        'jobId': manifest.job.jobId,
        'sessionId': manifest.job.sessionId,
        'destinationPath': destinationPath,
        'destinationReservationNonce': nonce,
        'byteLength': byteLength,
        'sha256': sha256,
      }),
    );
  }

  Future<bool> _hasMatchingDestinationCompletion({
    required _RecordingHandoffManifest manifest,
    required String destinationPath,
  }) async {
    final nonce = manifest.destinationReservationNonce;
    final marker = _destinationCompletionMarkerFile(destinationPath);
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(marker);
    try {
      final decoded = jsonDecode(await marker.readAsString());
      _rejectUnsupportedDestinationSidecarSchema(decoded, path: marker.path);
      if (decoded is! Map ||
          decoded['schemaVersion'] !=
              _destinationSidecarMetadataSchemaVersion ||
          decoded['jobId'] != manifest.job.jobId ||
          decoded['sessionId'] != manifest.job.sessionId ||
          decoded['destinationPath'] != destinationPath ||
          decoded['destinationReservationNonce'] != nonce ||
          decoded['byteLength'] is! int ||
          decoded['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(decoded['sha256'] as String)) {
        return false;
      }
      final (byteLength, sha256) = await _recordingDestinationContentIdentity(
        destinationPath,
      );
      return decoded['byteLength'] == byteLength && decoded['sha256'] == sha256;
    } on LocalSessionRecordingUnsupportedSidecarSchemaException {
      rethrow;
    } on Object {
      return false;
    }
  }

  Future<void> _rejectUnsupportedDestinationMarkerSchemaIfPresent(
    File marker,
  ) => _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(marker);

  Future<void> _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
    File file,
  ) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Recording destination sidecar must not be a symbolic link.',
        file.path,
      );
    }
    if (type != FileSystemEntityType.file) {
      return;
    }
    if (await file.length() > _maximumRecordingDestinationMarkerBytes) {
      throw LocalSessionRecordingUnsupportedSidecarSchemaException(
        path: file.path,
        schemaVersion: 'unrecognized-oversized',
      );
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      _rejectUnsupportedDestinationSidecarSchema(decoded, path: file.path);
    } on LocalSessionRecordingUnsupportedSidecarSchemaException {
      rethrow;
    } on FormatException {
      // A current write interrupted before atomic replacement is recoverable.
    }
  }

  Future<void> _rejectUnsupportedDestinationMetadataForOperation({
    required String destinationPath,
    required String nonce,
  }) async {
    final heldReservation = _destinationReservations[destinationPath];
    if (heldReservation != null && heldReservation.nonce == nonce) {
      _rejectUnsupportedHeldDestinationClaimSchema(heldReservation);
    } else {
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
        _destinationReservationFile(destinationPath),
      );
    }
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
      _destinationCompletionMarkerFile(destinationPath),
    );
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
      _destinationSidecarReferenceFile(destinationPath, nonce),
    );
  }

  void _rejectUnsupportedHeldDestinationClaimSchema(
    _RecordingDestinationReservation reservation,
  ) {
    final handle = reservation.handle;
    final length = handle.lengthSync();
    if (length > _maximumRecordingDestinationMarkerBytes) {
      throw LocalSessionRecordingUnsupportedSidecarSchemaException(
        path: _destinationReservationFile(reservation.destinationPath).path,
        schemaVersion: 'unrecognized-oversized',
      );
    }
    if (length <= 0) {
      return;
    }
    handle.setPositionSync(0);
    try {
      try {
        final decoded = jsonDecode(utf8.decode(handle.readSync(length)));
        _rejectUnsupportedDestinationSidecarSchema(
          decoded,
          path: _destinationReservationFile(reservation.destinationPath).path,
        );
      } on FormatException {
        // Match the file preflight contract: a partial current atomic write is
        // recoverable, while a parseable non-current schema is rejected.
      }
    } finally {
      handle.setPositionSync(length);
    }
  }

  Future<_RecordingDestinationReservation?> _acquireDestinationReservation({
    required String destinationPath,
    required String sessionId,
    required String expectedNonce,
    bool initializeReservation = false,
    required bool requireDestinationAbsent,
  }) async {
    final held = _destinationReservations[destinationPath];
    if (held != null) {
      if (held.sessionId == sessionId && held.nonce == expectedNonce) {
        return held;
      }
      return null;
    }
    final claimFile = _destinationReservationFile(destinationPath);
    final claimKey = claimFile.absolute.path;
    if (_processDestinationClaimOwners.containsKey(claimKey)) {
      return null;
    }
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(claimFile);
    // Reserve the process-local identity before the first await. POSIX record
    // locks may otherwise allow two descriptors in one process to appear as
    // the same owner.
    _processDestinationClaimOwners[claimKey] = _destinationClaimOwner;
    final registryFile = _destinationReservationRegistryFile(destinationPath);
    RandomAccessFile? registryHandle;
    var registryLocked = false;
    RandomAccessFile? handle;
    var locked = false;
    try {
      if (await FileSystemEntity.type(registryFile.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
          'Destination reservation registry must not be a symbolic link.',
        );
      }
      registryHandle = await registryFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(registryHandle)) {
        throw LocalSessionRecordingDestinationBusyException(registryFile.path);
      }
      registryLocked = true;
      if (await FileSystemEntity.type(claimFile.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
          'Destination reservation must not be a symbolic link.',
        );
      }
      handle = await claimFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(handle)) {
        return null;
      }
      locked = true;
      final existingClaimLength = handle.lengthSync();
      if (existingClaimLength > _maximumRecordingDestinationMarkerBytes) {
        throw LocalSessionRecordingUnsupportedSidecarSchemaException(
          path: claimFile.path,
          schemaVersion: 'unrecognized-oversized',
        );
      }
      if (existingClaimLength > 0 &&
          existingClaimLength <= _maximumRecordingDestinationMarkerBytes) {
        try {
          handle.setPositionSync(0);
          final decoded = jsonDecode(
            utf8.decode(handle.readSync(existingClaimLength)),
          );
          _rejectUnsupportedDestinationSidecarSchema(
            decoded,
            path: claimFile.path,
          );
        } on LocalSessionRecordingUnsupportedSidecarSchemaException {
          rethrow;
        } on FormatException {
          // A current claim write interrupted before flush may be replaced
          // only while this process owns both protocol locks.
        }
      }
      final destinationType = await FileSystemEntity.type(
        destinationPath,
        followLinks: false,
      );
      if (requireDestinationAbsent &&
          destinationType != FileSystemEntityType.notFound) {
        return null;
      }

      final nonce = expectedNonce;
      if (!initializeReservation) {
        final length = handle.lengthSync();
        if (length <= 0 || length > _maximumRecordingDestinationMarkerBytes) {
          return null;
        }
        handle.setPositionSync(0);
        final decoded = jsonDecode(utf8.decode(handle.readSync(length)));
        _rejectUnsupportedDestinationSidecarSchema(
          decoded,
          path: claimFile.path,
        );
        if (decoded is! Map ||
            decoded['schemaVersion'] !=
                _destinationSidecarMetadataSchemaVersion ||
            decoded['destinationPath'] != destinationPath ||
            decoded['sessionId'] != sessionId ||
            decoded['nonce'] != nonce) {
          return null;
        }
      }
      if (initializeReservation) {
        final reference = await _ensureDestinationSidecarReference(
          destinationPath: destinationPath,
          sessionId: sessionId,
          nonce: nonce,
        );
        handle
          ..truncateSync(0)
          ..setPositionSync(0)
          ..writeStringSync(
            jsonEncode(<String, Object?>{
              'schemaVersion': _destinationSidecarMetadataSchemaVersion,
              'destinationPath': destinationPath,
              'sessionId': sessionId,
              'nonce': nonce,
              'sidecarReferencePath': reference.path,
              'ownerPid': pid,
            }),
          )
          ..flushSync();
      }
      final reservation = _RecordingDestinationReservation(
        destinationPath: destinationPath,
        sessionId: sessionId,
        nonce: nonce,
        claimKey: claimKey,
        handle: handle,
      );
      _destinationReservations[destinationPath] = reservation;
      return reservation;
    } on LocalSessionRecordingUnsupportedSidecarSchemaException {
      rethrow;
    } on FormatException {
      return null;
    } finally {
      if (!_destinationReservations.containsKey(destinationPath)) {
        if (locked) {
          try {
            handle?.unlockSync();
          } on FileSystemException {
            // The claim is being rejected and cannot be reused here.
          }
        }
        try {
          handle?.closeSync();
        } on FileSystemException {
          // The process-local owner is still cleared below.
        }
        if (identical(
          _processDestinationClaimOwners[claimKey],
          _destinationClaimOwner,
        )) {
          _processDestinationClaimOwners.remove(claimKey);
        }
      }
      if (registryLocked) {
        try {
          registryHandle?.unlockSync();
        } on FileSystemException {
          // Closing the registry descriptor below still releases the lock.
        }
      }
      try {
        registryHandle?.closeSync();
      } on FileSystemException {
        // The short-lived directory protocol lock is not reused.
      }
    }
  }

  Future<bool> _tryLockDestinationProtocol(RandomAccessFile handle) async {
    for (var attempt = 0; attempt < destinationLockRetryLimit; attempt += 1) {
      try {
        await handle.lock(FileLock.exclusive);
        return true;
      } on FileSystemException {
        if (attempt + 1 >= destinationLockRetryLimit) {
          return false;
        }
        await _delay(destinationLockRetryDelay);
      }
    }
    return false;
  }

  Future<_RecordingDestinationReservation?>
  _acquirePersistedDestinationReservation(String destinationPath) async {
    final claimFile = _destinationReservationFile(destinationPath);
    final claimKey = claimFile.absolute.path;
    if (_destinationReservations.containsKey(destinationPath) ||
        _processDestinationClaimOwners.containsKey(claimKey)) {
      throw LocalSessionRecordingDestinationBusyException(destinationPath);
    }
    String? sessionId;
    String? nonce;
    final claimType = await FileSystemEntity.type(
      claimFile.path,
      followLinks: false,
    );
    if (claimType == FileSystemEntityType.file) {
      try {
        await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
          claimFile,
        );
        if (await claimFile.length() <=
            _maximumRecordingDestinationMarkerBytes) {
          final decoded = jsonDecode(await claimFile.readAsString());
          _rejectUnsupportedDestinationSidecarSchema(
            decoded,
            path: claimFile.path,
          );
          if (decoded is Map &&
              decoded['schemaVersion'] ==
                  _destinationSidecarMetadataSchemaVersion &&
              decoded['destinationPath'] == destinationPath &&
              decoded['sessionId'] is String &&
              decoded['nonce'] is String) {
            sessionId = decoded['sessionId'] as String;
            nonce = decoded['nonce'] as String;
          }
        }
      } on LocalSessionRecordingUnsupportedSidecarSchemaException {
        rethrow;
      } on FormatException {
        // Refuse mutation when the existing owner cannot be proven.
      }
      if (sessionId == null || nonce == null) {
        throw LocalSessionRecordingDestinationBusyException(destinationPath);
      }
    } else if (claimType != FileSystemEntityType.notFound) {
      throw LocalSessionRecordingDestinationBusyException(destinationPath);
    }
    if (sessionId == null || nonce == null) {
      final file = File(destinationPath);
      final stat = await file.stat();
      final metadata = await _readRecordingMetadataLine(file, stat.size);
      sessionId = metadata.sessionId;
      nonce = _newHandoffJobId();
      final acquired = await _acquireDestinationReservation(
        destinationPath: destinationPath,
        sessionId: sessionId,
        expectedNonce: nonce,
        initializeReservation: true,
        requireDestinationAbsent: false,
      );
      return _rejectPendingDestinationReservation(acquired);
    }
    final acquired = await _acquireDestinationReservation(
      destinationPath: destinationPath,
      sessionId: sessionId,
      expectedNonce: nonce,
      requireDestinationAbsent: false,
    );
    return _rejectPendingDestinationReservation(acquired);
  }

  Future<_RecordingDestinationReservation?>
  _rejectPendingDestinationReservation(
    _RecordingDestinationReservation? reservation,
  ) async {
    if (reservation == null) {
      return null;
    }
    try {
      final handle = reservation.handle;
      final length = handle.lengthSync();
      if (length > _maximumRecordingDestinationMarkerBytes) {
        throw LocalSessionRecordingUnsupportedSidecarSchemaException(
          path: _destinationReservationFile(reservation.destinationPath).path,
          schemaVersion: 'unrecognized-oversized',
        );
      }
      if (length <= 0) {
        throw LocalSessionRecordingDestinationBusyException(
          reservation.destinationPath,
        );
      }
      handle.setPositionSync(0);
      final decoded = jsonDecode(utf8.decode(handle.readSync(length)));
      _rejectUnsupportedDestinationSidecarSchema(
        decoded,
        path: _destinationReservationFile(reservation.destinationPath).path,
      );
      if (decoded is! Map ||
          decoded['schemaVersion'] !=
              _destinationSidecarMetadataSchemaVersion ||
          decoded['destinationPath'] != reservation.destinationPath ||
          decoded['sessionId'] != reservation.sessionId ||
          decoded['nonce'] != reservation.nonce) {
        throw LocalSessionRecordingDestinationBusyException(
          reservation.destinationPath,
        );
      }
      if (decoded['jobId'] != null) {
        final manifestPath = decoded['manifestPath'];
        if (manifestPath is! String ||
            await FileSystemEntity.type(manifestPath, followLinks: false) ==
                FileSystemEntityType.file) {
          throw LocalSessionRecordingDestinationBusyException(
            reservation.destinationPath,
          );
        }
      }
      return reservation;
    } on Object {
      _releaseOwnedDestinationReservation(reservation);
      rethrow;
    }
  }

  bool _releaseDestinationReservation(
    String destinationPath, {
    required String expectedNonce,
  }) {
    final reservation = _destinationReservations[destinationPath];
    if (reservation == null || reservation.nonce != expectedNonce) {
      return false;
    }
    return _releaseOwnedDestinationReservation(reservation);
  }

  bool _releaseOwnedDestinationReservation(
    _RecordingDestinationReservation reservation,
  ) {
    if (!identical(
      _destinationReservations[reservation.destinationPath],
      reservation,
    )) {
      return false;
    }
    _destinationReservations.remove(reservation.destinationPath);
    try {
      reservation.handle.unlockSync();
    } on FileSystemException {
      // Closing the descriptor below still releases the OS lock.
    }
    try {
      reservation.handle.closeSync();
    } on FileSystemException {
      // The process-local owner must still be released.
    }
    if (identical(
      _processDestinationClaimOwners[reservation.claimKey],
      _destinationClaimOwner,
    )) {
      _processDestinationClaimOwners.remove(reservation.claimKey);
    }
    return true;
  }

  void _bindDestinationReservationToJob(
    _RecordingDestinationReservation reservation,
    TerminalRecordingFinalizeJob job,
  ) {
    final handle = reservation.handle;
    final length = handle.lengthSync();
    if (length > _maximumRecordingDestinationMarkerBytes) {
      throw LocalSessionRecordingUnsupportedSidecarSchemaException(
        path: _destinationReservationFile(reservation.destinationPath).path,
        schemaVersion: 'unrecognized-oversized',
      );
    }
    if (length <= 0) {
      throw const FormatException(
        'Destination reservation metadata is invalid.',
      );
    }
    handle.setPositionSync(0);
    final decoded = jsonDecode(utf8.decode(handle.readSync(length)));
    _rejectUnsupportedDestinationSidecarSchema(
      decoded,
      path: _destinationReservationFile(reservation.destinationPath).path,
    );
    if (decoded is! Map ||
        decoded['schemaVersion'] != _destinationSidecarMetadataSchemaVersion ||
        decoded['destinationPath'] != reservation.destinationPath ||
        decoded['sessionId'] != reservation.sessionId ||
        decoded['nonce'] != reservation.nonce ||
        (decoded['jobId'] != null && decoded['jobId'] != job.jobId)) {
      throw const FormatException(
        'Destination reservation belongs to another recording job.',
      );
    }
    handle
      ..truncateSync(0)
      ..setPositionSync(0)
      ..writeStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': _destinationSidecarMetadataSchemaVersion,
          'destinationPath': reservation.destinationPath,
          'sessionId': reservation.sessionId,
          'nonce': reservation.nonce,
          'jobId': job.jobId,
          'manifestPath': _handoffManifestFile(job).path,
          'sidecarReferencePath': decoded['sidecarReferencePath'],
          'ownerPid': pid,
        }),
      )
      ..flushSync();
  }

  void _validateBoundDestinationReservation(
    _RecordingDestinationReservation reservation,
    TerminalRecordingFinalizeJob job,
  ) {
    final handle = reservation.handle;
    final length = handle.lengthSync();
    if (length <= 0 || length > _maximumRecordingDestinationMarkerBytes) {
      throw const FormatException(
        'Destination reservation metadata is invalid.',
      );
    }
    handle.setPositionSync(0);
    final decoded = jsonDecode(utf8.decode(handle.readSync(length)));
    _rejectUnsupportedDestinationSidecarSchema(
      decoded,
      path: _destinationReservationFile(reservation.destinationPath).path,
    );
    if (decoded is! Map ||
        decoded['destinationPath'] != reservation.destinationPath ||
        decoded['sessionId'] != reservation.sessionId ||
        decoded['nonce'] != reservation.nonce ||
        decoded['jobId'] != job.jobId ||
        decoded['manifestPath'] != _handoffManifestFile(job).path) {
      throw const FormatException(
        'Destination reservation belongs to another recording job.',
      );
    }
  }

  Future<void> _cleanupDestinationSidecars(String destinationPath) async {
    if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return;
    }
    final claimFile = _destinationReservationFile(destinationPath);
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(claimFile);
    final claimKey = claimFile.absolute.path;
    if (_processDestinationClaimOwners.containsKey(claimKey)) {
      throw FileSystemException(
        'Recording destination is still claimed by a live owner.',
        destinationPath,
      );
    }
    _processDestinationClaimOwners[claimKey] = _destinationClaimOwner;
    final registryFile = _destinationReservationRegistryFile(destinationPath);
    RandomAccessFile? registryHandle;
    RandomAccessFile? claimHandle;
    var registryLocked = false;
    var claimLocked = false;
    try {
      if (await FileSystemEntity.type(registryFile.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'Destination reservation registry must not be a symbolic link.',
          registryFile.path,
        );
      }
      registryHandle = await registryFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(registryHandle)) {
        throw LocalSessionRecordingDestinationBusyException(registryFile.path);
      }
      registryLocked = true;
      final claimType = await FileSystemEntity.type(
        claimFile.path,
        followLinks: false,
      );
      if (claimType == FileSystemEntityType.notFound) {
        return;
      }
      if (claimType != FileSystemEntityType.file) {
        throw FileSystemException(
          'Destination reservation is not a regular file.',
          claimFile.path,
        );
      }
      claimHandle = await claimFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(claimHandle)) {
        throw LocalSessionRecordingDestinationBusyException(destinationPath);
      }
      claimLocked = true;
      await _destinationCleanupBarrier?.call(destinationPath);
      if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return;
      }
      final claimLength = claimHandle.lengthSync();
      if (claimLength <= 0 ||
          claimLength > _maximumRecordingDestinationMarkerBytes) {
        throw FileSystemException(
          'Destination reservation metadata is invalid.',
          claimFile.path,
        );
      }
      claimHandle.setPositionSync(0);
      final decodedClaim = jsonDecode(
        utf8.decode(claimHandle.readSync(claimLength)),
      );
      _rejectUnsupportedDestinationSidecarSchema(
        decodedClaim,
        path: claimFile.path,
      );
      if (decodedClaim is! Map ||
          decodedClaim['schemaVersion'] !=
              _destinationSidecarMetadataSchemaVersion ||
          decodedClaim['destinationPath'] != destinationPath ||
          decodedClaim['sessionId'] is! String ||
          decodedClaim['nonce'] is! String ||
          !RegExp(
            r'^[0-9a-f]{32}$',
          ).hasMatch(decodedClaim['nonce'] as String)) {
        throw FileSystemException(
          'Destination reservation identity is invalid.',
          claimFile.path,
        );
      }
      final sidecarReferencePath = decodedClaim['sidecarReferencePath'];
      if (sidecarReferencePath != null &&
          sidecarReferencePath !=
              _destinationSidecarReferenceFile(
                destinationPath,
                decodedClaim['nonce'] as String,
              ).path) {
        throw FileSystemException(
          'Destination sidecar reference identity is invalid.',
          claimFile.path,
        );
      }
      if (sidecarReferencePath is String) {
        await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
          File(sidecarReferencePath),
        );
      }
      if (decodedClaim['jobId'] is String) {
        final manifestPath = decodedClaim['manifestPath'];
        if (manifestPath is! String ||
            await FileSystemEntity.type(manifestPath, followLinks: false) ==
                FileSystemEntityType.file) {
          return;
        }
      }
      final marker = _destinationCompletionMarkerFile(destinationPath);
      final markerType = await FileSystemEntity.type(
        marker.path,
        followLinks: false,
      );
      if (markerType == FileSystemEntityType.file) {
        if (await marker.length() > _maximumRecordingDestinationMarkerBytes) {
          throw FileSystemException(
            'Recording completion marker is too large.',
            marker.path,
          );
        }
        final decodedMarker = jsonDecode(await marker.readAsString());
        _rejectUnsupportedDestinationSidecarSchema(
          decodedMarker,
          path: marker.path,
        );
        if (decodedMarker is! Map ||
            decodedMarker['schemaVersion'] !=
                _destinationSidecarMetadataSchemaVersion ||
            decodedClaim['jobId'] is! String ||
            decodedMarker['jobId'] != decodedClaim['jobId'] ||
            decodedMarker['destinationPath'] != destinationPath ||
            decodedMarker['sessionId'] != decodedClaim['sessionId'] ||
            decodedMarker['destinationReservationNonce'] !=
                decodedClaim['nonce']) {
          throw FileSystemException(
            'Recording completion marker belongs to another job.',
            marker.path,
          );
        }
        await marker.delete();
      } else if (markerType != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Recording completion marker is not a regular file.',
          marker.path,
        );
      }
      await claimHandle.unlock();
      claimLocked = false;
      await claimHandle.close();
      claimHandle = null;
      await claimFile.delete();
      if (sidecarReferencePath is String) {
        await _deleteIfPresent(File(sidecarReferencePath));
      }
    } on FormatException catch (error) {
      throw FileSystemException(
        'Recording sidecar metadata is invalid: $error',
        destinationPath,
      );
    } finally {
      if (claimLocked) {
        try {
          await claimHandle?.unlock();
        } on FileSystemException {
          // Closing below releases the per-destination claim.
        }
      }
      try {
        await claimHandle?.close();
      } on FileSystemException {
        // The directory protocol lock still prevents inode replacement.
      }
      if (registryLocked) {
        try {
          await registryHandle?.unlock();
        } on FileSystemException {
          // Closing below releases the registry lock.
        }
      }
      try {
        await registryHandle?.close();
      } on FileSystemException {
        // The registry descriptor is not reused.
      }
      if (identical(
        _processDestinationClaimOwners[claimKey],
        _destinationClaimOwner,
      )) {
        _processDestinationClaimOwners.remove(claimKey);
      }
    }
  }

  Future<void> _collectOrphanDestinationSidecars(Directory root) async {
    _destinationSidecarReferencesInspected = 0;
    final indexRoot = Directory(
      '${root.path}${Platform.pathSeparator}'
      '.ianvs-destination-sidecars',
    );
    if (!await indexRoot.exists()) {
      return;
    }
    final cursorFile = File(
      '${indexRoot.path}${Platform.pathSeparator}cursor.json',
    );
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(cursorFile);
    await _preflightDestinationSidecarGc(
      root: root,
      indexRoot: indexRoot,
      cursorFile: cursorFile,
    );
    await _destinationGcPreLockBarrier?.call(indexRoot);
    await _withDestinationGcLock(indexRoot, () async {
      await _preflightDestinationSidecarGc(
        root: root,
        indexRoot: indexRoot,
        cursorFile: cursorFile,
      );
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(cursorFile);
      var bucket = 0;
      var quarantineSerial = 0;
      if (await FileSystemEntity.type(cursorFile.path, followLinks: false) ==
          FileSystemEntityType.file) {
        try {
          final decoded = jsonDecode(await cursorFile.readAsString());
          _rejectUnsupportedDestinationSidecarSchema(
            decoded,
            path: cursorFile.path,
          );
          if (decoded is! Map ||
              decoded['bucket'] is! int ||
              decoded['quarantineSerial'] is! int) {
            throw const FormatException('Sidecar GC cursor is invalid.');
          }
          bucket = (decoded['bucket'] as int) % _destinationSidecarBucketCount;
          quarantineSerial = decoded['quarantineSerial'] as int;
        } on LocalSessionRecordingUnsupportedSidecarSchemaException {
          rethrow;
        } on FormatException {
          bucket = 0;
          quarantineSerial = 0;
        }
      }
      final bucketDirectory = Directory(
        '${indexRoot.path}${Platform.pathSeparator}buckets'
        '${Platform.pathSeparator}${bucket.toRadixString(16).padLeft(2, '0')}',
      );
      var processed = 0;
      if (await bucketDirectory.exists()) {
        await for (final entity in bucketDirectory.list(followLinks: false)) {
          if (processed >= _maximumOrphanDestinationSidecarsPerPass) {
            throw FileSystemException(
              'Recording sidecar bucket exceeds its bounded capacity.',
              bucketDirectory.path,
            );
          }
          if (entity is! File || !entity.path.endsWith('.json')) {
            continue;
          }
          processed += 1;
          final reference = entity;
          _destinationSidecarReferencesInspected += 1;
          String? destinationPath;
          String? nonce;
          try {
            await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
              reference,
            );
            if (await reference.length() >
                _maximumRecordingDestinationMarkerBytes) {
              throw const FormatException('Sidecar reference is too large.');
            }
            final decoded = jsonDecode(await reference.readAsString());
            _rejectUnsupportedDestinationSidecarSchema(
              decoded,
              path: reference.path,
            );
            if (decoded is! Map ||
                decoded['schemaVersion'] !=
                    _destinationSidecarMetadataSchemaVersion ||
                decoded['destinationPath'] is! String ||
                decoded['sessionId'] is! String ||
                decoded['nonce'] is! String) {
              throw const FormatException('Sidecar reference is invalid.');
            }
            destinationPath = await _validateNativeRecordingDestination(
              value: decoded['destinationPath'] as String,
              libraryRoot: root,
              jobId: 'sidecar-gc',
            );
            nonce = decoded['nonce'] as String;
            if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce) ||
                reference.path !=
                    _destinationSidecarReferenceFile(
                      destinationPath,
                      nonce,
                    ).path) {
              throw const FormatException(
                'Sidecar reference identity is invalid.',
              );
            }
          } on LocalSessionRecordingUnsupportedSidecarSchemaException {
            rethrow;
          } on Object {
            await _quarantineSidecarReference(
              reference: reference,
              indexRoot: indexRoot,
              serial: quarantineSerial,
            );
            quarantineSerial += 1;
            continue;
          }
          final destinationIsAbsent =
              await FileSystemEntity.type(
                destinationPath,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound;
          final claim = _destinationReservationFile(destinationPath);
          var claimMetadataIsWellFormed = false;
          var claimIdentityIsValid = false;
          try {
            if (await FileSystemEntity.type(claim.path, followLinks: false) ==
                FileSystemEntityType.file) {
              await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(
                claim,
              );
            }
            if (await FileSystemEntity.type(claim.path, followLinks: false) ==
                    FileSystemEntityType.file &&
                await claim.length() <=
                    _maximumRecordingDestinationMarkerBytes) {
              final decodedClaim = jsonDecode(await claim.readAsString());
              _rejectUnsupportedDestinationSidecarSchema(
                decodedClaim,
                path: claim.path,
              );
              claimMetadataIsWellFormed =
                  decodedClaim is Map &&
                  decodedClaim['schemaVersion'] ==
                      _destinationSidecarMetadataSchemaVersion &&
                  decodedClaim['destinationPath'] is String &&
                  decodedClaim['sessionId'] is String &&
                  decodedClaim['nonce'] is String &&
                  RegExp(
                    r'^[0-9a-f]{32}$',
                  ).hasMatch(decodedClaim['nonce'] as String);
              claimIdentityIsValid =
                  claimMetadataIsWellFormed &&
                  decodedClaim['destinationPath'] == destinationPath &&
                  decodedClaim['nonce'] == nonce;
            }
          } on LocalSessionRecordingUnsupportedSidecarSchemaException {
            rethrow;
          } on FormatException {
            claimMetadataIsWellFormed = false;
            claimIdentityIsValid = false;
          }
          if (!destinationIsAbsent) {
            continue;
          }
          if (!claimIdentityIsValid) {
            if (claimMetadataIsWellFormed) {
              await _quarantineSidecarReference(
                reference: reference,
                indexRoot: indexRoot,
                serial: quarantineSerial,
              );
              quarantineSerial += 1;
              continue;
            }
            final quarantined = await _quarantineMalformedDestinationSidecars(
              destinationPath: destinationPath,
              reference: reference,
              indexRoot: indexRoot,
              serial: quarantineSerial,
            );
            if (quarantined) {
              quarantineSerial += 1;
            }
            continue;
          }
          try {
            await _cleanupDestinationSidecars(destinationPath);
          } on LocalSessionRecordingDestinationBusyException {
            // A live foreign owner is skipped; the shard cursor revisits it.
          } on FileSystemException {
            // Invalid or foreign identity is retained for explicit diagnosis.
          } on FormatException {
            // Malformed sidecars are never deleted automatically.
          }
        }
      }
      await _expireDestinationSidecarQuarantine(indexRoot);
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(cursorFile);
      await writeStringAtomically(
        cursorFile,
        jsonEncode(<String, Object?>{
          'schemaVersion': _destinationSidecarMetadataSchemaVersion,
          'bucket': (bucket + 1) % _destinationSidecarBucketCount,
          'quarantineSerial': quarantineSerial,
        }),
      );
    });
  }

  Future<void> _preflightDestinationSidecarGc({
    required Directory root,
    required Directory indexRoot,
    required File cursorFile,
  }) async {
    // A rejected schema must leave the directory byte-for-byte unchanged. In
    // particular, perform this bounded pass before opening the persistent GC
    // lock, because FileMode.append would otherwise create `.gc.lock` on a
    // failing operation.
    await _preflightDestinationSidecarQuarantine(indexRoot);
    var bucket = 0;
    if (await FileSystemEntity.type(cursorFile.path, followLinks: false) ==
        FileSystemEntityType.file) {
      try {
        final decoded = jsonDecode(await cursorFile.readAsString());
        _rejectUnsupportedDestinationSidecarSchema(
          decoded,
          path: cursorFile.path,
        );
        if (decoded is Map && decoded['bucket'] is int) {
          bucket = (decoded['bucket'] as int) % _destinationSidecarBucketCount;
        }
      } on LocalSessionRecordingUnsupportedSidecarSchemaException {
        rethrow;
      } on FormatException {
        // A malformed current cursor is reset only after the locked pass.
      }
    }
    final bucketDirectory = Directory(
      '${indexRoot.path}${Platform.pathSeparator}buckets'
      '${Platform.pathSeparator}${bucket.toRadixString(16).padLeft(2, '0')}',
    );
    if (!await bucketDirectory.exists()) {
      return;
    }
    var inspected = 0;
    await for (final entity in bucketDirectory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      inspected += 1;
      if (inspected > _maximumOrphanDestinationSidecarsPerPass) {
        throw FileSystemException(
          'Recording sidecar bucket exceeds its bounded capacity.',
          bucketDirectory.path,
        );
      }
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(entity);
      try {
        final decoded = jsonDecode(await entity.readAsString());
        _rejectUnsupportedDestinationSidecarSchema(decoded, path: entity.path);
        if (decoded is! Map ||
            decoded['destinationPath'] is! String ||
            decoded['nonce'] is! String) {
          continue;
        }
        final destinationPath = await _validateNativeRecordingDestination(
          value: decoded['destinationPath'] as String,
          libraryRoot: root,
          jobId: 'sidecar-gc-preflight',
        );
        await _rejectUnsupportedDestinationMetadataForOperation(
          destinationPath: destinationPath,
          nonce: decoded['nonce'] as String,
        );
      } on LocalSessionRecordingUnsupportedSidecarSchemaException {
        rethrow;
      } on Object {
        // Malformed current references are handled by the locked quarantine
        // pass. Their bounded quarantine targets were preflighted above.
      }
    }
  }

  Future<void> _preflightDestinationSidecarQuarantine(
    Directory indexRoot,
  ) async {
    final quarantine = Directory(
      '${indexRoot.path}${Platform.pathSeparator}quarantine',
    );
    if (!await quarantine.exists()) {
      return;
    }
    var inspected = 0;
    await for (final entity in quarantine.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      inspected += 1;
      if (inspected > _maximumDestinationSidecarQuarantineEntries * 3) {
        break;
      }
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(entity);
    }
  }

  Future<T> _withDestinationGcLock<T>(
    Directory indexRoot,
    Future<T> Function() operation,
  ) async {
    final lockFile = _destinationSidecarGcLockFile(indexRoot);
    if (await FileSystemEntity.type(lockFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Recording sidecar GC lock is missing or not a regular file.',
        lockFile.path,
      );
    }
    final handle = await lockFile.open(mode: FileMode.append);
    var locked = false;
    try {
      if (!await _tryLockDestinationProtocol(handle)) {
        throw LocalSessionRecordingDestinationBusyException(lockFile.path);
      }
      locked = true;
      return await operation();
    } finally {
      if (locked) {
        try {
          await handle.unlock();
        } on FileSystemException {
          // Closing below releases the bounded GC protocol lock.
        }
      }
      await handle.close();
    }
  }

  Future<void> _quarantineSidecarReference({
    required File reference,
    required Directory indexRoot,
    required int serial,
  }) async {
    if (await FileSystemEntity.type(reference.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final quarantine = Directory(
      '${indexRoot.path}${Platform.pathSeparator}quarantine',
    );
    final slot = serial % _maximumDestinationSidecarQuarantineEntries;
    final target = File(
      '${quarantine.path}${Platform.pathSeparator}'
      'slot-${slot.toString().padLeft(2, '0')}.reference.json',
    );
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(reference);
    await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(target);
    await _withDestinationQuarantineLock(indexRoot, () async {
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(reference);
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(target);
      await quarantine.create(recursive: true);
      await _deleteIfPresent(target);
      await reference.rename(target.path);
    });
  }

  Future<T> _withDestinationQuarantineLock<T>(
    Directory indexRoot,
    Future<T> Function() operation,
  ) async {
    final lockFile = File(
      '${indexRoot.path}${Platform.pathSeparator}.quarantine.lock',
    );
    if (await FileSystemEntity.type(lockFile.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'Recording quarantine lock must not be a symbolic link.',
        lockFile.path,
      );
    }
    final handle = await lockFile.open(mode: FileMode.append);
    var locked = false;
    try {
      if (!await _tryLockDestinationProtocol(handle)) {
        throw LocalSessionRecordingDestinationBusyException(lockFile.path);
      }
      locked = true;
      return await operation();
    } finally {
      if (locked) {
        try {
          await handle.unlock();
        } on FileSystemException {
          // Closing below releases the bounded quarantine protocol lock.
        }
      }
      await handle.close();
    }
  }

  Future<bool> _quarantineMalformedDestinationSidecars({
    required String destinationPath,
    required File reference,
    required Directory indexRoot,
    required int serial,
  }) async {
    final claimFile = _destinationReservationFile(destinationPath);
    final marker = _destinationCompletionMarkerFile(destinationPath);
    final slot = serial % _maximumDestinationSidecarQuarantineEntries;
    final quarantine = Directory(
      '${indexRoot.path}${Platform.pathSeparator}quarantine',
    );
    final targets = <File>[
      for (final suffix in <String>[
        'reference.json',
        'claim.lock',
        'marker.json',
      ])
        File(
          '${quarantine.path}${Platform.pathSeparator}'
          'slot-${slot.toString().padLeft(2, '0')}.$suffix',
        ),
    ];
    for (final source in <File>[reference, claimFile, marker]) {
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(source);
    }
    for (final target in targets) {
      await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(target);
    }
    final claimKey = claimFile.absolute.path;
    if (_processDestinationClaimOwners.containsKey(claimKey)) {
      return false;
    }
    _processDestinationClaimOwners[claimKey] = _destinationClaimOwner;
    final registryFile = _destinationReservationRegistryFile(destinationPath);
    RandomAccessFile? registryHandle;
    RandomAccessFile? claimHandle;
    var registryLocked = false;
    var claimLocked = false;
    try {
      registryHandle = await registryFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(registryHandle)) {
        return false;
      }
      registryLocked = true;
      if (await FileSystemEntity.type(claimFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        await _quarantineSidecarReference(
          reference: reference,
          indexRoot: indexRoot,
          serial: serial,
        );
        return true;
      }
      claimHandle = await claimFile.open(mode: FileMode.append);
      if (!await _tryLockDestinationProtocol(claimHandle)) {
        return false;
      }
      claimLocked = true;
      if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
      await _withDestinationQuarantineLock(indexRoot, () async {
        for (final source in <File>[reference, claimFile, marker]) {
          await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(source);
        }
        for (final target in targets) {
          await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(target);
        }
        await claimHandle?.unlock();
        claimLocked = false;
        await claimHandle?.close();
        claimHandle = null;
        await quarantine.create(recursive: true);
        for (final target in targets) {
          await _deleteIfPresent(target);
        }
        await claimFile.rename(
          '${quarantine.path}${Platform.pathSeparator}'
          'slot-${slot.toString().padLeft(2, '0')}.claim.lock',
        );
        if (await FileSystemEntity.type(marker.path, followLinks: false) ==
            FileSystemEntityType.file) {
          await marker.rename(
            '${quarantine.path}${Platform.pathSeparator}'
            'slot-${slot.toString().padLeft(2, '0')}.marker.json',
          );
        }
        await reference.rename(
          '${quarantine.path}${Platform.pathSeparator}'
          'slot-${slot.toString().padLeft(2, '0')}.reference.json',
        );
      });
      return true;
    } finally {
      if (claimLocked) {
        try {
          await claimHandle?.unlock();
        } on FileSystemException {
          // Closing below releases the malformed claim.
        }
      }
      try {
        await claimHandle?.close();
      } on FileSystemException {
        // The registry lock remains until the end of this finally.
      }
      if (registryLocked) {
        try {
          await registryHandle?.unlock();
        } on FileSystemException {
          // Closing below releases the registry lock.
        }
      }
      try {
        await registryHandle?.close();
      } on FileSystemException {
        // The descriptor is not reused.
      }
      if (identical(
        _processDestinationClaimOwners[claimKey],
        _destinationClaimOwner,
      )) {
        _processDestinationClaimOwners.remove(claimKey);
      }
    }
  }

  Future<void> _expireDestinationSidecarQuarantine(Directory indexRoot) async {
    final quarantine = Directory(
      '${indexRoot.path}${Platform.pathSeparator}quarantine',
    );
    if (!await quarantine.exists()) {
      return;
    }
    Future<List<File>> inspectBatch() async {
      final inspected = <File>[];
      await for (final entity in quarantine.list(followLinks: false)) {
        if (inspected.length >=
            _maximumDestinationSidecarQuarantineEntries * 3) {
          break;
        }
        if (entity is File) {
          inspected.add(entity);
        }
      }
      for (final entity in inspected) {
        await _rejectUnsupportedDestinationSidecarSchemaFileIfPresent(entity);
      }
      return inspected;
    }

    // Fail before creating the stable lock if the existing batch is already
    // unsupported, then repeat under the protocol lock to close the race.
    await inspectBatch();
    await _withDestinationQuarantineLock(indexRoot, () async {
      final cutoff = _now().toUtc().subtract(
        _destinationSidecarQuarantineMaximumAge,
      );
      final inspected = await inspectBatch();
      for (final entity in inspected) {
        if ((await entity.stat()).modified.toUtc().isBefore(cutoff)) {
          await entity.delete();
        }
      }
    });
  }

  String _requireLibraryPath(String value, Directory root) {
    final path = File(value.trim()).absolute.path;
    final prefix = '${root.absolute.path}${Platform.pathSeparator}';
    if (path.startsWith(prefix)) {
      return path;
    }
    throw FormatException('Recording path is outside the library: $path');
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

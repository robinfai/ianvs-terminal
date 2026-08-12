import 'package:ianvs_pty/ianvs_pty.dart';

import '../runtime/terminal_session_request_transport.dart';
import 'terminal_recording.dart';

enum TerminalRecordingBackendErrorCode {
  unsupportedBackend,
  alreadyActive,
  notActive,
  capacityExceeded,
  invalidHandoff,
  handoffCollision,
  finalizeCapacityExceeded,
  finalizeWorkerSpawnFailed,
  invalidResponse,
  nativeFailure,
}

final class TerminalRecordingBackendException implements Exception {
  const TerminalRecordingBackendException({
    required this.code,
    required this.sessionId,
    required this.message,
  });

  final TerminalRecordingBackendErrorCode code;
  final String sessionId;
  final String message;

  @override
  String toString() {
    return 'TerminalRecordingBackendException('
        '${code.name}, session $sessionId): $message';
  }
}

final class TerminalRecordingStartResult {
  const TerminalRecordingStartResult({
    required this.maxEvents,
    required this.maxPayloadBytes,
  });

  final int maxEvents;
  final int maxPayloadBytes;
}

enum TerminalRecordingStartDisposition {
  acknowledged,
  rejected,
  terminationUnknown,
}

/// Typed ownership outcome for a native recording start request.
///
/// Only an explicit native `{ok:false}` response is
/// [TerminalRecordingStartDisposition.rejected]. Once the
/// request may have crossed the transport boundary, a missing, malformed, or
/// correlation-invalid response is
/// [TerminalRecordingStartDisposition.terminationUnknown] and retains the
/// local active identity until a definitive cancel/stop/prepare acknowledgment.
final class TerminalRecordingStartOutcome {
  const TerminalRecordingStartOutcome.acknowledged(this.result)
    : disposition = TerminalRecordingStartDisposition.acknowledged,
      error = null,
      stackTrace = null;

  const TerminalRecordingStartOutcome.rejected({
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingStartDisposition.rejected,
       result = null;

  const TerminalRecordingStartOutcome.terminationUnknown({
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingStartDisposition.terminationUnknown,
       result = null;

  final TerminalRecordingStartDisposition disposition;
  final TerminalRecordingStartResult? result;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isAcknowledged =>
      disposition == TerminalRecordingStartDisposition.acknowledged;
}

enum TerminalRecordingCancelDisposition {
  acknowledged,
  rejected,
  terminationUnknown,
  notOwned,
}

/// Definitive ownership result for a native recording cancellation request.
///
/// Only [TerminalRecordingCancelDisposition.acknowledged] proves that native
/// capture has stopped. Rejections,
/// malformed/failed transport, and an absent local owner deliberately retain
/// the recorder's active identity so callers cannot discard durable recovery
/// metadata while native capture may still be alive.
final class TerminalRecordingCancelOutcome {
  const TerminalRecordingCancelOutcome.acknowledged()
    : disposition = TerminalRecordingCancelDisposition.acknowledged,
      error = null,
      stackTrace = null,
      detachedPrepareStatus = null;

  const TerminalRecordingCancelOutcome.rejected({
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingCancelDisposition.rejected,
       detachedPrepareStatus = null;

  const TerminalRecordingCancelOutcome.terminationUnknown({
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingCancelDisposition.terminationUnknown,
       detachedPrepareStatus = null;

  const TerminalRecordingCancelOutcome.detachedPrepareConfirmed({
    required this.detachedPrepareStatus,
  }) : disposition = TerminalRecordingCancelDisposition.terminationUnknown,
       error = null,
       stackTrace = null;

  const TerminalRecordingCancelOutcome.notOwned()
    : disposition = TerminalRecordingCancelDisposition.notOwned,
      error = null,
      stackTrace = null,
      detachedPrepareStatus = null;

  final TerminalRecordingCancelDisposition disposition;
  final Object? error;
  final StackTrace? stackTrace;
  final TerminalRecordingFinalizeJobStatus? detachedPrepareStatus;

  bool get isAcknowledged =>
      disposition == TerminalRecordingCancelDisposition.acknowledged;

  bool get isDetachedPrepareConfirmed => detachedPrepareStatus != null;
}

/// Small native-worker handle returned without serializing recording data over
/// the synchronous Session Request transport.
final class TerminalRecordingFinalizeJob {
  const TerminalRecordingFinalizeJob({
    required this.sessionId,
    required this.jobId,
    required this.handoffPath,
    required this.errorPath,
  });

  final String sessionId;
  final String jobId;
  final String handoffPath;
  final String errorPath;
}

enum TerminalRecordingFinalizeJobState {
  running,
  ready,
  failed,
  unknown,
  unavailable,
}

/// Bounded status for a detached native finalize worker.
///
/// [TerminalRecordingFinalizeJobState.unavailable] is a transient status-query
/// transport failure and is not proof that the worker stopped.
/// [TerminalRecordingFinalizeJobState.failed] and
/// [TerminalRecordingFinalizeJobState.unknown] are terminal but deliberately
/// keep the durable Dart manifest so recovery can report the recording whose
/// native outcome was not usable.
final class TerminalRecordingFinalizeJobStatus {
  const TerminalRecordingFinalizeJobStatus({
    required this.state,
    this.errorCode,
    this.message,
    this.error,
    this.stackTrace,
  });

  final TerminalRecordingFinalizeJobState state;
  final String? errorCode;
  final String? message;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isTerminal => switch (state) {
    TerminalRecordingFinalizeJobState.ready ||
    TerminalRecordingFinalizeJobState.failed ||
    TerminalRecordingFinalizeJobState.unknown => true,
    TerminalRecordingFinalizeJobState.running ||
    TerminalRecordingFinalizeJobState.unavailable => false,
  };
}

enum TerminalRecordingPrepareDisposition {
  acknowledged,
  rejected,
  terminationUnknown,
}

/// Typed ownership-transfer outcome for native recording finalization.
///
/// A transport or response-contract failure after dispatch is never treated as
/// a rejection: native may already own [job]. The recorder probes that stable
/// job identity and only acknowledges the transfer when native reports
/// running, ready, or failed. Until then, subsequent calls for the same job
/// only re-probe status and never dispatch a second prepare request.
final class TerminalRecordingPrepareOutcome {
  const TerminalRecordingPrepareOutcome.acknowledged({
    required this.job,
    this.status,
  }) : disposition = TerminalRecordingPrepareDisposition.acknowledged,
       error = null,
       stackTrace = null;

  const TerminalRecordingPrepareOutcome.rejected({
    required this.job,
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingPrepareDisposition.rejected,
       status = null;

  const TerminalRecordingPrepareOutcome.terminationUnknown({
    required this.job,
    required this.status,
    required this.error,
    required this.stackTrace,
  }) : disposition = TerminalRecordingPrepareDisposition.terminationUnknown;

  final TerminalRecordingPrepareDisposition disposition;
  final TerminalRecordingFinalizeJob job;
  final TerminalRecordingFinalizeJobStatus? status;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isAcknowledged =>
      disposition == TerminalRecordingPrepareDisposition.acknowledged;
}

final class _UncertainRecordingPrepare {
  const _UncertainRecordingPrepare({
    required this.job,
    required this.error,
    required this.stackTrace,
  });

  final TerminalRecordingFinalizeJob job;
  final Object error;
  final StackTrace stackTrace;
}

/// Controls native raw-session capture without routing PTY bytes through Frames.
///
/// Capture is explicitly bounded by the native backend. [stop] either returns a
/// complete current-schema recording or throws; a capacity overflow never
/// returns a partial
/// event stream that could look complete.
final class TerminalLiveRecorder {
  TerminalLiveRecorder({
    required PtySessionRequestV1Backend backend,
    DateTime Function()? utcNow,
  }) : _requestTransport = TerminalSessionRequestTransport(backend),
       _utcNow = utcNow ?? DateTime.now;

  final TerminalSessionRequestTransport _requestTransport;
  final DateTime Function() _utcNow;
  final Set<String> _activeSessionIds = <String>{};
  final Map<String, _UncertainRecordingPrepare> _uncertainPrepares =
      <String, _UncertainRecordingPrepare>{};

  bool isRecording(String sessionId) => _activeSessionIds.contains(sessionId);

  TerminalRecordingStartResult start(
    String sessionId, {
    required TerminalRecordingInputPolicy inputPolicy,
  }) {
    final outcome = startWithOutcome(sessionId, inputPolicy: inputPolicy);
    final result = outcome.result;
    if (result != null) {
      return result;
    }
    Error.throwWithStackTrace(
      outcome.error ?? StateError('Native recording start failed.'),
      outcome.stackTrace ?? StackTrace.current,
    );
  }

  TerminalRecordingStartOutcome startWithOutcome(
    String sessionId, {
    required TerminalRecordingInputPolicy inputPolicy,
  }) {
    if (isRecording(sessionId)) {
      return TerminalRecordingStartOutcome.rejected(
        error: TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.alreadyActive,
          sessionId: sessionId,
          message: 'A recording is already active for this session',
        ),
        stackTrace: StackTrace.current,
      );
    }
    final Map<String, Object?> response;
    try {
      response = _request(sessionId, <String, Object?>{
        'kind': 'terminal.recording_start',
        'schema_version': terminalRecordingSchemaVersion,
        'created_at_utc': _utcNow().toUtc().toIso8601String(),
        'input_policy': inputPolicy.name,
      });
    } on Object catch (error, stackTrace) {
      _activeSessionIds.add(sessionId);
      return TerminalRecordingStartOutcome.terminationUnknown(
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (response['ok'] != true) {
      if (response['ok'] == false && response['error'] is Map) {
        try {
          _throwResponseError(sessionId, response);
        } on Object catch (error, stackTrace) {
          return TerminalRecordingStartOutcome.rejected(
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final error = TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: 'Native recording start response was malformed',
      );
      _activeSessionIds.add(sessionId);
      return TerminalRecordingStartOutcome.terminationUnknown(
        error: error,
        stackTrace: StackTrace.current,
      );
    }
    final maxEvents = response['max_events'];
    final maxPayloadBytes = response['max_payload_bytes'];
    if (maxEvents is! int ||
        maxEvents <= 0 ||
        maxPayloadBytes is! int ||
        maxPayloadBytes <= 0) {
      final error = TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: 'Native recording start response omitted capacity limits',
      );
      _activeSessionIds.add(sessionId);
      return TerminalRecordingStartOutcome.terminationUnknown(
        error: error,
        stackTrace: StackTrace.current,
      );
    }
    _activeSessionIds.add(sessionId);
    return TerminalRecordingStartOutcome.acknowledged(
      TerminalRecordingStartResult(
        maxEvents: maxEvents,
        maxPayloadBytes: maxPayloadBytes,
      ),
    );
  }

  TerminalRecording stop(String sessionId) {
    if (_uncertainPrepares.containsKey(sessionId)) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: 'Native recording prepare ownership is still uncertain',
      );
    }
    if (!isRecording(sessionId)) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.notActive,
        sessionId: sessionId,
        message: 'No recording is active for this session',
      );
    }
    try {
      final response = _request(sessionId, const <String, Object?>{
        'kind': 'terminal.recording_stop',
      });
      _throwResponseError(sessionId, response);
      final source = response['recording_ndjson'];
      if (source is! String) {
        throw TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.invalidResponse,
          sessionId: sessionId,
          message: 'Native recording stop response omitted recording_ndjson',
        );
      }
      final recording = const TerminalRecordingCodec().decode(source);
      if (recording.metadata.sessionId != sessionId) {
        throw TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.invalidResponse,
          sessionId: sessionId,
          message: 'Native recording response used a different session id',
        );
      }
      return recording;
    } finally {
      _activeSessionIds.remove(sessionId);
    }
  }

  /// Transfers the active native recording to a background finalize worker.
  ///
  /// The returned paths are opaque native-created files inside the private
  /// [handoffDirectory]. Callers must poll them asynchronously and validate
  /// that they remain inside that directory before reading either path.
  TerminalRecordingFinalizeJob prepareStop(
    String sessionId, {
    required String handoffDirectory,
    required String jobId,
  }) {
    final outcome = prepareStopWithOutcome(
      sessionId,
      handoffDirectory: handoffDirectory,
      jobId: jobId,
    );
    if (outcome.isAcknowledged) {
      return outcome.job;
    }
    Error.throwWithStackTrace(
      outcome.error ?? StateError('Native recording prepare failed.'),
      outcome.stackTrace ?? StackTrace.current,
    );
  }

  TerminalRecordingPrepareOutcome prepareStopWithOutcome(
    String sessionId, {
    required String handoffDirectory,
    required String jobId,
    TerminalRecordingFinalizeJob? expectedJob,
  }) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(jobId)) {
      throw ArgumentError.value(
        jobId,
        'jobId',
        'Must be 32 lowercase hexadecimal characters.',
      );
    }
    final derivedJob = _provisionalFinalizeJob(
      sessionId: sessionId,
      handoffDirectory: handoffDirectory,
      jobId: jobId,
    );
    if (expectedJob != null && !_sameFinalizeJob(expectedJob, derivedJob)) {
      throw ArgumentError.value(
        expectedJob,
        'expectedJob',
        'Must use the exact handoff paths derived from the directory and job.',
      );
    }
    final provisionalJob = expectedJob ?? derivedJob;
    final uncertain = _uncertainPrepares[sessionId];
    if (uncertain != null) {
      if (!_sameFinalizeJob(uncertain.job, provisionalJob)) {
        return TerminalRecordingPrepareOutcome.rejected(
          job: provisionalJob,
          error: TerminalRecordingBackendException(
            code: TerminalRecordingBackendErrorCode.alreadyActive,
            sessionId: sessionId,
            message: 'Another native recording prepare outcome is unresolved',
          ),
          stackTrace: StackTrace.current,
        );
      }
      return _resolveUncertainPrepare(uncertain);
    }
    if (!isRecording(sessionId)) {
      return TerminalRecordingPrepareOutcome.rejected(
        job: provisionalJob,
        error: TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.notActive,
          sessionId: sessionId,
          message: 'No recording is active for this session',
        ),
        stackTrace: StackTrace.current,
      );
    }
    final Map<String, Object?> response;
    try {
      response = _request(sessionId, <String, Object?>{
        'kind': 'terminal.recording_stop_prepare',
        'handoff_directory': handoffDirectory,
        'job_id': jobId,
      });
    } on Object catch (error, stackTrace) {
      return _recordUncertainPrepare(
        job: provisionalJob,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (response['ok'] != true) {
      if (response['ok'] == false && response['error'] is Map) {
        try {
          _throwResponseError(sessionId, response);
        } on Object catch (error, stackTrace) {
          if (error case TerminalRecordingBackendException(
            code: TerminalRecordingBackendErrorCode.notActive,
          )) {
            _activeSessionIds.remove(sessionId);
          }
          return TerminalRecordingPrepareOutcome.rejected(
            job: provisionalJob,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      return _recordUncertainPrepare(
        job: provisionalJob,
        error: TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.invalidResponse,
          sessionId: sessionId,
          message: 'Native recording finalize response was malformed',
        ),
        stackTrace: StackTrace.current,
      );
    }
    final responseJobId = response['job_id'];
    final handoffPath = response['handoff_path'];
    final errorPath = response['error_path'];
    final responseJob = handoffPath is String && errorPath is String
        ? TerminalRecordingFinalizeJob(
            sessionId: sessionId,
            jobId: jobId,
            handoffPath: handoffPath,
            errorPath: errorPath,
          )
        : null;
    if (responseJobId != jobId ||
        handoffPath is! String ||
        handoffPath.isEmpty ||
        handoffPath.length > 4096 ||
        errorPath is! String ||
        errorPath.isEmpty ||
        errorPath.length > 4096 ||
        (expectedJob != null && !_sameFinalizeJob(expectedJob, responseJob!))) {
      return _recordUncertainPrepare(
        job: provisionalJob,
        error: TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.invalidResponse,
          sessionId: sessionId,
          message: 'Native recording finalize response was invalid',
        ),
        stackTrace: StackTrace.current,
      );
    }
    _uncertainPrepares.remove(sessionId);
    _activeSessionIds.remove(sessionId);
    return TerminalRecordingPrepareOutcome.acknowledged(job: responseJob!);
  }

  TerminalRecordingPrepareOutcome _recordUncertainPrepare({
    required TerminalRecordingFinalizeJob job,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final uncertain = _UncertainRecordingPrepare(
      job: job,
      error: error,
      stackTrace: stackTrace,
    );
    _uncertainPrepares[job.sessionId] = uncertain;
    return _resolveUncertainPrepare(uncertain);
  }

  TerminalRecordingPrepareOutcome _resolveUncertainPrepare(
    _UncertainRecordingPrepare uncertain,
  ) {
    final status = probeFinalizeJobStatus(
      uncertain.job,
      consumeTerminal: false,
    );
    if (status.state
        case TerminalRecordingFinalizeJobState.running ||
            TerminalRecordingFinalizeJobState.ready ||
            TerminalRecordingFinalizeJobState.failed) {
      _uncertainPrepares.remove(uncertain.job.sessionId);
      _activeSessionIds.remove(uncertain.job.sessionId);
      return TerminalRecordingPrepareOutcome.acknowledged(
        job: uncertain.job,
        status: status,
      );
    }
    return TerminalRecordingPrepareOutcome.terminationUnknown(
      job: uncertain.job,
      status: status,
      error: status.error ?? uncertain.error,
      stackTrace: status.stackTrace ?? uncertain.stackTrace,
    );
  }

  TerminalRecordingFinalizeJob _provisionalFinalizeJob({
    required String sessionId,
    required String handoffDirectory,
    required String jobId,
  }) {
    final pathSeparator = handoffDirectory.contains(r'\') ? r'\' : '/';
    final separator =
        handoffDirectory.endsWith('/') || handoffDirectory.endsWith(r'\')
        ? ''
        : pathSeparator;
    final handoffPath =
        '$handoffDirectory$separator.ianvs-recording-handoff-$jobId.ndjson';
    return TerminalRecordingFinalizeJob(
      sessionId: sessionId,
      jobId: jobId,
      handoffPath: handoffPath,
      errorPath: '$handoffPath.error.json',
    );
  }

  bool _sameFinalizeJob(
    TerminalRecordingFinalizeJob left,
    TerminalRecordingFinalizeJob right,
  ) {
    return left.sessionId == right.sessionId &&
        left.jobId == right.jobId &&
        left.handoffPath == right.handoffPath &&
        left.errorPath == right.errorPath;
  }

  /// Releases conservative local ownership after another durable owner has
  /// settled an ambiguous prepare job without routing through this recorder's
  /// status resolver (for example, repository handoff recovery at shutdown).
  void confirmPrepareOwnershipSettled(TerminalRecordingFinalizeJob job) {
    final uncertain = _uncertainPrepares[job.sessionId];
    if (uncertain != null && _sameFinalizeJob(uncertain.job, job)) {
      _uncertainPrepares.remove(job.sessionId);
      _activeSessionIds.remove(job.sessionId);
    }
  }

  TerminalRecordingCancelOutcome cancel(String sessionId) {
    if (!isRecording(sessionId)) {
      return const TerminalRecordingCancelOutcome.notOwned();
    }
    final Map<String, Object?> response;
    try {
      response = _request(sessionId, const <String, Object?>{
        'kind': 'terminal.recording_cancel',
      });
    } on Object catch (error, stackTrace) {
      return TerminalRecordingCancelOutcome.terminationUnknown(
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (response['ok'] != true) {
      if (response['ok'] == false) {
        try {
          _throwResponseError(sessionId, response);
        } on Object catch (error, stackTrace) {
          if (error case TerminalRecordingBackendException(
            code: TerminalRecordingBackendErrorCode.notActive,
          )) {
            final uncertain = _uncertainPrepares[sessionId];
            if (uncertain != null) {
              final status = probeFinalizeJobStatus(
                uncertain.job,
                consumeTerminal: false,
              );
              if (status.state == TerminalRecordingFinalizeJobState.unknown) {
                _uncertainPrepares.remove(sessionId);
                _activeSessionIds.remove(sessionId);
                return const TerminalRecordingCancelOutcome.acknowledged();
              }
              if (status.state == TerminalRecordingFinalizeJobState.running ||
                  status.state == TerminalRecordingFinalizeJobState.ready ||
                  status.state == TerminalRecordingFinalizeJobState.failed) {
                return TerminalRecordingCancelOutcome.detachedPrepareConfirmed(
                  detachedPrepareStatus: status,
                );
              }
              return TerminalRecordingCancelOutcome.terminationUnknown(
                error: TerminalRecordingBackendException(
                  code: TerminalRecordingBackendErrorCode.invalidResponse,
                  sessionId: sessionId,
                  message: 'Native finalize ownership remains unresolved',
                ),
                stackTrace: stackTrace,
              );
            }
            _activeSessionIds.remove(sessionId);
            return const TerminalRecordingCancelOutcome.acknowledged();
          }
          return TerminalRecordingCancelOutcome.rejected(
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final error = TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: 'Native recording cancel response omitted an acknowledgment',
      );
      return TerminalRecordingCancelOutcome.terminationUnknown(
        error: error,
        stackTrace: StackTrace.current,
      );
    }
    _uncertainPrepares.remove(sessionId);
    _activeSessionIds.remove(sessionId);
    return const TerminalRecordingCancelOutcome.acknowledged();
  }

  /// Queries the detached native worker independently of live session state.
  ///
  /// A terminal status may be consumed from native's bounded in-process
  /// registry. The handoff artifact/error and Dart manifest remain the durable
  /// cross-process source of truth.
  TerminalRecordingFinalizeJobStatus probeFinalizeJobStatus(
    TerminalRecordingFinalizeJob job, {
    bool consumeTerminal = true,
  }) {
    final Map<String, Object?> response;
    try {
      response = _request(job.sessionId, <String, Object?>{
        'kind': 'terminal.recording_finalize_status',
        'job_id': job.jobId,
        'consume_terminal': consumeTerminal,
      });
      _throwResponseError(job.sessionId, response);
    } on Object catch (error, stackTrace) {
      return TerminalRecordingFinalizeJobStatus(
        state: TerminalRecordingFinalizeJobState.unavailable,
        error: error,
        stackTrace: stackTrace,
      );
    }
    final state = switch (response['state']) {
      'running' => TerminalRecordingFinalizeJobState.running,
      'ready' => TerminalRecordingFinalizeJobState.ready,
      'failed' => TerminalRecordingFinalizeJobState.failed,
      'unknown' => TerminalRecordingFinalizeJobState.unknown,
      _ => TerminalRecordingFinalizeJobState.unavailable,
    };
    final uncertain = _uncertainPrepares[job.sessionId];
    if (uncertain != null &&
        _sameFinalizeJob(uncertain.job, job) &&
        (state == TerminalRecordingFinalizeJobState.running ||
            state == TerminalRecordingFinalizeJobState.ready ||
            state == TerminalRecordingFinalizeJobState.failed)) {
      _uncertainPrepares.remove(job.sessionId);
      _activeSessionIds.remove(job.sessionId);
    }
    final rawError = response['error'];
    final errorMap = rawError is Map
        ? rawError.cast<String, Object?>()
        : const <String, Object?>{};
    return TerminalRecordingFinalizeJobStatus(
      state: state,
      errorCode: errorMap['code'] is String
          ? errorMap['code']! as String
          : null,
      message: errorMap['message'] is String
          ? errorMap['message']! as String
          : null,
    );
  }

  Map<String, Object?> _request(
    String sessionId,
    Map<String, Object?> request,
  ) {
    final Map<String, Object?>? decoded;
    try {
      final operation = request['kind'];
      if (operation is! String || operation.isEmpty) {
        throw StateError('Recording request is missing its operation');
      }
      final payload = Map<String, Object?>.of(request)..remove('kind');
      decoded = _requestTransport.requestObject(sessionId, operation, payload);
    } on PtySessionRequestContractException catch (error) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: error.toString(),
      );
    }
    if (decoded == null) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.unsupportedBackend,
        sessionId: sessionId,
        message: 'The backend does not support native session recording',
      );
    }
    return decoded;
  }

  void _throwResponseError(String sessionId, Map<String, Object?> response) {
    if (response['ok'] == true) {
      return;
    }
    final error = response['error'];
    final errorMap = error is Map
        ? error.cast<String, Object?>()
        : const <String, Object?>{};
    final rawCode = errorMap['code'];
    final code = switch (rawCode) {
      'already_active' => TerminalRecordingBackendErrorCode.alreadyActive,
      'not_active' => TerminalRecordingBackendErrorCode.notActive,
      'capacity_exceeded' => TerminalRecordingBackendErrorCode.capacityExceeded,
      'invalid_handoff' => TerminalRecordingBackendErrorCode.invalidHandoff,
      'handoff_collision' => TerminalRecordingBackendErrorCode.handoffCollision,
      'finalize_capacity_exceeded' =>
        TerminalRecordingBackendErrorCode.finalizeCapacityExceeded,
      'finalize_worker_spawn_failed' =>
        TerminalRecordingBackendErrorCode.finalizeWorkerSpawnFailed,
      'unsupported_backend' =>
        TerminalRecordingBackendErrorCode.unsupportedBackend,
      _ => TerminalRecordingBackendErrorCode.nativeFailure,
    };
    throw TerminalRecordingBackendException(
      code: code,
      sessionId: sessionId,
      message: errorMap['message'] is String
          ? errorMap['message']! as String
          : 'Native recording request failed',
    );
  }
}

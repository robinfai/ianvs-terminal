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

/// Controls native raw-session capture without routing PTY bytes through Frames.
///
/// Capture is explicitly bounded by the native backend. [stop] either returns a
/// complete v1 recording or throws; a capacity overflow never returns a partial
/// event stream that could look complete.
final class TerminalLiveRecorder {
  TerminalLiveRecorder({
    required PtySessionJsonRequestBackend backend,
    DateTime Function()? utcNow,
  }) : _requestTransport = TerminalSessionRequestTransport(backend),
       _utcNow = utcNow ?? DateTime.now;

  final TerminalSessionRequestTransport _requestTransport;
  final DateTime Function() _utcNow;
  final Set<String> _activeSessionIds = <String>{};

  bool isRecording(String sessionId) => _activeSessionIds.contains(sessionId);

  TerminalRecordingStartResult start(
    String sessionId, {
    required TerminalRecordingInputPolicy inputPolicy,
  }) {
    if (isRecording(sessionId)) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.alreadyActive,
        sessionId: sessionId,
        message: 'A recording is already active for this session',
      );
    }
    final response = _request(sessionId, <String, Object?>{
      'kind': 'terminal.recording_start',
      'schema_version': terminalRecordingSchemaVersion,
      'created_at_utc': _utcNow().toUtc().toIso8601String(),
      'input_policy': inputPolicy.name,
    });
    _throwResponseError(sessionId, response);
    final maxEvents = response['max_events'];
    final maxPayloadBytes = response['max_payload_bytes'];
    if (maxEvents is! int ||
        maxEvents <= 0 ||
        maxPayloadBytes is! int ||
        maxPayloadBytes <= 0) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.invalidResponse,
        sessionId: sessionId,
        message: 'Native recording start response omitted capacity limits',
      );
    }
    _activeSessionIds.add(sessionId);
    return TerminalRecordingStartResult(
      maxEvents: maxEvents,
      maxPayloadBytes: maxPayloadBytes,
    );
  }

  TerminalRecording stop(String sessionId) {
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
    if (!isRecording(sessionId)) {
      throw TerminalRecordingBackendException(
        code: TerminalRecordingBackendErrorCode.notActive,
        sessionId: sessionId,
        message: 'No recording is active for this session',
      );
    }
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(jobId)) {
      throw ArgumentError.value(
        jobId,
        'jobId',
        'Must be 32 lowercase hexadecimal characters.',
      );
    }
    var nativeAccepted = false;
    try {
      final response = _request(sessionId, <String, Object?>{
        'kind': 'terminal.recording_stop_prepare',
        'handoff_directory': handoffDirectory,
        'job_id': jobId,
      });
      _throwResponseError(sessionId, response);
      nativeAccepted = true;
      final responseJobId = response['job_id'];
      final handoffPath = response['handoff_path'];
      final errorPath = response['error_path'];
      if (responseJobId != jobId ||
          handoffPath is! String ||
          handoffPath.isEmpty ||
          handoffPath.length > 4096 ||
          errorPath is! String ||
          errorPath.isEmpty ||
          errorPath.length > 4096) {
        throw TerminalRecordingBackendException(
          code: TerminalRecordingBackendErrorCode.invalidResponse,
          sessionId: sessionId,
          message: 'Native recording finalize response was invalid',
        );
      }
      _activeSessionIds.remove(sessionId);
      return TerminalRecordingFinalizeJob(
        sessionId: sessionId,
        jobId: jobId,
        handoffPath: handoffPath,
        errorPath: errorPath,
      );
    } on TerminalRecordingBackendException catch (error) {
      if (nativeAccepted ||
          error.code == TerminalRecordingBackendErrorCode.notActive ||
          error.code == TerminalRecordingBackendErrorCode.capacityExceeded) {
        _activeSessionIds.remove(sessionId);
      }
      rethrow;
    }
  }

  void cancel(String sessionId) {
    if (!isRecording(sessionId)) {
      return;
    }
    try {
      final response = _request(sessionId, const <String, Object?>{
        'kind': 'terminal.recording_cancel',
      });
      _throwResponseError(sessionId, response);
    } finally {
      _activeSessionIds.remove(sessionId);
    }
  }

  Map<String, Object?> _request(
    String sessionId,
    Map<String, Object?> request,
  ) {
    final Map<String, Object?>? decoded;
    try {
      decoded = _requestTransport.requestObject(sessionId, request);
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

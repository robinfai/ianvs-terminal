import 'package:ianvs_pty/ianvs_pty.dart';

import '../runtime/terminal_session_request_transport.dart';
import 'terminal_recording.dart';

enum TerminalRecordingBackendErrorCode {
  unsupportedBackend,
  alreadyActive,
  notActive,
  capacityExceeded,
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

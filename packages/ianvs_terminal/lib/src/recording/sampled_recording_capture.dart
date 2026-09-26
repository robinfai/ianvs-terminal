import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../runtime/terminal_session_request_transport.dart';

/// Persist this identity and the library's filesystem claim BEFORE start.
/// A transport error, timeout, or missing registry entry never releases a claim.
final class SampledCaptureHandle {
  SampledCaptureHandle({
    required this.sessionId,
    required this.captureId,
    required this.bundlePath,
  }) {
    final session = BigInt.tryParse(sessionId);
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(sessionId) ||
        session == null ||
        session > (BigInt.one << 64) - BigInt.one ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(captureId)) {
      throw ArgumentError('Invalid sampled recording identity');
    }
    final uri = Uri.file(bundlePath, windows: Platform.isWindows);
    final parts = bundlePath.split(Platform.isWindows ? RegExp(r'[\\/]') : '/');
    if (utf8.encode(bundlePath).length > 4096 ||
        bundlePath.contains('\u0000') ||
        !File(bundlePath).isAbsolute ||
        parts.contains('..') ||
        uri.pathSegments.lastOrNull != '$captureId.trailrec') {
      throw ArgumentError('Expected an absolute capture_id.trailrec path');
    }
  }

  final String sessionId;
  final String captureId;
  final String bundlePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 2,
    'capture_id': captureId,
    'bundle_path': bundlePath,
  };
}

final class SampledCaptureStart {
  SampledCaptureStart({
    required this.handle,
    required this.startedAtUnixMillis,
    required this.title,
    this.hostname,
  }) {
    if (startedAtUnixMillis < 0 ||
        <String>[title, ?hostname].any(
          (value) =>
              utf8.encode(value).length > 8192 || value.contains('\u0000'),
        )) {
      throw ArgumentError('Invalid sampled recording metadata');
    }
  }

  final SampledCaptureHandle handle;
  final int startedAtUnixMillis;
  final String title;
  final String? hostname;

  Map<String, Object?> toJson() => <String, Object?>{
    ...handle.toJson(),
    'metadata': <String, Object?>{
      'recording_id': handle.captureId,
      'started_at_unix_millis': startedAtUnixMillis,
      'title': title,
      'hostname': hostname,
    },
  };
}

enum SampledCapturePhase {
  starting,
  capturing,
  stopping,
  finished,
  interrupted,
  failed,
}

final class SampledCaptureCounts {
  const SampledCaptureCounts._({
    required this.recordCount,
    required this.visualCount,
    required this.semanticCount,
    required this.durationMicros,
  });

  factory SampledCaptureCounts._decode(Object? value) {
    final json = _object(value);
    _keys(json, const <String>{
      'record_count',
      'visual_count',
      'semantic_count',
      'duration_micros',
    });
    int count(String key) {
      final result = json[key];
      if (result is! int || result < 0) {
        throw const FormatException('Invalid recording count');
      }
      return result;
    }

    final records = count('record_count');
    final visuals = count('visual_count');
    final semantics = count('semantic_count');
    if (visuals > records || semantics != records - visuals) {
      throw const FormatException('Inconsistent recording counts');
    }
    return SampledCaptureCounts._(
      recordCount: records,
      visualCount: visuals,
      semanticCount: semantics,
      durationMicros: count('duration_micros'),
    );
  }

  final int recordCount;
  final int visualCount;
  final int semanticCount;
  final int durationMicros;

  bool _atMost(SampledCaptureCounts other) =>
      recordCount <= other.recordCount &&
      visualCount <= other.visualCount &&
      semanticCount <= other.semanticCount &&
      durationMicros <= other.durationMicros;
}

final class SampledCaptureStatus {
  const SampledCaptureStatus._({
    required this.handle,
    required this.phase,
    required this.settled,
    required this.stopRequested,
    required this.written,
    required this.committed,
    required this.error,
  });

  factory SampledCaptureStatus._decode(
    Map<String, Object?> json,
    SampledCaptureHandle handle, {
    required bool releasing,
  }) {
    _keys(json, <String>{
      'ok',
      'schema_version',
      'capture_id',
      'bundle_path',
      'session_id',
      'phase',
      'settled',
      'stop_requested',
      'written',
      'committed',
      'error',
      if (releasing) 'released',
    });
    if (json['ok'] != true ||
        json['schema_version'] is! int ||
        json['schema_version'] != 2 ||
        json['capture_id'] != handle.captureId ||
        json['bundle_path'] != handle.bundlePath ||
        json['session_id'] != handle.sessionId ||
        (releasing && json['released'] != true)) {
      throw const FormatException('Recording response identity mismatch');
    }
    final phase = SampledCapturePhase.values
        .where((phase) => phase.name == json['phase'])
        .firstOrNull;
    final settled = json['settled'];
    final stopRequested = json['stop_requested'];
    final error = json['error'];
    if (phase == null ||
        settled is! bool ||
        stopRequested is! bool ||
        (error != null && error is! String)) {
      throw const FormatException('Invalid recording status');
    }
    final terminal =
        phase == SampledCapturePhase.finished ||
        phase == SampledCapturePhase.interrupted ||
        phase == SampledCapturePhase.failed;
    if ((settled && !terminal) ||
        (releasing && !settled) ||
        (phase == SampledCapturePhase.failed &&
            (error == null || error == '')) ||
        (phase != SampledCapturePhase.failed && error != null)) {
      throw const FormatException('Inconsistent recording settlement');
    }
    final written = SampledCaptureCounts._decode(json['written']);
    final committed = SampledCaptureCounts._decode(json['committed']);
    if (!committed._atMost(written) ||
        (phase == SampledCapturePhase.finished &&
            !written._atMost(committed))) {
      throw const FormatException('Inconsistent recording durability');
    }
    return SampledCaptureStatus._(
      handle: handle,
      phase: phase,
      settled: settled,
      stopRequested: stopRequested,
      written: written,
      committed: committed,
      error: error as String?,
    );
  }

  final SampledCaptureHandle handle;
  final SampledCapturePhase phase;

  /// The native writer released its file and queue. Failure alone is NOT this
  /// proof: an admission failure can still be draining accepted records.
  /// The library must also retain/check its own cross-process filesystem claim.
  final bool settled;
  final bool stopRequested;
  final SampledCaptureCounts written;
  final SampledCaptureCounts committed;
  final String? error;
}

/// All operation failures leave ownership unresolved. Keep the persisted claim
/// and retry with the SAME identity, or recover after process ownership ends.
final class SampledCaptureRequestException implements Exception {
  const SampledCaptureRequestException(this.operation, this.cause);
  final String operation;
  final Object cause;
  @override
  String toString() => 'SampledCaptureRequestException($operation: $cause)';
}

/// Native requests return promptly; starting and stopping use background jobs.
/// No method reads recordings, launches replay sessions, or deletes files.
final class SampledRecordingCaptureClient {
  SampledRecordingCaptureClient({PtySessionRequestV1Backend? backend})
    : _transport = TerminalSessionRequestTransport(backend);

  final TerminalSessionRequestTransport _transport;

  SampledCaptureStatus start(SampledCaptureStart request) =>
      _request('start', request.handle, request.toJson());

  SampledCaptureStatus status(SampledCaptureHandle handle) =>
      _request('status', handle, handle.toJson());

  /// Stop is idempotent, including while start is pending or after session close.
  /// Cancelling a product capture uses stop and preserves its prefix until the
  /// library receives settled=true and decides whether to retain the result.
  SampledCaptureStatus stop(SampledCaptureHandle handle) =>
      _request('stop', handle, handle.toJson());

  /// Release the bounded native registry entry after persisting the final state.
  /// This never removes or renames the recording bundle.
  SampledCaptureStatus release(SampledCaptureHandle handle) =>
      _request('release', handle, handle.toJson());

  Future<SampledCaptureStatus> waitUntilSettled(
    SampledCaptureHandle handle, {
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 100),
    bool Function()? isCancelled,
  }) async {
    if (timeout <= Duration.zero || pollInterval <= Duration.zero) {
      throw ArgumentError('Recording wait durations must be positive');
    }
    final clock = Stopwatch()..start();
    while (true) {
      if (isCancelled?.call() ?? false) {
        throw const SampledCaptureRequestException('wait', 'cancelled');
      }
      final result = status(handle);
      if (result.settled) return result;
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw SampledCaptureRequestException(
          'wait',
          TimeoutException('Recording writer is not settled', timeout),
        );
      }
      await Future<void>.delayed(
        pollInterval < remaining ? pollInterval : remaining,
      );
    }
  }

  SampledCaptureStatus _request(
    String action,
    SampledCaptureHandle handle,
    Map<String, Object?> payload,
  ) {
    final operation = 'terminal.sampled_recording_$action';
    try {
      final response = _transport.requestObject(
        handle.sessionId,
        operation,
        payload,
      );
      if (response == null) {
        throw const FormatException('Recording request transport unavailable');
      }
      if (response['ok'] == false) {
        throw FormatException(
          'Recording request rejected: ${response['error']}',
        );
      }
      return SampledCaptureStatus._decode(
        response,
        handle,
        releasing: action == 'release',
      );
    } on Object catch (error) {
      throw SampledCaptureRequestException(operation, error);
    }
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected recording object');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw const FormatException('Unexpected recording contract fields');
  }
}

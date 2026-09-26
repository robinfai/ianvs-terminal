import 'dart:convert';
import 'dart:io';

import 'package:ianvs_pty/ianvs_pty.dart';

import 'fake_pty_backend.dart';

class NoSampledFileReads implements RecordingFileApi {
  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) => throw StateError('Unexpected file read: $operation');
}

class SampledTestBackend extends FakePtyBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[2],
        'features': <String>[
          ptyRuntimeFeatureSessionRecordingV2,
          'zmodem.receive.v1',
          'zmodem.send.v1',
        ],
      });
  bool loseStart = false;
  bool loseStop = false;
  bool loseStatus = false;
  bool deferSettlement = false;
  bool corruptIdentity = false;
  String terminalPhase = 'finished';
  final Set<String> loseStopFor = {};
  final List<String> timeline = [];
  final List<String> createdSessions = [];
  @override
  String createSession(String config) {
    final id = super.createSession(config);
    createdSessions.add(id);
    return id;
  }

  void Function(String operation, String sessionId)? onRequest;
  @override
  void closeSession(String sessionId) {
    timeline.add('close:$sessionId');
    super.closeSession(sessionId);
  }

  final List<String> capturedIds = [];
  final Set<String> finished = {};
  final List<String> actions = [];
  bool manifestBeforeStart = false;
  @override
  String? requestSessionV1Json(String sessionId, String input) {
    final request = jsonDecode(input) as Map;
    final operation = request['operation'] as String;
    if (!operation.startsWith('terminal.sampled_recording_')) {
      return super.requestSessionV1Json(sessionId, input);
    }
    final payload = request['payload'] as Map;
    final id = payload['capture_id'] as String;
    actions.add(operation);
    timeline.add('$operation:$sessionId');
    onRequest?.call(operation, sessionId);
    if (loseStatus && operation.endsWith('_status')) return null;
    if (operation.endsWith('_start')) {
      capturedIds.add(id);
      final bundle = Directory(payload['bundle_path'] as String);
      manifestBeforeStart = File(
        '${bundle.parent.path}/entries/$id.json',
      ).existsSync();
      if (loseStart) return null;
    }
    if (operation.endsWith('_stop')) {
      if (loseStop || loseStopFor.contains(sessionId)) return null;
      finished.add(id);
    }
    final done = finished.contains(id) && !deferSettlement;
    const counts = {
      'record_count': 0,
      'visual_count': 0,
      'semantic_count': 0,
      'duration_micros': 0,
    };
    return jsonEncode({
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': operation,
      'ok': true,
      'timestamp_micros': 1,
      'payload': {
        'ok': true,
        'schema_version': 2,
        'capture_id': corruptIdentity ? 'f' * 32 : id,
        'bundle_path': payload['bundle_path'],
        'session_id': sessionId,
        'phase': done ? terminalPhase : 'capturing',
        'settled': done,
        'stop_requested': done,
        'written': counts,
        'committed': counts,
        'error': done && terminalPhase == 'failed' ? 'disk full' : null,
        if (operation.endsWith('_release')) 'released': true,
      },
    });
  }
}

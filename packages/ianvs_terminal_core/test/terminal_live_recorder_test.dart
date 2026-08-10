import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  group('TerminalLiveRecorder', () {
    test('starts native capture and decodes the stopped v1 recording', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(
        backend: backend,
        utcNow: () => DateTime.utc(2026, 7, 21),
      );

      final started = recorder.start(
        '42',
        inputPolicy: TerminalRecordingInputPolicy.redact,
      );
      final recording = recorder.stop('42');

      expect(started.maxEvents, 4096);
      expect(started.maxPayloadBytes, 8 * 1024 * 1024);
      expect(recording.metadata.sessionId, '42');
      expect(
        recording.metadata.inputPolicy,
        TerminalRecordingInputPolicy.redact,
      );
      expect(
        recording.events.map((event) => event.kind),
        <TerminalRecordingEventKind>[
          TerminalRecordingEventKind.sessionStarted,
          TerminalRecordingEventKind.ptyOutput,
          TerminalRecordingEventKind.userInput,
          TerminalRecordingEventKind.resize,
        ],
      );
      expect(recording.events[1].bytes, utf8.encode('ready\r\n'));
      expect(recording.events[2].redactedByteLength, 6);
      expect(backend.requests.map((request) => request['kind']), <String>[
        'terminal.recording_start',
        'terminal.recording_stop',
      ]);
      expect(backend.requests.first['input_policy'], 'redact');
      expect(
        backend.requests.first['created_at_utc'],
        '2026-07-21T00:00:00.000Z',
      );
    });

    test('prefers Session Request v1 when the backend advertises it', () {
      final backend = _RecordingRequestBackend(supportsV1: true);
      final recorder = TerminalLiveRecorder(
        backend: backend,
        utcNow: () => DateTime.utc(2026, 7, 21),
      );

      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      recorder.stop('42');

      expect(backend.requests, isEmpty);
      expect(
        backend.v1Requests.map((request) => request['operation']),
        <String>['terminal.recording_start', 'terminal.recording_stop'],
      );
      expect(
        (backend.v1Requests.first['payload']! as Map)['input_policy'],
        'redact',
      );
    });

    test(
      'reports bounded native overflow without returning a partial recording',
      () {
        final backend = _RecordingRequestBackend()..overflowOnStop = true;
        final recorder = TerminalLiveRecorder(backend: backend);
        recorder.start('7', inputPolicy: TerminalRecordingInputPolicy.record);

        expect(
          () => recorder.stop('7'),
          throwsA(
            isA<TerminalRecordingBackendException>()
                .having(
                  (error) => error.code,
                  'code',
                  TerminalRecordingBackendErrorCode.capacityExceeded,
                )
                .having((error) => error.sessionId, 'sessionId', '7'),
          ),
        );
        expect(recorder.isRecording('7'), isFalse);
      },
    );

    test('rejects stop when no recording is active', () {
      final recorder = TerminalLiveRecorder(
        backend: _RecordingRequestBackend(),
      );

      expect(
        () => recorder.stop('missing'),
        throwsA(
          isA<TerminalRecordingBackendException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingBackendErrorCode.notActive,
          ),
        ),
      );
    });
  });
}

final class _RecordingRequestBackend
    implements PtySessionJsonRequestBackend, PtySessionRequestV1Backend {
  _RecordingRequestBackend({this.supportsV1 = false});

  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> v1Requests = <Map<String, Object?>>[];
  final bool supportsV1;
  bool overflowOnStop = false;

  @override
  bool get supportsSessionRequestV1 => supportsV1;

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
    v1Requests.add(request);
    final payload = (request['payload']! as Map).cast<String, Object?>();
    final legacyRequest = <String, Object?>{
      'kind': request['operation'],
      ...payload,
    };
    final legacyResponse = _responseFor(sessionId, legacyRequest);
    if (legacyResponse == null) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': true,
      'timestamp_micros': 1234,
      'payload': jsonDecode(legacyResponse),
    });
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    requests.add(request);
    return _responseFor(sessionId, request);
  }

  String? _responseFor(String sessionId, Map<String, Object?> request) {
    return switch (request['kind']) {
      'terminal.recording_start' => jsonEncode(<String, Object?>{
        'ok': true,
        'max_events': 4096,
        'max_payload_bytes': 8 * 1024 * 1024,
      }),
      'terminal.recording_stop' when overflowOnStop => jsonEncode(
        <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'capacity_exceeded',
            'message': 'recording buffer capacity exceeded',
          },
        },
      ),
      'terminal.recording_stop' => jsonEncode(<String, Object?>{
        'ok': true,
        'recording_ndjson': _recordingFixture(sessionId),
      }),
      _ => null,
    };
  }
}

String _recordingFixture(String sessionId) {
  final records = <Map<String, Object?>>[
    <String, Object?>{
      'record_type': 'metadata',
      'schema_version': 1,
      'session_id': sessionId,
      'created_at_utc': '2026-07-21T00:00:00.000Z',
      'input_policy': 'redact',
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 0,
      'monotonic_offset_micros': 0,
      'event_kind': 'session_started',
      'payload': <String, Object?>{
        'terminal_emulation': 'xterm256',
        'cols': 120,
        'rows': 32,
      },
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 1,
      'monotonic_offset_micros': 10,
      'event_kind': 'pty_output',
      'payload': <String, Object?>{'bytes_base64': 'cmVhZHkNCg=='},
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 2,
      'monotonic_offset_micros': 20,
      'event_kind': 'user_input',
      'payload': <String, Object?>{'byte_length': 6, 'redacted': true},
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 3,
      'monotonic_offset_micros': 30,
      'event_kind': 'resize',
      'payload': <String, Object?>{
        'cols': 100,
        'rows': 30,
        'pixel_width': 1000,
        'pixel_height': 600,
        'cell_width': 10,
        'cell_height': 20,
      },
    },
  ];
  return '${records.map(jsonEncode).join('\n')}\n';
}

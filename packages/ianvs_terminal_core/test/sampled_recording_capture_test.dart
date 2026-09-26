import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

const _id = 'abcdef0123456789abcdef0123456789';
const _path = '/tmp/$_id.trailrec';
SampledCaptureHandle _handle() =>
    SampledCaptureHandle(sessionId: '42', captureId: _id, bundlePath: _path);
SampledCaptureStart _start() => SampledCaptureStart(
  handle: _handle(),
  startedAtUnixMillis: 42,
  title: '部署复盘',
  hostname: 'host-a',
);
Map<String, Object?> _fixture() {
  const relative =
      'native/core/tests/fixtures/recording/sampled_capture_status_v2.json';
  final file = <File>[
    File(relative),
    File('../../$relative'),
  ].firstWhere((f) => f.existsSync());
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

void main() {
  test(
    'starts with the exact native identity and polls after session close',
    () {
      final backend = _Backend();
      final client = SampledRecordingCaptureClient(backend: backend);
      final started = client.start(_start());
      expect(started.phase, SampledCapturePhase.starting);
      expect(started.settled, isFalse);
      expect(backend.requests.single['payload'], _start().toJson());
      backend.reply['phase'] = 'finished';
      backend.reply['settled'] = true;
      expect(client.status(_handle()).settled, isTrue);
      expect(backend.requests.last['session_id'], '42');
      expect(backend.requests.last['payload'], _handle().toJson());
      backend.reply['released'] = true;
      expect(client.release(_handle()).phase, SampledCapturePhase.finished);
      expect(
        backend.requests.last['operation'],
        'terminal.sampled_recording_release',
      );
    },
  );

  test('retry preserves start identity and metadata after a lost response', () {
    final backend = _Backend()..fault = 'missing';
    final client = SampledRecordingCaptureClient(backend: backend);
    expect(
      () => client.start(_start()),
      throwsA(isA<SampledCaptureRequestException>()),
    );
    backend.fault = null;
    client.start(_start());
    expect(backend.requests[0]['payload'], backend.requests[1]['payload']);
    expect(backend.requests.map((r) => r['operation']).toSet(), <String>{
      'terminal.sampled_recording_start',
    });
  });

  for (final fault in <String>[
    'missing',
    'malformed',
    'correlation',
    'throw',
    'outer_error',
    'unknown_capture',
  ]) {
    test('$fault never becomes a settlement acknowledgement', () {
      final backend = _Backend()..fault = fault;
      final client = SampledRecordingCaptureClient(backend: backend);
      expect(
        () => client.start(_start()),
        throwsA(isA<SampledCaptureRequestException>()),
      );
      expect(
        () => client.stop(_handle()),
        throwsA(isA<SampledCaptureRequestException>()),
      );
      expect(
        () => client.status(_handle()),
        throwsA(isA<SampledCaptureRequestException>()),
      );
      expect(
        () => client.release(_handle()),
        throwsA(isA<SampledCaptureRequestException>()),
      );
    });
  }

  final invalid = <String, void Function(Map<String, Object?>)>{
    'schema': (r) => r['schema_version'] = 1,
    'floating schema': (r) => r['schema_version'] = 2.0,
    'capture identity': (r) => r['capture_id'] = '0' * 32,
    'session identity': (r) => r['session_id'] = '43',
    'path identity': (r) => r['bundle_path'] = '/tmp/other.trailrec',
    'extra field': (r) => r['future'] = true,
    'missing field': (r) => r.remove('error'),
    'unknown phase': (r) => r['phase'] = 'gone',
    'active settlement': (r) => r['settled'] = true,
    'string settlement': (r) => r['settled'] = 'true',
    'failure without error': (r) => r['phase'] = 'failed',
    'negative count': (r) => (r['written']! as Map)['record_count'] = -1,
    'floating count': (r) => (r['written']! as Map)['record_count'] = 0.0,
    'inconsistent counts': (r) => (r['written']! as Map)['record_count'] = 5,
    'durable ahead of written': (r) =>
        (r['committed']! as Map)['duration_micros'] = 1,
    'finished before durable': (r) {
      r['phase'] = 'finished';
      (r['written']! as Map)['duration_micros'] = 10;
    },
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} from the shared native status contract', () {
      final backend = _Backend();
      entry.value(backend.reply);
      final client = SampledRecordingCaptureClient(backend: backend);
      expect(
        () => client.status(_handle()),
        throwsA(isA<SampledCaptureRequestException>()),
      );
    });
  }

  test('failed capture still waits for pending writes to drain', () async {
    final backend = _Backend();
    backend.reply['phase'] = 'failed';
    backend.reply['error'] = 'queue exhausted';
    final client = SampledRecordingCaptureClient(backend: backend);
    expect(client.status(_handle()).settled, isFalse);
    backend.beforeReply = () {
      if (backend.requests.length >= 3) backend.reply['settled'] = true;
    };
    final result = await client.waitUntilSettled(
      _handle(),
      pollInterval: const Duration(milliseconds: 1),
    );
    expect(result.phase, SampledCapturePhase.failed);
    expect(result.settled, isTrue);
    expect(backend.requests.length, 3);
    expect(
      backend.requests.every(
        (r) => r['operation'] == 'terminal.sampled_recording_status',
      ),
      isTrue,
    );
  });

  test('timeout and cancelling a wait preserve the recording task', () async {
    final backend = _Backend();
    final client = SampledRecordingCaptureClient(backend: backend);
    await expectLater(
      client.waitUntilSettled(
        _handle(),
        timeout: const Duration(milliseconds: 5),
        pollInterval: const Duration(milliseconds: 1),
      ),
      throwsA(isA<SampledCaptureRequestException>()),
    );
    await expectLater(
      client.waitUntilSettled(_handle(), isCancelled: () => true),
      throwsA(isA<SampledCaptureRequestException>()),
    );
    expect(
      backend.requests.every(
        (r) => r['operation'] == 'terminal.sampled_recording_status',
      ),
      isTrue,
    );
  });

  test('release requires an explicit settled and released acknowledgement', () {
    final backend = _Backend();
    final client = SampledRecordingCaptureClient(backend: backend);
    expect(
      () => client.release(_handle()),
      throwsA(isA<SampledCaptureRequestException>()),
    );
    backend.reply['released'] = true;
    expect(
      () => client.release(_handle()),
      throwsA(isA<SampledCaptureRequestException>()),
    );
    backend.reply['phase'] = 'interrupted';
    backend.reply['settled'] = true;
    expect(client.release(_handle()).settled, isTrue);
  });

  test(
    'invalid paths, identifiers and metadata are rejected before dispatch',
    () {
      for (final path in <String>[
        'relative/$_id.trailrec',
        '/tmp/../$_id.trailrec',
        '/tmp/$_id.ndjson',
        '/tmp/$_id.trailrec/',
      ]) {
        expect(
          () => SampledCaptureHandle(
            sessionId: '42',
            captureId: _id,
            bundlePath: path,
          ),
          throwsArgumentError,
        );
      }
      for (final session in <String>['0', '-1', '01', '18446744073709551616']) {
        expect(
          () => SampledCaptureHandle(
            sessionId: session,
            captureId: _id,
            bundlePath: _path,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => SampledCaptureStart(
          handle: _handle(),
          startedAtUnixMillis: -1,
          title: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => SampledCaptureStart(
          handle: _handle(),
          startedAtUnixMillis: 42,
          title: '雪' * 3000,
        ),
        throwsArgumentError,
      );
    },
  );
}

final class _Backend implements PtySessionRequestV1Backend {
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final Map<String, Object?> reply = _fixture();
  String? fault;
  void Function()? beforeReply;

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
    requests.add(request);
    beforeReply?.call();
    if (fault == 'missing') return null;
    if (fault == 'malformed') return '{';
    if (fault == 'throw') throw StateError('transport unavailable');
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': fault == 'correlation' ? 'wrong' : request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': fault != 'outer_error',
      'timestamp_micros': 1,
      if (fault == 'outer_error')
        'error': <String, Object?>{
          'code': 'native_failure',
          'message': 'unknown',
        },
      if (fault != 'outer_error')
        'payload': fault == 'unknown_capture'
            ? <String, Object?>{
                'ok': false,
                'error': <String, Object?>{
                  'code': 'unknown_capture',
                  'message': 'unknown',
                },
              }
            : reply,
    });
  }
}

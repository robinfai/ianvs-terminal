import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  group('TerminalLiveRecorder', () {
    test('starts native capture and decodes the stopped current recording', () {
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

    test('uses Session Request v1', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(
        backend: backend,
        utcNow: () => DateTime.utc(2026, 7, 21),
      );

      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      recorder.stop('42');

      expect(backend.requests, hasLength(2));
      expect(
        backend.v1Requests.map((request) => request['operation']),
        <String>['terminal.recording_start', 'terminal.recording_stop'],
      );
      expect(
        (backend.v1Requests.first['payload']! as Map)['input_policy'],
        'redact',
      );
    });

    for (final responseFault in <String>[
      'missing',
      'malformed',
      'correlation',
    ]) {
      test(
        'start $responseFault response retains unknown native ownership',
        () {
          final backend = _RecordingRequestBackend()
            ..missingStartResponse = responseFault == 'missing'
            ..malformedStartResponse = responseFault == 'malformed'
            ..mismatchedStartCorrelation = responseFault == 'correlation';
          final recorder = TerminalLiveRecorder(backend: backend);

          final outcome = recorder.startWithOutcome(
            '42',
            inputPolicy: TerminalRecordingInputPolicy.redact,
          );

          expect(
            outcome.disposition,
            TerminalRecordingStartDisposition.terminationUnknown,
          );
          expect(outcome.result, isNull);
          expect(outcome.error, isNotNull);
          expect(recorder.isRecording('42'), isTrue);
          expect(backend.nativeStartDispatchCount, 1);
        },
      );
    }

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

    test('prepareStop returns only a bounded native worker handle', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      final job = recorder.prepareStop(
        '42',
        handoffDirectory: '/private/tmp/ianvs-recording-handoff-current-test',
        jobId: '0123456789abcdef0123456789abcdef',
      );

      expect(job.sessionId, '42');
      expect(job.jobId, '0123456789abcdef0123456789abcdef');
      expect(job.handoffPath, endsWith('${job.jobId}.ndjson'));
      expect(job.errorPath, endsWith('${job.jobId}.ndjson.error.json'));
      expect(recorder.isRecording('42'), isFalse);
      expect(backend.requests.last['kind'], 'terminal.recording_stop_prepare');
      expect(backend.requests.last['job_id'], job.jobId);
    });

    for (final entry in <({String fault, String status})>[
      (fault: 'missing', status: 'running'),
      (fault: 'malformed', status: 'ready'),
      (fault: 'correlation', status: 'failed'),
    ]) {
      test(
        'prepare ${entry.fault} response settles from ${entry.status} status',
        () {
          final backend = _RecordingRequestBackend()
            ..prepareResponseFault = entry.fault
            ..finalizeState = entry.status;
          final recorder = TerminalLiveRecorder(backend: backend);
          recorder.start(
            '42',
            inputPolicy: TerminalRecordingInputPolicy.redact,
          );
          const job = TerminalRecordingFinalizeJob(
            sessionId: '42',
            jobId: '0123456789abcdef0123456789abcdef',
            handoffPath:
                '/private/tmp/ianvs-recording-handoff-current-test/'
                '.ianvs-recording-handoff-'
                '0123456789abcdef0123456789abcdef.ndjson',
            errorPath:
                '/private/tmp/ianvs-recording-handoff-current-test/'
                '.ianvs-recording-handoff-'
                '0123456789abcdef0123456789abcdef.ndjson.error.json',
          );

          final outcome = recorder.prepareStopWithOutcome(
            '42',
            handoffDirectory:
                '/private/tmp/ianvs-recording-handoff-current-test',
            jobId: job.jobId,
            expectedJob: job,
          );

          expect(outcome.isAcknowledged, isTrue);
          expect(outcome.job.jobId, job.jobId);
          expect(outcome.status?.state.name, entry.status);
          expect(recorder.isRecording('42'), isFalse);
          expect(backend.nativePrepareDispatchCount, 1);
          expect(backend.statusProbeCount, 1);
        },
      );
    }

    test('uncertain prepare re-probes the same job without redispatch', () {
      final backend = _RecordingRequestBackend()
        ..prepareResponseFault = 'missing'
        ..finalizeState = 'unknown';
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      const job = TerminalRecordingFinalizeJob(
        sessionId: '42',
        jobId: '0123456789abcdef0123456789abcdef',
        handoffPath:
            '/shared/.ianvs-recording-handoff-'
            '0123456789abcdef0123456789abcdef.ndjson',
        errorPath:
            '/shared/.ianvs-recording-handoff-'
            '0123456789abcdef0123456789abcdef.ndjson.error.json',
      );

      final uncertain = recorder.prepareStopWithOutcome(
        '42',
        handoffDirectory: '/shared',
        jobId: job.jobId,
        expectedJob: job,
      );

      expect(
        uncertain.disposition,
        TerminalRecordingPrepareDisposition.terminationUnknown,
      );
      expect(recorder.isRecording('42'), isTrue);
      expect(backend.nativePrepareDispatchCount, 1);
      expect(backend.statusProbeCount, 1);

      backend.finalizeState = 'running';
      final resolved = recorder.prepareStopWithOutcome(
        '42',
        handoffDirectory: '/shared',
        jobId: job.jobId,
        expectedJob: job,
      );

      expect(resolved.isAcknowledged, isTrue);
      expect(resolved.status?.state, TerminalRecordingFinalizeJobState.running);
      expect(recorder.isRecording('42'), isFalse);
      expect(backend.nativePrepareDispatchCount, 1);
      expect(backend.statusProbeCount, 2);
    });

    test(
      'prepare unknown plus not_active and unknown status cancels safely',
      () {
        final backend = _RecordingRequestBackend()
          ..prepareResponseFault = 'missing'
          ..finalizeState = 'unknown'
          ..cancelIsNotActive = true;
        final recorder = TerminalLiveRecorder(backend: backend);
        recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

        final prepare = recorder.prepareStopWithOutcome(
          '42',
          handoffDirectory: '/shared',
          jobId: '0123456789abcdef0123456789abcdef',
        );
        final cancel = recorder.cancel('42');

        expect(
          prepare.disposition,
          TerminalRecordingPrepareDisposition.terminationUnknown,
        );
        expect(cancel.isAcknowledged, isTrue);
        expect(cancel.isDetachedPrepareConfirmed, isFalse);
        expect(recorder.isRecording('42'), isFalse);
        expect(backend.nativePrepareDispatchCount, 1);
      },
    );

    test('not_active cancel exposes a concurrently confirmed detached job', () {
      final backend = _RecordingRequestBackend()
        ..prepareResponseFault = 'missing'
        ..finalizeState = 'unknown'
        ..cancelIsNotActive = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      recorder.prepareStopWithOutcome(
        '42',
        handoffDirectory: '/shared',
        jobId: '0123456789abcdef0123456789abcdef',
      );
      backend.finalizeState = 'running';

      final cancel = recorder.cancel('42');

      expect(cancel.isAcknowledged, isFalse);
      expect(cancel.isDetachedPrepareConfirmed, isTrue);
      expect(
        cancel.detachedPrepareStatus?.state,
        TerminalRecordingFinalizeJobState.running,
      );
      expect(recorder.isRecording('42'), isFalse);
    });

    test('not_active cancel with unavailable status retains ownership', () {
      final backend = _RecordingRequestBackend()
        ..prepareResponseFault = 'missing'
        ..throwOnStatus = true
        ..cancelIsNotActive = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      recorder.prepareStopWithOutcome(
        '42',
        handoffDirectory: '/shared',
        jobId: '0123456789abcdef0123456789abcdef',
      );

      final cancel = recorder.cancel('42');

      expect(
        cancel.disposition,
        TerminalRecordingCancelDisposition.terminationUnknown,
      );
      expect(cancel.isDetachedPrepareConfirmed, isFalse);
      expect(recorder.isRecording('42'), isTrue);
    });

    test('prepare rejects a mismatched expected path before dispatch', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      const mismatched = TerminalRecordingFinalizeJob(
        sessionId: '42',
        jobId: '0123456789abcdef0123456789abcdef',
        handoffPath: '/outside/forged.ndjson',
        errorPath: '/outside/forged.ndjson.error.json',
      );

      expect(
        () => recorder.prepareStopWithOutcome(
          '42',
          handoffDirectory: '/shared',
          jobId: mismatched.jobId,
          expectedJob: mismatched,
        ),
        throwsArgumentError,
      );
      expect(backend.nativePrepareDispatchCount, 0);
      expect(recorder.isRecording('42'), isTrue);
    });

    test('probes and consumes detached finalize worker terminal status', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
      final job = recorder.prepareStop(
        '42',
        handoffDirectory: '/private/tmp/ianvs-recording-handoff-current-test',
        jobId: '0123456789abcdef0123456789abcdef',
      );
      backend.finalizeState = 'failed';

      final status = recorder.probeFinalizeJobStatus(job);

      expect(status.state, TerminalRecordingFinalizeJobState.failed);
      expect(status.isTerminal, isTrue);
      expect(status.errorCode, 'serialize_failed');
      expect(status.message, 'recording serialization failed');
      expect(
        backend.requests.last,
        containsPair('kind', 'terminal.recording_finalize_status'),
      );
      expect(backend.requests.last['consume_terminal'], isTrue);
    });

    test('status transport failure is transient rather than terminal', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(backend: backend);
      const job = TerminalRecordingFinalizeJob(
        sessionId: '42',
        jobId: '0123456789abcdef0123456789abcdef',
        handoffPath: '/private/tmp/handoff.ndjson',
        errorPath: '/private/tmp/handoff.ndjson.error.json',
      );
      backend.throwOnStatus = true;

      final status = recorder.probeFinalizeJobStatus(job);

      expect(status.state, TerminalRecordingFinalizeJobState.unavailable);
      expect(status.isTerminal, isFalse);
      expect(status.error, isA<StateError>());
    });

    test('rejected handoff keeps the native recording active for retry', () {
      final backend = _RecordingRequestBackend()..rejectPrepare = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      expect(
        () => recorder.prepareStop(
          '42',
          handoffDirectory: '/shared',
          jobId: '0123456789abcdef0123456789abcdef',
        ),
        throwsA(
          isA<TerminalRecordingBackendException>().having(
            (error) => error.code,
            'code',
            TerminalRecordingBackendErrorCode.invalidHandoff,
          ),
        ),
      );
      expect(recorder.isRecording('42'), isTrue);
    });

    for (final entry in <String, TerminalRecordingBackendErrorCode>{
      'capacity_exceeded': TerminalRecordingBackendErrorCode.capacityExceeded,
      'finalize_capacity_exceeded':
          TerminalRecordingBackendErrorCode.finalizeCapacityExceeded,
      'finalize_worker_spawn_failed':
          TerminalRecordingBackendErrorCode.finalizeWorkerSpawnFailed,
    }.entries) {
      test('${entry.key} is typed and keeps capture active for retry', () {
        final backend = _RecordingRequestBackend()
          ..prepareErrorCode = entry.key;
        final recorder = TerminalLiveRecorder(backend: backend);
        recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

        expect(
          () => recorder.prepareStop(
            '42',
            handoffDirectory: '/shared',
            jobId: '0123456789abcdef0123456789abcdef',
          ),
          throwsA(
            isA<TerminalRecordingBackendException>().having(
              (error) => error.code,
              'code',
              entry.value,
            ),
          ),
        );
        expect(recorder.isRecording('42'), isTrue);
        expect(recorder.cancel('42').isAcknowledged, isTrue);
        expect(recorder.isRecording('42'), isFalse);

        recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);
        expect(recorder.isRecording('42'), isTrue);
      });
    }

    test('explicit native start rejection does not claim ownership', () {
      final backend = _RecordingRequestBackend()..rejectStart = true;
      final recorder = TerminalLiveRecorder(backend: backend);

      final outcome = recorder.startWithOutcome(
        '42',
        inputPolicy: TerminalRecordingInputPolicy.redact,
      );

      expect(outcome.disposition, TerminalRecordingStartDisposition.rejected);
      expect(outcome.error, isA<TerminalRecordingBackendException>());
      expect(recorder.isRecording('42'), isFalse);
    });

    test('cancel removes ownership only after a native acknowledgment', () {
      final backend = _RecordingRequestBackend();
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      final outcome = recorder.cancel('42');

      expect(
        outcome.disposition,
        TerminalRecordingCancelDisposition.acknowledged,
      );
      expect(outcome.isAcknowledged, isTrue);
      expect(recorder.isRecording('42'), isFalse);
    });

    test('rejected cancel retains native recording ownership', () {
      final backend = _RecordingRequestBackend()..rejectCancel = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      final outcome = recorder.cancel('42');

      expect(outcome.disposition, TerminalRecordingCancelDisposition.rejected);
      expect(outcome.error, isA<TerminalRecordingBackendException>());
      expect(outcome.isAcknowledged, isFalse);
      expect(recorder.isRecording('42'), isTrue);
    });

    test('cancel not_active is an idempotent definitive acknowledgment', () {
      final backend = _RecordingRequestBackend()..cancelIsNotActive = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      final outcome = recorder.cancel('42');

      expect(outcome.isAcknowledged, isTrue);
      expect(recorder.isRecording('42'), isFalse);
    });

    test('cancel transport failure retains native recording ownership', () {
      final backend = _RecordingRequestBackend()..throwOnCancel = true;
      final recorder = TerminalLiveRecorder(backend: backend);
      recorder.start('42', inputPolicy: TerminalRecordingInputPolicy.redact);

      final outcome = recorder.cancel('42');

      expect(
        outcome.disposition,
        TerminalRecordingCancelDisposition.terminationUnknown,
      );
      expect(outcome.error, isA<StateError>());
      expect(outcome.isAcknowledged, isFalse);
      expect(recorder.isRecording('42'), isTrue);
    });
  });
}

final class _RecordingRequestBackend implements PtySessionRequestV1Backend {
  _RecordingRequestBackend();

  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> v1Requests = <Map<String, Object?>>[];
  bool overflowOnStop = false;
  bool rejectPrepare = false;
  String? prepareErrorCode;
  bool rejectCancel = false;
  bool cancelIsNotActive = false;
  bool throwOnCancel = false;
  bool throwOnStatus = false;
  bool missingStartResponse = false;
  bool malformedStartResponse = false;
  bool mismatchedStartCorrelation = false;
  String? prepareResponseFault;
  bool rejectStart = false;
  String finalizeState = 'running';
  int nativeStartDispatchCount = 0;
  int nativePrepareDispatchCount = 0;
  int statusProbeCount = 0;

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
    v1Requests.add(request);
    final operation = request['operation'];
    if (operation == 'terminal.recording_start') {
      nativeStartDispatchCount += 1;
    } else if (operation == 'terminal.recording_stop_prepare') {
      nativePrepareDispatchCount += 1;
    } else if (operation == 'terminal.recording_finalize_status') {
      statusProbeCount += 1;
    }
    if (operation == 'terminal.recording_start' && missingStartResponse) {
      return null;
    }
    if (operation == 'terminal.recording_start' && malformedStartResponse) {
      return '{malformed';
    }
    if (operation == 'terminal.recording_stop_prepare' &&
        prepareResponseFault == 'missing') {
      return null;
    }
    if (operation == 'terminal.recording_stop_prepare' &&
        prepareResponseFault == 'malformed') {
      return '{malformed';
    }
    final payload = (request['payload']! as Map).cast<String, Object?>();
    final currentPayload = <String, Object?>{
      'kind': request['operation'],
      ...payload,
    };
    requests.add(currentPayload);
    final configuredPayload = _responseFor(sessionId, currentPayload);
    if (configuredPayload == null) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id':
          (operation == 'terminal.recording_start' &&
                  mismatchedStartCorrelation) ||
              (operation == 'terminal.recording_stop_prepare' &&
                  prepareResponseFault == 'correlation')
          ? 'wrong-correlation'
          : request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': true,
      'timestamp_micros': 1234,
      'payload': jsonDecode(configuredPayload),
    });
  }

  String? _responseFor(String sessionId, Map<String, Object?> request) {
    return switch (request['kind']) {
      'terminal.recording_start' when rejectStart => jsonEncode(
        const <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'native_failure',
            'message': 'native recording start rejected',
          },
        },
      ),
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
      'terminal.recording_stop_prepare' when rejectPrepare => jsonEncode(
        const <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'invalid_handoff',
            'message': 'recording handoff directory is invalid',
          },
        },
      ),
      'terminal.recording_stop_prepare' when prepareErrorCode != null =>
        jsonEncode(<String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': prepareErrorCode,
            'message': 'native finalize admission failed',
          },
        }),
      'terminal.recording_stop_prepare' => () {
        final jobId = request['job_id']! as String;
        final directory = request['handoff_directory']! as String;
        final path = '$directory/.ianvs-recording-handoff-$jobId.ndjson';
        return jsonEncode(<String, Object?>{
          'ok': true,
          'job_id': jobId,
          'handoff_path': path,
          'error_path': '$path.error.json',
        });
      }(),
      'terminal.recording_cancel' when throwOnCancel => throw StateError(
        'cancel transport terminated before acknowledgment',
      ),
      'terminal.recording_cancel' when rejectCancel => jsonEncode(
        const <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'native_failure',
            'message': 'native cancellation was rejected',
          },
        },
      ),
      'terminal.recording_cancel' when cancelIsNotActive => jsonEncode(
        const <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'not_active',
            'message': 'no recording is active for this session',
          },
        },
      ),
      'terminal.recording_cancel' => jsonEncode(const <String, Object?>{
        'ok': true,
      }),
      'terminal.recording_finalize_status' when throwOnStatus =>
        throw StateError('status transport unavailable'),
      'terminal.recording_finalize_status' => jsonEncode(<String, Object?>{
        'ok': true,
        'state': finalizeState,
        if (finalizeState == 'failed')
          'error': const <String, Object?>{
            'code': 'serialize_failed',
            'message': 'recording serialization failed',
          },
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

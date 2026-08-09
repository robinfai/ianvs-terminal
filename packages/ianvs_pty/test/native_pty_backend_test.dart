import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  test('native pty backend exposes the planned low-level API', () {
    final PtySessionBackend backend = NativePtyBackend.fromBindings(
      _NoopPtyBindings(),
    );

    expect(backend.ping(), 42);
    expect(backend.createSession('{"launch":{"program":"/bin/sh"}}'), '1');
    backend.resizeSession(
      '1',
      cols: 80,
      rows: 24,
      pixelWidth: 800,
      pixelHeight: 600,
      cellWidth: 10,
      cellHeight: 25,
    );
    backend.writeInput('1', const [0x41]);
    backend.scrollViewport('1', 3);
    backend.scrollViewportTo('1', 4);
    expect(backend.takeFrameDiffJson('1'), '{"rows":[]}');
    final diagnosticsBackend = backend as PtySessionDiagnosticsBackend;
    expect(diagnosticsBackend.takeDiagnosticsJson('1', 'frame'), isNull);
    expect(diagnosticsBackend.takeDiagnosticsJson('1', 'session'), isNull);
    expect(backend.pollEvents('1'), isEmpty);
    backend.closeSession('1');
  });

  test('native pty backend exposes ordered protocol replies explicitly', () {
    final bindings = _ProtocolReplyPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final protocolBackend = backend as PtyProtocolReplyBackend;

    expect(protocolBackend.supportsProtocolReplies, isTrue);
    protocolBackend.writeProtocolReply('1', const <int>[0x1b, 0x5b, 0x52]);

    expect(bindings.replies, hasLength(1));
    expect(bindings.replies.single.$1, 1);
    expect(bindings.replies.single.$2, <int>[0x1b, 0x5b, 0x52]);
  });

  test('native pty backend reports unavailable ordered protocol replies', () {
    final backend = NativePtyBackend.fromBindings(_NoopPtyBindings());
    final protocolBackend = backend as PtyProtocolReplyBackend;

    expect(protocolBackend.supportsProtocolReplies, isFalse);
    expect(
      () => protocolBackend.writeProtocolReply('1', const <int>[0x1b]),
      throwsUnsupportedError,
    );
  });

  test(
    'native pty backend surfaces optional debug bindings when available',
    () {
      final PtySessionBackend backend = NativePtyBackend.fromBindings(
        _NoopDebugPtyBindings(),
      );

      final diagnosticsBackend = backend as PtySessionDiagnosticsBackend;
      expect(
        diagnosticsBackend.takeDiagnosticsJson('1', 'frame'),
        '{"rows_scanned":2}',
      );
      expect(
        diagnosticsBackend.takeDiagnosticsJson('1', 'session'),
        '{"bytes_read":4}',
      );
    },
  );

  test('native pty backend prefers typed Diagnostic Event v1 bindings', () {
    final bindings = _DiagnosticEventV1PtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final diagnosticBackend = backend as PtySessionDiagnosticEventV1Backend;

    expect(diagnosticBackend.supportsDiagnosticEventV1, isTrue);
    final event = diagnosticBackend.takeDiagnosticEventV1('1', 'frame_stats');

    expect(event, isNotNull);
    expect(event!.sessionId, '1');
    expect(event.name, 'frame_stats');
    expect(event.payload['rows_scanned'], 9);
    expect(bindings.v1Calls, 1);
    expect(bindings.legacyCalls, 0);
  });

  test('native pty backend forwards protobuf frame bytes when supported', () {
    final backend =
        NativePtyBackend.fromBindings(_ProtobufFramePtyBindings())
            as PtySessionProtobufFrameBackend;

    expect(backend.supportsProtobufFrameDiffs, isTrue);
    final bytes = backend.takeFrameDiffProtobuf('1');

    expect(bytes, <int>[8, 1, 18, 4]);
  });

  test('native pty backend forwards Frame Packet v1 acknowledgements', () {
    final bindings = _FramePacketV1PtyBindings();
    final backend =
        NativePtyBackend.fromBindings(bindings)
            as PtySessionFramePacketV1Backend;

    expect(backend.supportsFramePacketV1, isTrue);
    expect(backend.takeFramePacketV1Protobuf('1', afterSequence: null), <int>[
      10,
      1,
    ]);
    expect(backend.takeFramePacketV1Protobuf('1', afterSequence: 7), <int>[
      10,
      1,
    ]);
    expect(bindings.calls, <(int, int?)>[(1, null), (1, 7)]);
  });

  test('native pty backend falls back when refresh hints are unavailable', () {
    final backend =
        NativePtyBackend.fromBindings(_NoopPtyBindings())
            as PtySessionRefreshHintBackend;

    expect(backend.supportsRefreshHints, isFalse);
    expect(PtyRefreshHintFlags.none, 0);
    expect(PtyRefreshHintFlags.frameDirty, 1);
    expect(backend.refreshHintFlags('1'), PtyRefreshHintFlags.none);
  });

  test('native pty backend decodes optional runtime capabilities', () {
    final backend =
        NativePtyBackend.fromBindings(_CapabilityPtyBindings())
            as PtyRuntimeCapabilityBackend;

    final capabilities = backend.runtimeCapabilities;

    expect(capabilities, isNotNull);
    expect(capabilities!.schemaVersion, 1);
    expect(capabilities.supports('frame.protobuf.v1'), isTrue);
  });

  test('native pty backend keeps old bindings usable without capabilities', () {
    final backend = NativePtyBackend.fromBindings(_NoopPtyBindings());

    expect(
      (backend as PtyRuntimeCapabilityBackend).runtimeCapabilities,
      isNull,
    );
    expect(backend.ping(), 42);
    expect(backend.createSession('{}'), '1');
  });

  test('native pty backend routes live and replay SessionConfig v1', () {
    final bindings = _SessionConfigV1PtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final liveConfigBackend = backend as PtySessionConfigV1Backend;
    final replayConfigBackend = backend as PtyReplaySessionConfigV1Backend;

    expect(liveConfigBackend.supportsSessionConfigV1, isTrue);
    expect(replayConfigBackend.supportsReplaySessionConfigV1, isTrue);
    expect(liveConfigBackend.createSessionV1('{"schema_version":1}'), '51');
    expect(
      replayConfigBackend.createReplaySessionV1('{"schema_version":1}'),
      '52',
    );
    expect(bindings.liveV1Calls, 1);
    expect(bindings.replayV1Calls, 1);
    expect(bindings.legacyCreateCalls, 0);
  });

  test('native pty backend exposes an explicit SessionConfig v1 fallback', () {
    final bindings = _LegacySessionConfigPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final configBackend = backend as PtySessionConfigV1Backend;

    expect(configBackend.supportsSessionConfigV1, isFalse);
    expect(
      () => configBackend.createSessionV1('{"schema_version":1}'),
      throwsUnsupportedError,
    );
    expect(backend.createSession('{"id":"legacy"}'), '1');
    expect(bindings.legacyCreateCalls, 1);
  });

  test('native pty backend prefers Runtime Event Envelope v1', () {
    final bindings = _RuntimeEventPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = backend.createSession('{}');

    final events = backend.pollEvents(sessionId);

    expect(bindings.envelopePollCalls, 1);
    expect(bindings.legacyPollCalls, 0);
    expect(events.map((event) => event.kind), <String>[
      'started',
      'future_event',
    ]);
    expect(events.map((event) => event.sequence), <int>[0, 1]);
    expect(events.every((event) => event.wireSchemaVersion == 1), isTrue);
  });

  test('native pty backend falls back to legacy event polling', () {
    final bindings = _LegacyEventPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = backend.createSession('{}');

    final events = backend.pollEvents(sessionId);

    expect(bindings.legacyPollCalls, 1);
    expect(events.map((event) => event.kind), <String>['legacy_started']);
    expect(events.single.sequence, isNull);
    expect(events.single.wireSchemaVersion, isNull);
  });

  test(
    'native pty backend delivers a typed gap diagnostic before survivors',
    () {
      final bindings = _RuntimeEventPtyBindings(sequences: const <int>[0, 2]);
      final backend = NativePtyBackend.fromBindings(
        bindings,
        emitRuntimeEventGapDiagnostics: true,
      );
      final sessionId = backend.createSession('{}');

      final events = backend.pollEvents(sessionId);

      expect(events.map((event) => event.kind), <String>[
        'runtime_event_gap',
        'started',
        'future_event',
      ]);
      expect(events.skip(1).map((event) => event.sequence), <int>[0, 2]);
      final diagnostic = events.first as PtyRuntimeEventGapDiagnostic;
      expect(diagnostic.expectedSequence, 0);
      expect(diagnostic.nextSequence, 3);
      expect(diagnostic.droppedCount, 1);
      expect(diagnostic.survivingEventCount, 2);
      expect(diagnostic.sequence, isNull);
      expect(diagnostic.payload, <String, Object?>{
        'code': 'event_sequence_gap',
        'expectedSequence': 0,
        'nextSequence': 3,
        'droppedCount': 1,
        'survivingEventCount': 2,
      });
    },
  );

  test('native pty backend preserves legacy gap exception by default', () {
    final bindings = _RuntimeEventPtyBindings(sequences: const <int>[0, 2]);
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = backend.createSession('{}');

    expect(
      () => backend.pollEvents(sessionId),
      throwsA(
        isA<PtyRuntimeContractException>()
            .having((error) => error.code, 'code', 'event_sequence_gap')
            .having((error) => error.path, 'path', r'$.messages'),
      ),
    );
  });

  test(
    'native pty backend rejects cross-poll replay without moving its cursor',
    () {
      final bindings = _SequencedRuntimeEventPtyBindings(<List<int>>[
        <int>[0, 1],
        <int>[1],
        <int>[2],
      ]);
      final backend = NativePtyBackend.fromBindings(bindings);
      final sessionId = backend.createSession('{}');

      expect(
        backend.pollEvents(sessionId).map((event) => event.sequence),
        <int>[0, 1],
      );
      expect(
        () => backend.pollEvents(sessionId),
        throwsA(
          isA<PtyRuntimeContractException>()
              .having((error) => error.code, 'code', 'event_sequence_reordered')
              .having((error) => error.path, 'path', r'$.messages[0].sequence'),
        ),
      );
      expect(
        backend.pollEvents(sessionId).map((event) => event.sequence),
        <int>[2],
      );
    },
  );

  test(
    'native pty backend rejects a backwards batch cursor without moving it',
    () {
      final bindings = _SequencedRuntimeEventPtyBindings(
        <List<int>>[
          <int>[0],
          const <int>[],
          <int>[1],
        ],
        nextSequences: const <int>[1, 0, 2],
      );
      final backend = NativePtyBackend.fromBindings(bindings);
      final sessionId = backend.createSession('{}');

      expect(backend.pollEvents(sessionId).single.sequence, 0);
      expect(
        () => backend.pollEvents(sessionId),
        throwsA(
          isA<PtyRuntimeContractException>()
              .having((error) => error.code, 'code', 'event_sequence_reordered')
              .having((error) => error.path, 'path', r'$.next_sequence'),
        ),
      );
      expect(backend.pollEvents(sessionId).single.sequence, 1);
    },
  );

  test('native pty backend rejects reordered messages within one poll', () {
    final bindings = _SequencedRuntimeEventPtyBindings(<List<int>>[
      <int>[0, 2, 1],
    ]);
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = backend.createSession('{}');

    expect(
      () => backend.pollEvents(sessionId),
      throwsA(
        isA<PtyRuntimeContractException>()
            .having((error) => error.code, 'code', 'event_sequence_reordered')
            .having((error) => error.path, 'path', r'$.messages[2].sequence'),
      ),
    );
  });

  test('native pty backend forwards the complete refresh hint bitmask', () {
    final bindings = _RefreshHintPtyBindings(0x80000001);
    final backend =
        NativePtyBackend.fromBindings(bindings) as PtySessionRefreshHintBackend;

    expect(backend.supportsRefreshHints, isTrue);
    expect(backend.refreshHintFlags('7'), 0x80000001);
    expect(bindings.lastSessionId, 7);
  });

  test('native pty backend forwards headless replay operations', () {
    final bindings = _ReplayPtyBindings();
    final backend =
        NativePtyBackend.fromBindings(bindings) as PtyReplaySessionBackend;

    final sessionId = backend.createReplaySession('{"id":"fixture"}');
    backend.replayOutput(sessionId, const <int>[0x41, 0x42]);
    backend.replayExit(sessionId, exitCode: 7);

    expect(sessionId, '41');
    expect(bindings.createdConfig, '{"id":"fixture"}');
    expect(bindings.outputCalls, hasLength(1));
    expect(bindings.outputCalls.single.$1, 41);
    expect(bindings.outputCalls.single.$2, <int>[0x41, 0x42]);
    expect(bindings.exitCalls, <(int, int?)>[(41, 7)]);
  });

  test('native pty backend forwards optional replay checkpoints', () {
    final bindings = _ReplayCheckpointPtyBindings();
    final nativeBackend = NativePtyBackend.fromBindings(bindings);
    final replayBackend = nativeBackend as PtyReplaySessionBackend;
    final checkpointBackend = nativeBackend as PtyReplayCheckpointBackend;
    final sessionId = replayBackend.createReplaySession('{}');

    expect(checkpointBackend.supportsReplayCheckpoints, isTrue);
    final checkpointId = checkpointBackend.captureReplayCheckpoint(sessionId);
    expect(checkpointId, 71);
    expect(
      checkpointBackend.restoreReplayCheckpoint(sessionId, checkpointId),
      isTrue,
    );
    expect(bindings.captureCalls, <int>[41]);
    expect(bindings.restoreCalls, <(int, int)>[(41, 71)]);
  });

  test('native pty backend reports unavailable replay symbols', () {
    final backend =
        NativePtyBackend.fromBindings(_NoopPtyBindings())
            as PtyReplaySessionBackend;

    expect(() => backend.createReplaySession('{}'), throwsUnsupportedError);
  });

  test('native pty backend validates refresh hint session ids', () {
    final backend =
        NativePtyBackend.fromBindings(_RefreshHintPtyBindings(1))
            as PtySessionRefreshHintBackend;

    expect(() => backend.refreshHintFlags('invalid'), throwsArgumentError);
  });

  test('native pty backend forwards hints for created session ids', () {
    final bindings = _RefreshHintPtyBindings(1);
    final backend = NativePtyBackend.fromBindings(bindings);
    final refreshHints = backend as PtySessionRefreshHintBackend;

    final sessionId = backend.createSession('{}');

    expect(refreshHints.refreshHintFlags(sessionId), 1);
    expect(refreshHints.refreshHintFlags(sessionId), 1);
    expect(bindings.refreshHintCalls, 2);

    backend.closeSession(sessionId);
    expect(() => refreshHints.refreshHintFlags('invalid'), throwsArgumentError);
  });

  test('native pty backend retains cached ids when native close fails', () {
    final bindings = _CloseFailingRefreshHintPtyBindings(1);
    final backend = NativePtyBackend.fromBindings(bindings);
    final refreshHints = backend as PtySessionRefreshHintBackend;
    final sessionId = backend.createSession('{}');

    expect(
      () => backend.closeSession(sessionId),
      throwsA(isA<PtyNativeCallException>()),
    );

    expect(refreshHints.refreshHintFlags(sessionId), 1);
    expect(bindings.lastSessionId, 1);
  });

  test(
    'native pty backend forwards generic JSON requests through bindings',
    () {
      final bindings = _RequestRecordingPtyBindings();
      final backend = NativePtyBackend.fromBindings(bindings);

      final requestBackend = backend as PtySessionJsonRequestBackend;
      final response = requestBackend.requestSessionJson(
        '7',
        '{"kind":"opaque.echo","payload":"hello"}',
      );

      expect(response, '{"ok":true}');
      expect(bindings.lastSessionId, 7);
      expect(
        bindings.lastRequestJson,
        '{"kind":"opaque.echo","payload":"hello"}',
      );
    },
  );

  test('native pty backend routes Session Request/Response v1 explicitly', () {
    final bindings = _SessionRequestV1PtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final requestBackend = backend as PtySessionRequestV1Backend;

    expect(requestBackend.supportsSessionRequestV1, isTrue);
    final response = requestBackend.requestSessionV1Json(
      '7',
      '{"schema_version":1}',
    );

    expect(response, '{"schema_version":1}');
    expect(bindings.lastSessionId, 7);
    expect(bindings.lastRequestJson, '{"schema_version":1}');
    expect(bindings.legacyRequestCalls, 0);

    final fallback =
        NativePtyBackend.fromBindings(_NoopPtyBindings())
            as PtySessionRequestV1Backend;
    expect(fallback.supportsSessionRequestV1, isFalse);
    expect(
      () => fallback.requestSessionV1Json('7', '{"schema_version":1}'),
      throwsUnsupportedError,
    );
  });

  test('native pty backend correlates Host Request/Response v1 explicitly', () {
    final bindings = _HostRequestPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = backend.createSession('{}');

    final event = backend.pollEvents(sessionId).single;
    expect(event.kind, 'clipboard_paste_request');
    expect(event.payload, <String, Object?>{'selection': 'c'});
    expect(event.hostRequest, isNotNull);
    expect(event.hostRequest!.requestId, 'host:1:0');
    expect(event.hostRequest!.sequence, 0);

    final hostBackend = backend as PtyHostResponseV1Backend;
    expect(hostBackend.supportsHostResponseV1, isTrue);
    expect(
      hostBackend.respondToHostRequestV1(sessionId, '{"schema_version":1}'),
      isTrue,
    );
    expect(bindings.lastSessionId, 1);
    expect(bindings.lastResponseJson, '{"schema_version":1}');

    final fallback =
        NativePtyBackend.fromBindings(_NoopPtyBindings())
            as PtyHostResponseV1Backend;
    expect(fallback.supportsHostResponseV1, isFalse);
    expect(
      () => fallback.respondToHostRequestV1('1', '{}'),
      throwsUnsupportedError,
    );
  });

  test('native pty backend loads graphic assets through bindings', () {
    final bindings = _GraphicAssetRecordingPtyBindings();
    final backend =
        NativePtyBackend.fromBindings(bindings)
            as PtySessionGraphicAssetBackend;

    final asset = backend.loadGraphicAsset('9', assetId: 42, assetVersion: 3);

    expect(asset, isNotNull);
    expect(asset!.assetId, 42);
    expect(asset.assetVersion, 3);
    expect(asset.width, 1);
    expect(asset.height, 1);
    expect(asset.rgba, <int>[255, 0, 0, 255]);
    expect(bindings.lastSessionId, 9);
    expect(bindings.lastAssetId, 42);
    expect(bindings.lastAssetVersion, 3);
  });

  test('native pty backend prefers Graphic Asset Packet v1', () {
    final bindings = _GraphicAssetPacketV1PtyBindings();
    final backend =
        NativePtyBackend.fromBindings(bindings)
            as PtySessionGraphicAssetBackend;

    final asset = backend.loadGraphicAsset('9', assetId: 42, assetVersion: 3);

    expect(asset, isNotNull);
    expect(asset!.rgba, <int>[255, 0, 0, 255]);
    expect(bindings.packetCalls, <(int, int, int)>[(9, 42, 3)]);
    expect(bindings.legacyCalls, 0);
  });

  test('malformed Graphic Asset Packet v1 never downgrades in-call', () {
    final bindings = _GraphicAssetPacketV1PtyBindings(
      packet: Uint8List.fromList(const <int>[0x0a]),
    );
    final backend =
        NativePtyBackend.fromBindings(bindings)
            as PtySessionGraphicAssetBackend;

    expect(
      () => backend.loadGraphicAsset('9', assetId: 42, assetVersion: 3),
      throwsA(isA<PtyGraphicAssetPacketFormatException>()),
    );
    expect(bindings.legacyCalls, 0);
  });

  test('native pty backend consumes and discards file downloads once', () {
    final bindings = _FileDownloadRecordingPtyBindings();
    final backend =
        NativePtyBackend.fromBindings(bindings)
            as PtySessionFileDownloadBackend;

    final bytes = backend.takeFileDownload(
      '9',
      downloadId: 42,
      expectedSize: 5,
    );
    final discarded = backend.discardFileDownload('9', downloadId: 43);

    expect(bytes, <int>[1, 2, 3, 4, 5]);
    expect(discarded, isTrue);
    expect(bindings.takeCalls, <(int, int, int)>[(9, 42, 5)]);
    expect(bindings.discardCalls, <(int, int)>[(9, 43)]);
    expect(
      () => backend.takeFileDownload('9', downloadId: 0, expectedSize: 5),
      throwsArgumentError,
    );
    expect(
      () => backend.takeFileDownload(
        '9',
        downloadId: 1,
        expectedSize: 16 * 1024 * 1024 + 1,
      ),
      throwsRangeError,
    );
  });

  test(
    'native pty backend leaves generic JSON response validation to callers',
    () {
      final bindings = _RequestRecordingPtyBindings();
      final backend =
          NativePtyBackend.fromBindings(bindings)
              as PtySessionJsonRequestBackend;

      bindings.response = null;
      expect(backend.requestSessionJson('7', '{"kind":"diagnostics"}'), isNull);

      bindings.response = '';
      expect(backend.requestSessionJson('7', '{"kind":"diagnostics"}'), '');

      bindings.response = '{';
      expect(backend.requestSessionJson('7', '{"kind":"diagnostics"}'), '{');
    },
  );

  test('native pty backend throws typed exceptions for failed FFI calls', () {
    final bindings = _FailingPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);

    expect(
      () => backend.closeSession('1'),
      throwsA(
        isA<PtyNativeCallException>()
            .having((error) => error.operation, 'operation', 'closeSession')
            .having((error) => error.sessionId, 'sessionId', '1')
            .having((error) => error.statusCode, 'statusCode', -1),
      ),
    );
    expect(
      () => backend.resizeSession(
        '1',
        cols: 80,
        rows: 24,
        pixelWidth: 800,
        pixelHeight: 600,
      ),
      throwsA(
        isA<PtyNativeCallException>().having(
          (error) => error.operation,
          'operation',
          'resizeSession',
        ),
      ),
    );
    expect(
      () => backend.writeInput('1', const [0x41]),
      throwsA(
        isA<PtyNativeCallException>().having(
          (error) => error.operation,
          'operation',
          'writeInput',
        ),
      ),
    );
    expect(
      () => backend.scrollViewport('1', 1),
      throwsA(
        isA<PtyNativeCallException>().having(
          (error) => error.operation,
          'operation',
          'scrollViewport',
        ),
      ),
    );
    expect(
      () => backend.scrollViewportTo('1', 0),
      throwsA(
        isA<PtyNativeCallException>().having(
          (error) => error.operation,
          'operation',
          'scrollViewportTo',
        ),
      ),
    );
  });

  test('native pty backend classifies only status -2 close as retryable', () {
    expect(
      const PtyNativeCallException(
        operation: 'closeSession',
        sessionId: '1',
        statusCode: -2,
      ).isRetryableClose,
      isTrue,
    );
    expect(
      const PtyNativeCallException(
        operation: 'closeSession',
        sessionId: '1',
        statusCode: -1,
      ).isRetryableClose,
      isFalse,
    );
    expect(
      const PtyNativeCallException(
        operation: 'writeInput',
        sessionId: '1',
        statusCode: -2,
      ).isRetryableClose,
      isFalse,
    );
  });

  test(
    'native pty library resolution ignores environment override in product',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'ianvs-pty-resolver-test-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final explicitLib = File('${tempDir.path}/libianvs_core.dylib')
        ..writeAsStringSync('not a real dylib');

      expect(
        () => resolveNativePtyLibraryPath(
          environment: <String, String>{'IANVS_CORE_LIB': explicitLib.path},
          executableDirectory: tempDir,
          isProduct: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('IANVS_CORE_LIB is ignored in product builds'),
          ),
        ),
      );
    },
  );

  test('native pty backend rejects invalid session ids before bindings', () {
    final bindings = _RequestRecordingPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);

    expect(() => backend.closeSession('abc'), throwsArgumentError);
    expect(
      () => backend.resizeSession(
        '0',
        cols: 80,
        rows: 24,
        pixelWidth: 800,
        pixelHeight: 600,
      ),
      throwsArgumentError,
    );
    expect(() => backend.writeInput('-1', const [0x41]), throwsArgumentError);
    expect(
      () => (backend as PtySessionJsonRequestBackend).requestSessionJson(
        'nan',
        '{}',
      ),
      throwsArgumentError,
    );
    expect(
      () => backend.resizeSession(
        '18446744073709551616',
        cols: 80,
        rows: 24,
        pixelWidth: 800,
        pixelHeight: 600,
      ),
      throwsRangeError,
    );
    expect(bindings.lastSessionId, isNull);
  });

  test('native pty backend rejects invalid input bytes before bindings', () {
    final bindings = _RequestRecordingPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);

    expect(() => backend.writeInput('1', const [-1]), throwsRangeError);
    expect(bindings.lastSessionId, isNull);

    expect(() => backend.writeInput('1', const [0x100]), throwsRangeError);
    expect(bindings.lastSessionId, isNull);

    backend.writeInput('1', const [0x00, 0xff]);
    expect(bindings.lastSessionId, 1);
    expect(bindings.lastWriteBytes, const [0x00, 0xff]);
  });

  test('native pty backend rejects resize values before bindings', () {
    final bindings = _RequestRecordingPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);

    void expectInvalidResize({
      int cols = 80,
      int rows = 24,
      int pixelWidth = 800,
      int pixelHeight = 600,
      int cellWidth = 10,
      int cellHeight = 25,
    }) {
      bindings.lastSessionId = null;
      expect(
        () => backend.resizeSession(
          '1',
          cols: cols,
          rows: rows,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
        ),
        throwsRangeError,
      );
      expect(bindings.lastSessionId, isNull);
    }

    expectInvalidResize(cols: 0);
    expectInvalidResize(rows: 0);
    expectInvalidResize(cols: 65536);
    expectInvalidResize(rows: 65536);
    expectInvalidResize(pixelWidth: -1);
    expectInvalidResize(pixelHeight: -1);
    expectInvalidResize(pixelWidth: 65536);
    expectInvalidResize(pixelHeight: 65536);
    expectInvalidResize(cellWidth: -1);
    expectInvalidResize(cellHeight: -1);
    expectInvalidResize(cellWidth: 65536);
    expectInvalidResize(cellHeight: 65536);
  });

  test(
    'native pty backend rejects out-of-range scroll values before bindings',
    () {
      final bindings = _RequestRecordingPtyBindings();
      final backend = NativePtyBackend.fromBindings(bindings);

      expect(() => backend.scrollViewport('1', 0x80000000), throwsRangeError);
      expect(bindings.lastSessionId, isNull);

      expect(() => backend.scrollViewport('1', -0x80000001), throwsRangeError);
      expect(bindings.lastSessionId, isNull);

      expect(() => backend.scrollViewportTo('1', -1), throwsRangeError);
      expect(bindings.lastSessionId, isNull);
    },
  );

  test('pty event decoding skips malformed entries', () {
    final events = PtyEvent.listFromJson(<Object?>[
      <String, Object?>{
        'kind': 'started',
        'session_id': 7,
        'payload': <Object?, Object?>{'cwd': '/tmp/project', 42: 'ignored'},
      },
      'bad-entry',
      <String, Object?>{'kind': 'missing-session'},
      <String, Object?>{'session_id': 8},
      <String, Object?>{'kind': 'fractional-session', 'session_id': 7.5},
      <String, Object?>{'kind': 'zero-session', 'session_id': 0},
      <String, Object?>{'kind': 'blank-session', 'session_id': '   '},
      <String, Object?>{'kind': 'bad-string-session', 'session_id': 'abc'},
      <String, Object?>{'kind': 'zero-string-session', 'session_id': '0'},
      <String, Object?>{'kind': 'negative-string-session', 'session_id': '-1'},
      <String, Object?>{'kind': '   ', 'session_id': 9},
      <String, Object?>{
        'kind': 'fractional-string-session',
        'session_id': '7.5',
      },
      <String, Object?>{
        'kind': 'huge-string-session',
        'session_id': '18446744073709551616',
      },
      <String, Object?>{
        'kind': List<String>.filled(129, 'x').join(),
        'session_id': 9,
      },
      <String, Object?>{'kind': ' resized ', 'session_id': ' 9 '},
      <String, Object?>{
        'kind': 'exit',
        'session_id': ' 8 ',
        'payload': 'bad-payload',
      },
    ]);

    expect(events, hasLength(3));
    expect(events.first.kind, 'started');
    expect(events.first.sessionId, '7');
    expect(events.first.payload, <String, Object?>{'cwd': '/tmp/project'});
    expect(events[1].kind, 'resized');
    expect(events[1].sessionId, '9');
    expect(events.last.kind, 'exit');
    expect(events.last.sessionId, '8');
    expect(events.last.payload, isNull);
  });

  test('pty event decoding caps oversized event batches', () {
    final events = PtyEvent.listFromJson(<Object?>[
      for (var index = 0; index < 1026; index += 1)
        <String, Object?>{'kind': 'event', 'session_id': index + 1},
    ]);

    expect(events, hasLength(1024));
    expect(events.first.sessionId, '1');
    expect(events.last.sessionId, '1024');
  });

  test('pty event decoding rejects invalid single events', () {
    expect(
      () => PtyEvent.fromJson(<String, Object?>{'kind': 'started'}),
      throwsFormatException,
    );
    expect(
      () => PtyEvent.fromJson(<String, Object?>{
        'kind': 'started',
        'session_id': 'abc',
      }),
      throwsFormatException,
    );
    expect(
      () => PtyEvent.fromJson(<String, Object?>{
        'kind': '   ',
        'session_id': '1',
      }),
      throwsFormatException,
    );
  });

  test(
    'native pty backend can bridge to the real Rust core',
    () {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );

      expect(File(libraryPath).existsSync(), isTrue);
      expect(backend.ping(), 42);
      final capabilities =
          (backend as PtyRuntimeCapabilityBackend).runtimeCapabilities;
      expect(capabilities, isNotNull);
      expect(capabilities!.runtimeContract, 'ianvs-runtime-contract-v1');
      expect(capabilities.supports('replay-session.v1'), isTrue);
      expect(capabilities.supports('event-envelope.json.v1'), isTrue);
      expect(capabilities.supports('session-config.json.v1'), isTrue);
      expect(capabilities.supports('session-request-envelope.json.v1'), isTrue);
      expect(capabilities.supports('host-request-response.json.v1'), isTrue);
      expect(capabilities.supports('diagnostic-event.json.v1'), isTrue);
      expect(capabilities.supports('frame-packet.protobuf.v1'), isTrue);
      expect(capabilities.supports('graphic-asset-packet.protobuf.v1'), isTrue);
      final liveConfigBackend = backend as PtySessionConfigV1Backend;
      final replayConfigBackend = backend as PtyReplaySessionConfigV1Backend;
      expect(liveConfigBackend.supportsSessionConfigV1, isTrue);
      expect(replayConfigBackend.supportsReplaySessionConfigV1, isTrue);
      final refreshHintBackend = backend as PtySessionRefreshHintBackend;
      expect(refreshHintBackend.supportsRefreshHints, isTrue);
      expect(refreshHintBackend.refreshHintFlags('999999999'), 0);
      final hostBackend = backend as PtyHostResponseV1Backend;
      expect(hostBackend.supportsHostResponseV1, isTrue);
      final diagnosticBackend = backend as PtySessionDiagnosticEventV1Backend;
      expect(diagnosticBackend.supportsDiagnosticEventV1, isTrue);
      final framePacketBackend = backend as PtySessionFramePacketV1Backend;
      expect(framePacketBackend.supportsFramePacketV1, isTrue);

      final v1LiveSessionId = liveConfigBackend.createSessionV1(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-config-v1',
          'session_id': 'ffi-v1-live',
          'display_name': 'FFI V1 Live',
          'config': <String, Object?>{
            'launch': <String, Object?>{
              'program': '/bin/sh',
              'args': <Object?>['-c', 'sleep 60'],
              'env': <String, Object?>{},
              'cwd': null,
            },
          },
        }),
      );
      expect(v1LiveSessionId, isNot('0'));
      expect(
        framePacketBackend.takeFramePacketV1Protobuf(
          v1LiveSessionId,
          afterSequence: null,
        ),
        isNotEmpty,
      );
      final diagnosticEvent = diagnosticBackend.takeDiagnosticEventV1(
        v1LiveSessionId,
        'session_stats',
      );
      expect(diagnosticEvent, isNotNull);
      expect(diagnosticEvent!.sessionId, v1LiveSessionId);
      expect(diagnosticEvent.name, 'session_stats');
      backend.closeSession(v1LiveSessionId);

      final hostSessionId = liveConfigBackend.createSessionV1(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-config-v1',
          'session_id': 'ffi-v1-host',
          'display_name': 'FFI V1 Host Request',
          'config': <String, Object?>{
            'launch': <String, Object?>{
              'program': '/bin/sh',
              'args': <Object?>['-c', r"printf '\033]52;c;?\007'; sleep 60"],
              'env': <String, Object?>{},
              'cwd': null,
            },
          },
        }),
      );
      try {
        PtyHostRequestV1? hostRequest;
        for (var attempt = 0; attempt < 200 && hostRequest == null; attempt++) {
          final events = backend.pollEvents(hostSessionId);
          for (final event in events) {
            if (event.hostRequest != null) {
              hostRequest = event.hostRequest;
              break;
            }
          }
          if (hostRequest == null) {
            sleep(const Duration(milliseconds: 10));
          }
        }
        expect(hostRequest, isNotNull);
        final response = PtyHostResponseV1.success(
          request: hostRequest!,
          timestampMicros: DateTime.now().microsecondsSinceEpoch,
          payload: <String, Object?>{
            'data_base64': base64.encode(utf8.encode('ffi clipboard')),
          },
        ).toJsonString();
        expect(
          hostBackend.respondToHostRequestV1(hostSessionId, response),
          isTrue,
        );
        expect(
          hostBackend.respondToHostRequestV1(hostSessionId, response),
          isFalse,
          reason: 'a correlated Host Response must be consumed exactly once',
        );
      } finally {
        backend.closeSession(hostSessionId);
      }

      final replayBackend = backend as PtyReplaySessionBackend;
      final checkpointBackend = backend as PtyReplayCheckpointBackend;
      final requestV1Backend = backend as PtySessionRequestV1Backend;
      expect(requestV1Backend.supportsSessionRequestV1, isTrue);
      final sessionId = replayBackend.createReplaySession(
        '{"id":"ffi-replay","name":"FFI Replay","launch":{"program":"/definitely/not/a/child"}}',
      );
      replayBackend.replayOutput(sessionId, const <int>[0x66, 0x66, 0x69]);
      expect(checkpointBackend.supportsReplayCheckpoints, isTrue);
      final checkpointId = checkpointBackend.captureReplayCheckpoint(sessionId);
      replayBackend.replayOutput(sessionId, utf8.encode('-after-checkpoint'));
      expect(
        checkpointBackend.restoreReplayCheckpoint(sessionId, checkpointId),
        isTrue,
      );
      const requestId = 'dart-real-1';
      final requestResponse = requestV1Backend.requestSessionV1Json(
        sessionId,
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-request-v1',
          'request_id': requestId,
          'session_id': sessionId,
          'operation': 'terminal.search_text',
          'payload': <String, Object?>{
            'query': 'ffi',
            'mode': 'case_sensitive_substring',
          },
        }),
      );
      expect(requestResponse, isNotNull);
      final decodedRequestResponse = PtySessionResponseV1.fromJsonString(
        requestResponse!,
        expectedRequestId: requestId,
        expectedSessionId: sessionId,
        expectedOperation: 'terminal.search_text',
      );
      expect(decodedRequestResponse.ok, isTrue);
      expect(decodedRequestResponse.payload!['matches'], isNotEmpty);
      replayBackend.replayExit(sessionId, exitCode: 0);
      final restoredFrame = backend.takeFrameDiffJson(sessionId);
      expect(restoredFrame, contains('ffi'));
      expect(restoredFrame, isNot(contains('after-checkpoint')));
      final events = backend.pollEvents(sessionId);
      expect(
        events.map((event) => event.kind),
        containsAllInOrder(<String>['started', 'exit']),
      );
      expect(events.map((event) => event.sequence), <int>[0, 1]);
      expect(events.every((event) => event.wireSchemaVersion == 1), isTrue);
      backend.closeSession(sessionId);

      final v1ReplaySessionId = replayConfigBackend.createReplaySessionV1(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-config-v1',
          'session_id': 'ffi-v1-replay',
          'display_name': 'FFI V1 Replay',
          'config': <String, Object?>{
            'launch': <String, Object?>{
              'program': '/definitely/not/a/child',
              'args': <Object?>[],
              'env': <String, Object?>{},
              'cwd': null,
            },
          },
        }),
      );
      expect(v1ReplaySessionId, isNot('0'));
      backend.closeSession(v1ReplaySessionId);
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
  );
}

String? _resolveWorkspaceCoreLibraryPath() {
  if (!Platform.isMacOS) {
    return null;
  }

  const relativeCandidates = <String>[
    'native/core/target/debug/libianvs_core.dylib',
    '../native/core/target/debug/libianvs_core.dylib',
    '../../native/core/target/debug/libianvs_core.dylib',
  ];

  for (final relativePath in relativeCandidates) {
    final candidate = File.fromUri(Directory.current.uri.resolve(relativePath));
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}

final String? _workspaceCoreLibraryPath = _resolveWorkspaceCoreLibraryPath();

class _NoopPtyBindings implements PtyBindings {
  @override
  bool get supportsFrameDiffProtobuf => false;

  @override
  int ping() => 42;

  @override
  int sessionCreateJson(String sessionConfigJson) => 1;

  @override
  int sessionClose(int sessionId) => 0;

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight, [
    int cellWidth = 0,
    int cellHeight = 0,
  ]) => 0;

  @override
  int sessionWrite(int sessionId, List<int> bytes) => 0;

  @override
  int sessionScroll(int sessionId, int deltaLines) => 0;

  @override
  int sessionScrollTo(int sessionId, int offset) => 0;

  @override
  String? sessionRequestJson(int sessionId, String requestJson) => null;

  @override
  String? sessionDiagnosticsJson(int sessionId, String kind) => null;

  @override
  String? sessionTakeFrameDiffJson(int sessionId) => '{"rows":[]}';

  @override
  Uint8List? sessionTakeFrameDiffProtobuf(int sessionId) => null;

  @override
  List<PtyEvent> sessionPollEvents(int sessionId) => const [];

  @override
  PtyGraphicAsset? sessionGraphicAsset(
    int sessionId,
    int assetId,
    int assetVersion,
  ) => null;
}

class _CapabilityPtyBindings extends _NoopPtyBindings
    implements PtyRuntimeCapabilityBindings {
  @override
  String? runtimeCapabilitiesJson() => jsonEncode(<String, Object?>{
    'schema_version': 1,
    'runtime_contract': 'ianvs-runtime-contract-v1',
    'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
    'recording_schema_versions': <Object?>[1],
    'features': <Object?>['frame.json.v1', 'frame.protobuf.v1'],
  });
}

class _ProtocolReplyPtyBindings extends _NoopPtyBindings
    implements PtyProtocolReplyBindings {
  final List<(int, List<int>)> replies = <(int, List<int>)>[];

  @override
  bool get supportsProtocolReplies => true;

  @override
  int sessionWriteProtocolReply(int sessionId, List<int> bytes) {
    replies.add((sessionId, List<int>.of(bytes)));
    return 0;
  }
}

class _RuntimeEventPtyBindings extends _NoopPtyBindings
    implements PtyRuntimeEventBindings {
  _RuntimeEventPtyBindings({this.sequences = const <int>[0, 1]});

  final List<int> sequences;
  int envelopePollCalls = 0;
  int legacyPollCalls = 0;

  @override
  bool get supportsRuntimeEventEnvelopes => true;

  @override
  String? sessionPollEventEnvelopesJson(int sessionId) {
    envelopePollCalls += 1;
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-event-batch-v1',
      'message_class': 'event',
      'session_id': '$sessionId',
      'next_sequence': sequences.last + 1,
      'dropped_count': sequences.length == 2 && sequences.last == 2 ? 1 : 0,
      'messages': <Object?>[
        for (final sequence in sequences)
          <String, Object?>{
            'schema_version': 1,
            'contract': 'ianvs-runtime-envelope-v1',
            'message_class': 'event',
            'message_name': sequence == 0 ? 'started' : 'future_event',
            'session_id': '$sessionId',
            'sequence': sequence,
            'timestamp_micros': 1000 + sequence,
            'payload': <String, Object?>{'value': sequence},
          },
      ],
    });
  }

  @override
  List<PtyEvent> sessionPollEvents(int sessionId) {
    legacyPollCalls += 1;
    return super.sessionPollEvents(sessionId);
  }
}

class _SequencedRuntimeEventPtyBindings extends _NoopPtyBindings
    implements PtyRuntimeEventBindings {
  _SequencedRuntimeEventPtyBindings(this.batches, {this.nextSequences});

  final List<List<int>> batches;
  final List<int>? nextSequences;
  int _pollIndex = 0;

  @override
  bool get supportsRuntimeEventEnvelopes => true;

  @override
  String? sessionPollEventEnvelopesJson(int sessionId) {
    final index = _pollIndex;
    final sequences = batches[index];
    _pollIndex += 1;
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-event-batch-v1',
      'message_class': 'event',
      'session_id': '$sessionId',
      'next_sequence':
          nextSequences?[index] ?? (sequences.isEmpty ? 0 : sequences.last + 1),
      'dropped_count': 0,
      'messages': <Object?>[
        for (final sequence in sequences)
          <String, Object?>{
            'schema_version': 1,
            'contract': 'ianvs-runtime-envelope-v1',
            'message_class': 'event',
            'message_name': 'future_event',
            'session_id': '$sessionId',
            'sequence': sequence,
            'timestamp_micros': 1000 + sequence,
            'payload': <String, Object?>{'value': sequence},
          },
      ],
    });
  }
}

class _HostRequestPtyBindings extends _NoopPtyBindings
    implements PtyRuntimeEventBindings, PtyHostResponseV1Bindings {
  int? lastSessionId;
  String? lastResponseJson;

  @override
  bool get supportsRuntimeEventEnvelopes => true;

  @override
  bool get supportsHostResponseV1 => true;

  @override
  String? sessionPollEventEnvelopesJson(int sessionId) {
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-event-batch-v1',
      'message_class': 'event',
      'session_id': '$sessionId',
      'next_sequence': 1,
      'dropped_count': 0,
      'messages': <Object?>[
        <String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-runtime-envelope-v1',
          'message_class': 'event',
          'message_name': 'host_request',
          'session_id': '$sessionId',
          'sequence': 0,
          'timestamp_micros': 1000,
          'payload': <String, Object?>{
            'schema_version': 1,
            'contract': 'ianvs-host-request-v1',
            'request_id': 'host:$sessionId:0',
            'session_id': '$sessionId',
            'operation': 'clipboard.read_text',
            'sequence': 0,
            'timestamp_micros': 1000,
            'payload': <String, Object?>{'selection': 'c'},
          },
        },
      ],
    });
  }

  @override
  bool sessionHostResponseV1Json(int sessionId, String responseV1Json) {
    lastSessionId = sessionId;
    lastResponseJson = responseV1Json;
    return true;
  }
}

class _SessionConfigV1PtyBindings extends _NoopPtyBindings
    implements PtySessionConfigV1Bindings {
  int liveV1Calls = 0;
  int replayV1Calls = 0;
  int legacyCreateCalls = 0;

  @override
  bool get supportsSessionConfigV1 => true;

  @override
  bool get supportsReplaySessionConfigV1 => true;

  @override
  int sessionCreateV1Json(String sessionConfigV1Json) {
    liveV1Calls += 1;
    return 51;
  }

  @override
  int replaySessionCreateV1Json(String sessionConfigV1Json) {
    replayV1Calls += 1;
    return 52;
  }

  @override
  int sessionCreateJson(String sessionConfigJson) {
    legacyCreateCalls += 1;
    return super.sessionCreateJson(sessionConfigJson);
  }
}

class _LegacySessionConfigPtyBindings extends _NoopPtyBindings {
  int legacyCreateCalls = 0;

  @override
  int sessionCreateJson(String sessionConfigJson) {
    legacyCreateCalls += 1;
    return super.sessionCreateJson(sessionConfigJson);
  }
}

class _SessionRequestV1PtyBindings extends _NoopPtyBindings
    implements PtySessionRequestV1Bindings {
  int? lastSessionId;
  String? lastRequestJson;
  int legacyRequestCalls = 0;

  @override
  bool get supportsSessionRequestV1 => true;

  @override
  String? sessionRequestV1Json(int sessionId, String requestV1Json) {
    lastSessionId = sessionId;
    lastRequestJson = requestV1Json;
    return '{"schema_version":1}';
  }

  @override
  String? sessionRequestJson(int sessionId, String requestJson) {
    legacyRequestCalls += 1;
    return super.sessionRequestJson(sessionId, requestJson);
  }
}

class _LegacyEventPtyBindings extends _NoopPtyBindings {
  int legacyPollCalls = 0;

  @override
  List<PtyEvent> sessionPollEvents(int sessionId) {
    legacyPollCalls += 1;
    return <PtyEvent>[
      PtyEvent(kind: 'legacy_started', sessionId: '$sessionId'),
    ];
  }
}

class _NoopDebugPtyBindings extends _NoopPtyBindings {
  @override
  String? sessionDiagnosticsJson(int sessionId, String kind) {
    return switch (kind) {
      'frame' => '{"rows_scanned":2}',
      'session' => '{"bytes_read":4}',
      _ => null,
    };
  }
}

class _DiagnosticEventV1PtyBindings extends _NoopPtyBindings
    implements PtyDiagnosticEventV1Bindings {
  int v1Calls = 0;
  int legacyCalls = 0;

  @override
  bool get supportsDiagnosticEventV1 => true;

  @override
  String? sessionTakeDiagnosticEventV1Json(int sessionId, String name) {
    v1Calls += 1;
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-envelope-v1',
      'message_class': 'diagnostic',
      'message_name': name,
      'session_id': '$sessionId',
      'sequence': 0,
      'timestamp_micros': 1,
      'payload': <String, Object?>{'rows_scanned': 9},
    });
  }

  @override
  String? sessionDiagnosticsJson(int sessionId, String kind) {
    legacyCalls += 1;
    return super.sessionDiagnosticsJson(sessionId, kind);
  }
}

class _ReplayPtyBindings extends _NoopPtyBindings implements PtyReplayBindings {
  String? createdConfig;
  final List<(int, List<int>)> outputCalls = <(int, List<int>)>[];
  final List<(int, int?)> exitCalls = <(int, int?)>[];

  @override
  bool get supportsReplaySessions => true;

  @override
  int replaySessionCreateJson(String sessionConfigJson) {
    createdConfig = sessionConfigJson;
    return 41;
  }

  @override
  int replaySessionOutput(int sessionId, List<int> bytes) {
    outputCalls.add((sessionId, List<int>.of(bytes)));
    return 0;
  }

  @override
  int replaySessionExit(int sessionId, int? exitCode) {
    exitCalls.add((sessionId, exitCode));
    return 0;
  }
}

class _ReplayCheckpointPtyBindings extends _ReplayPtyBindings
    implements PtyReplayCheckpointBindings {
  final List<int> captureCalls = <int>[];
  final List<(int, int)> restoreCalls = <(int, int)>[];

  @override
  bool get supportsReplayCheckpoints => true;

  @override
  int replaySessionCheckpointCapture(int sessionId) {
    captureCalls.add(sessionId);
    return 71;
  }

  @override
  bool replaySessionCheckpointRestore(int sessionId, int checkpointId) {
    restoreCalls.add((sessionId, checkpointId));
    return true;
  }
}

class _FailingPtyBindings extends _NoopPtyBindings {
  @override
  int sessionClose(int sessionId) => -1;

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight, [
    int cellWidth = 0,
    int cellHeight = 0,
  ]) => -1;

  @override
  int sessionWrite(int sessionId, List<int> bytes) => -1;

  @override
  int sessionScroll(int sessionId, int deltaLines) => -1;

  @override
  int sessionScrollTo(int sessionId, int offset) => -1;
}

class _ProtobufFramePtyBindings extends _NoopPtyBindings {
  @override
  bool get supportsFrameDiffProtobuf => true;

  @override
  Uint8List? sessionTakeFrameDiffProtobuf(int sessionId) {
    return Uint8List.fromList(const <int>[8, 1, 18, 4]);
  }
}

class _FramePacketV1PtyBindings extends _NoopPtyBindings
    implements PtyFramePacketV1Bindings {
  final List<(int, int?)> calls = <(int, int?)>[];

  @override
  bool get supportsFramePacketV1 => true;

  @override
  Uint8List? sessionTakeFramePacketV1Protobuf(
    int sessionId, {
    required int? afterSequence,
  }) {
    calls.add((sessionId, afterSequence));
    return Uint8List.fromList(const <int>[10, 1]);
  }
}

class _RefreshHintPtyBindings extends _NoopPtyBindings
    implements PtyRefreshHintBindings {
  _RefreshHintPtyBindings(this.flags);

  final int flags;
  int? lastSessionId;
  int refreshHintCalls = 0;

  @override
  bool get supportsRefreshHints => true;

  @override
  int sessionRefreshHintFlags(int sessionId) {
    refreshHintCalls += 1;
    lastSessionId = sessionId;
    return flags;
  }
}

class _CloseFailingRefreshHintPtyBindings extends _RefreshHintPtyBindings {
  _CloseFailingRefreshHintPtyBindings(super.flags);

  @override
  int sessionClose(int sessionId) => -1;
}

class _RequestRecordingPtyBindings extends _NoopPtyBindings {
  int? lastSessionId;
  String? lastRequestJson;
  List<int>? lastWriteBytes;
  String? response = '{"ok":true}';

  @override
  int sessionWrite(int sessionId, List<int> bytes) {
    lastSessionId = sessionId;
    lastWriteBytes = List<int>.of(bytes);
    return 0;
  }

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight, [
    int cellWidth = 0,
    int cellHeight = 0,
  ]) {
    lastSessionId = sessionId;
    return 0;
  }

  @override
  int sessionScroll(int sessionId, int deltaLines) {
    lastSessionId = sessionId;
    return 0;
  }

  @override
  int sessionScrollTo(int sessionId, int offset) {
    lastSessionId = sessionId;
    return 0;
  }

  @override
  String? sessionRequestJson(int sessionId, String requestJson) {
    lastSessionId = sessionId;
    lastRequestJson = requestJson;
    return response;
  }
}

class _GraphicAssetRecordingPtyBindings extends _NoopPtyBindings {
  int? lastSessionId;
  int? lastAssetId;
  int? lastAssetVersion;

  @override
  PtyGraphicAsset? sessionGraphicAsset(
    int sessionId,
    int assetId,
    int assetVersion,
  ) {
    lastSessionId = sessionId;
    lastAssetId = assetId;
    lastAssetVersion = assetVersion;
    return PtyGraphicAsset(
      assetId: assetId,
      assetVersion: assetVersion,
      width: 1,
      height: 1,
      rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
    );
  }
}

class _GraphicAssetPacketV1PtyBindings extends _NoopPtyBindings
    implements PtyGraphicAssetPacketV1Bindings {
  _GraphicAssetPacketV1PtyBindings({Uint8List? packet})
    : packet =
          packet ??
          _graphicAssetPacket(
            sessionId: '9',
            assetId: 42,
            assetVersion: 3,
            width: 1,
            height: 1,
            rgba: const <int>[255, 0, 0, 255],
          );

  final Uint8List packet;
  final List<(int, int, int)> packetCalls = <(int, int, int)>[];
  int legacyCalls = 0;

  @override
  bool get supportsGraphicAssetPacketV1 => true;

  @override
  Uint8List? sessionGraphicAssetPacketV1Protobuf(
    int sessionId,
    int assetId,
    int assetVersion,
  ) {
    packetCalls.add((sessionId, assetId, assetVersion));
    return packet;
  }

  @override
  PtyGraphicAsset? sessionGraphicAsset(
    int sessionId,
    int assetId,
    int assetVersion,
  ) {
    legacyCalls += 1;
    return super.sessionGraphicAsset(sessionId, assetId, assetVersion);
  }
}

Uint8List _graphicAssetPacket({
  required String sessionId,
  required int assetId,
  required int assetVersion,
  required int width,
  required int height,
  required List<int> rgba,
}) => Uint8List.fromList(<int>[
  ..._protobufVarintField(1, 1),
  ..._protobufBytesField(2, utf8.encode('ianvs-graphic-asset-packet-v1')),
  ..._protobufBytesField(3, utf8.encode('asset_transfer')),
  ..._protobufBytesField(4, utf8.encode('graphic_asset')),
  ..._protobufBytesField(5, utf8.encode(sessionId)),
  ..._protobufBytesField(6, utf8.encode('$assetId')),
  ..._protobufBytesField(7, utf8.encode('$assetVersion')),
  ..._protobufVarintField(8, width),
  ..._protobufVarintField(9, height),
  ..._protobufBytesField(10, rgba),
]);

List<int> _protobufVarintField(int fieldNumber, int value) => <int>[
  ..._protobufVarint(fieldNumber << 3),
  ..._protobufVarint(value),
];

List<int> _protobufBytesField(int fieldNumber, List<int> value) => <int>[
  ..._protobufVarint((fieldNumber << 3) | 2),
  ..._protobufVarint(value.length),
  ...value,
];

List<int> _protobufVarint(int value) {
  final bytes = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) {
      byte |= 0x80;
    }
    bytes.add(byte);
  } while (remaining != 0);
  return bytes;
}

class _FileDownloadRecordingPtyBindings extends _NoopPtyBindings
    implements PtyFileDownloadBindings {
  final List<(int, int, int)> takeCalls = <(int, int, int)>[];
  final List<(int, int)> discardCalls = <(int, int)>[];

  @override
  Uint8List? sessionTakeFileDownload(
    int sessionId,
    int downloadId,
    int expectedSize,
  ) {
    takeCalls.add((sessionId, downloadId, expectedSize));
    return Uint8List.fromList(const <int>[1, 2, 3, 4, 5]);
  }

  @override
  bool sessionDiscardFileDownload(int sessionId, int downloadId) {
    discardCalls.add((sessionId, downloadId));
    return true;
  }
}

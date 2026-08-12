import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:test/test.dart';

void main() {
  test('manifest-required NativePtyBindings symbols are fail-fast', () {
    final source = <File>[
      File('${Directory.current.path}/lib/src/native_pty_backend.dart'),
      File('${Directory.current.path}/lib/src/pty/native_pty_backend.dart'),
    ].singleWhere((file) => file.existsSync()).readAsStringSync();
    expect(_requiredNativeBindingViolations(source), isEmpty);

    for (final mutation in <String>[
      '$source\n_lookupOptionalFileDownloadTake(library);',
      source.replaceFirst(
        'final _ReplayCheckpointCaptureDart _replayCheckpointCapture;',
        'final _ReplayCheckpointCaptureDart? _replayCheckpointCapture;',
      ),
      source.replaceFirst(
        'bool get supportsReplayCheckpoints => true;',
        'bool get supportsReplayCheckpoints => false;',
      ),
      source.replaceFirst(
        "'ianvs_session_file_download_take'",
        "'ianvs_session_file_download_take_compat'",
      ),
    ]) {
      expect(_requiredNativeBindingViolations(mutation), isNotEmpty);
    }
  });

  test('backend exposes only the current required runtime wire paths', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final config = backend as PtySessionConfigV1Backend;

    final sessionId = config.createSessionV1('{"schema_version":1}');
    backend.resizeSession(
      sessionId,
      cols: 80,
      rows: 24,
      pixelWidth: 800,
      pixelHeight: 600,
      cellWidth: 10,
      cellHeight: 25,
    );
    backend.writeInput(sessionId, const <int>[0x41]);
    backend.scrollViewport(sessionId, 3);
    backend.scrollViewportTo(sessionId, 4);

    expect(sessionId, '7');
    expect(bindings.liveConfigs, <String>['{"schema_version":1}']);
    expect(bindings.resizeCalls.single, (7, 80, 24, 800, 600, 10, 25));
    expect(bindings.inputCalls.single.$1, 7);
    expect(bindings.inputCalls.single.$2, <int>[0x41]);
    expect(bindings.scrollCalls, <(int, int)>[(7, 3)]);
    expect(bindings.scrollToCalls, <(int, int)>[(7, 4)]);

    backend.closeSession(sessionId);
    expect(bindings.closedSessions, <int>[7]);
  });

  test('Frame Packet v1 forwards its acknowledgement cursor exactly', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = (backend as PtySessionConfigV1Backend).createSessionV1(
      '{}',
    );
    final packets = backend as PtySessionFramePacketV1Backend;

    expect(
      packets.takeFramePacketV1Protobuf(sessionId, afterSequence: null),
      <int>[0x0a, 0x01],
    );
    expect(
      packets.takeFramePacketV1Protobuf(sessionId, afterSequence: 9),
      <int>[0x0a, 0x01],
    );
    expect(bindings.frameCalls, <(int, int?)>[(7, null), (7, 9)]);
  });

  test('Session Request v1 has no unversioned request fallback', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = (backend as PtySessionConfigV1Backend).createSessionV1(
      '{}',
    );
    final requests = backend as PtySessionRequestV1Backend;

    expect(
      requests.requestSessionV1Json(sessionId, '{"schema_version":1}'),
      '{"schema_version":1}',
    );
    expect(bindings.requestCalls, <(int, String)>[(7, '{"schema_version":1}')]);
  });

  test('Runtime Event Envelope v1 is the only event ingress', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = (backend as PtySessionConfigV1Backend).createSessionV1(
      '{}',
    );

    final events = backend.pollEvents(sessionId);

    expect(events, hasLength(1));
    expect(events.single.kind, 'started');
    expect(events.single.sequence, 0);
    expect(events.single.wireSchemaVersion, 1);
    expect(bindings.eventPolls, <int>[7]);
  });

  test('Diagnostic Event v1 remains exactly correlated', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final sessionId = (backend as PtySessionConfigV1Backend).createSessionV1(
      '{}',
    );
    final diagnostics = backend as PtySessionDiagnosticEventV1Backend;

    final event = diagnostics.takeDiagnosticEventV1(sessionId, 'frame_stats');

    expect(event, isNotNull);
    expect(event!.sessionId, '7');
    expect(event.name, 'frame_stats');
    expect(event.payload, <String, Object?>{'rows_scanned': 9});
    expect(bindings.diagnosticCalls, <(int, String)>[(7, 'frame_stats')]);
  });

  test('replay creation uses SessionConfig v1', () {
    final bindings = _CurrentPtyBindings();
    final backend = NativePtyBackend.fromBindings(bindings);
    final replayConfig = backend as PtyReplaySessionConfigV1Backend;
    final replay = backend as PtyReplaySessionBackend;

    final sessionId = replayConfig.createReplaySessionV1(
      '{"schema_version":1}',
    );
    replay.replayOutput(sessionId, const <int>[0x66]);
    replay.replayExit(sessionId, exitCode: 0);

    expect(sessionId, '8');
    expect(bindings.replayConfigs, <String>['{"schema_version":1}']);
    expect(bindings.replayOutputs.single.$1, 8);
    expect(bindings.replayOutputs.single.$2, <int>[0x66]);
    expect(bindings.replayExits, <(int, int?)>[(8, 0)]);
  });

  test('native pty library resolves a bundled macOS code asset framework', () {
    final executableRoot = Directory.systemTemp.createTempSync(
      'ianvs-pty-framework-resolver-test-',
    );
    addTearDown(() {
      if (executableRoot.existsSync()) {
        executableRoot.deleteSync(recursive: true);
      }
    });
    final executableDirectory = Directory(
      '${executableRoot.path}/ACP Client.app/Contents/MacOS',
    )..createSync(recursive: true);
    final appContents = '${executableRoot.path}/ACP Client.app/Contents';
    final frameworkBinary =
        File('$appContents/Frameworks/ianvs_core.framework/ianvs_core')
          ..createSync(recursive: true)
          ..writeAsStringSync('not a real dylib');

    final resolved = resolveNativePtyLibraryPath(
      environment: const <String, String>{},
      executableDirectory: executableDirectory,
      isProduct: true,
    );

    expect(
      File(resolved).absolute.uri.normalizePath(),
      frameworkBinary.absolute.uri.normalizePath(),
    );
  });

  test('invalid native identifiers are rejected before any current call', () {
    final backend = NativePtyBackend.fromBindings(_CurrentPtyBindings());

    expect(
      () => (backend as PtySessionFramePacketV1Backend)
          .takeFramePacketV1Protobuf('not-native', afterSequence: null),
      throwsArgumentError,
    );
    expect(
      () => (backend as PtySessionRequestV1Backend).requestSessionV1Json(
        '18446744073709551616',
        '{}',
      ),
      throwsArgumentError,
    );
  });
}

List<String> _requiredNativeBindingViolations(String source) {
  final violations = <String>[];
  for (final forbidden in <String>[
    '_lookupOptionalReplayCheckpointCapture',
    '_lookupOptionalReplayCheckpointRestore',
    '_lookupOptionalFileDownloadTake',
    '_lookupOptionalFileDownloadDiscard',
    'final _ReplayCheckpointCaptureDart? _replayCheckpointCapture;',
    'final _ReplayCheckpointRestoreDart? _replayCheckpointRestore;',
    'final _FileDownloadTakeDart? _fileDownloadTake;',
    'final _FileDownloadDiscardDart? _fileDownloadDiscard;',
  ]) {
    if (source.contains(forbidden)) {
      violations.add('optional required binding: $forbidden');
    }
  }
  for (final required in <String>[
    "'ianvs_replay_session_checkpoint_capture'",
    "'ianvs_replay_session_checkpoint_restore'",
    "'ianvs_session_file_download_take'",
    "'ianvs_session_file_download_discard'",
    'bool get supportsReplayCheckpoints => true;',
    'abstract interface class PtyReplayCheckpointBindings',
    'abstract interface class PtyFileDownloadBindings',
  ]) {
    if (!source.contains(required)) {
      violations.add('missing required binding: $required');
    }
  }
  return violations;
}

final class _CurrentPtyBindings implements PtyBindings, PtyReplayBindings {
  final List<String> liveConfigs = <String>[];
  final List<String> replayConfigs = <String>[];
  final List<int> closedSessions = <int>[];
  final List<(int, int, int, int, int, int, int)> resizeCalls =
      <(int, int, int, int, int, int, int)>[];
  final List<(int, List<int>)> inputCalls = <(int, List<int>)>[];
  final List<(int, int)> scrollCalls = <(int, int)>[];
  final List<(int, int)> scrollToCalls = <(int, int)>[];
  final List<(int, String)> requestCalls = <(int, String)>[];
  final List<(int, String)> diagnosticCalls = <(int, String)>[];
  final List<int> eventPolls = <int>[];
  final List<(int, int?)> frameCalls = <(int, int?)>[];
  final List<(int, List<int>)> replayOutputs = <(int, List<int>)>[];
  final List<(int, int?)> replayExits = <(int, int?)>[];

  @override
  int ping() => 42;

  @override
  int sessionCreateV1Json(String sessionConfigV1Json) {
    liveConfigs.add(sessionConfigV1Json);
    return 7;
  }

  @override
  int replaySessionCreateV1Json(String sessionConfigV1Json) {
    replayConfigs.add(sessionConfigV1Json);
    return 8;
  }

  @override
  int sessionClose(int sessionId) {
    closedSessions.add(sessionId);
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
    resizeCalls.add((
      sessionId,
      cols,
      rows,
      pixelWidth,
      pixelHeight,
      cellWidth,
      cellHeight,
    ));
    return 0;
  }

  @override
  int sessionWrite(int sessionId, List<int> bytes) {
    inputCalls.add((sessionId, List<int>.of(bytes)));
    return 0;
  }

  @override
  int sessionScroll(int sessionId, int deltaLines) {
    scrollCalls.add((sessionId, deltaLines));
    return 0;
  }

  @override
  int sessionScrollTo(int sessionId, int offset) {
    scrollToCalls.add((sessionId, offset));
    return 0;
  }

  @override
  String? sessionRequestV1Json(int sessionId, String requestV1Json) {
    requestCalls.add((sessionId, requestV1Json));
    return requestV1Json;
  }

  @override
  String? sessionTakeDiagnosticEventV1Json(int sessionId, String name) {
    diagnosticCalls.add((sessionId, name));
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-envelope-v1',
      'message_class': 'diagnostic',
      'message_name': name,
      'session_id': '$sessionId',
      'sequence': 0,
      'timestamp_micros': 42,
      'payload': <String, Object?>{'rows_scanned': 9},
    });
  }

  @override
  Uint8List? sessionTakeFramePacketV1Protobuf(
    int sessionId, {
    required int? afterSequence,
  }) {
    frameCalls.add((sessionId, afterSequence));
    return Uint8List.fromList(const <int>[0x0a, 0x01]);
  }

  @override
  String? sessionPollEventEnvelopesJson(int sessionId) {
    eventPolls.add(sessionId);
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
          'message_name': 'started',
          'session_id': '$sessionId',
          'sequence': 0,
          'timestamp_micros': 42,
          'payload': <String, Object?>{},
        },
      ],
    });
  }

  @override
  Uint8List? sessionGraphicAssetPacketV1Protobuf(
    int sessionId,
    int assetId,
    int assetVersion,
  ) => null;

  @override
  int replaySessionOutput(int sessionId, List<int> bytes) {
    replayOutputs.add((sessionId, List<int>.of(bytes)));
    return 0;
  }

  @override
  int replaySessionExit(int sessionId, int? exitCode) {
    replayExits.add((sessionId, exitCode));
    return 0;
  }
}

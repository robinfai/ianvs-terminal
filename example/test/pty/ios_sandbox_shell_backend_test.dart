import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/features/pty/pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_transport_coordinator.dart';

void main() {
  late Directory root;
  late IosSandboxShellBackend backend;
  late String sessionId;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ianvs-ios-shell-test-');
    backend = IosSandboxShellBackend(
      rootDirectory: root,
      terminalBackend: NativePtyBackend.load(),
      clock: () => DateTime.utc(2026, 8, 7, 12, 30),
    );
    sessionId = backend.createSessionV1(_sessionConfig('ios-test'));
  });

  tearDown(() {
    backend.closeSession(sessionId);
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('runs useful commands, pipes, and redirects inside the sandbox', () {
    _takeText(backend, sessionId);

    backend.writeInput(
      sessionId,
      utf8.encode(
        'mkdir -p docs; echo "Hello iPhone" > docs/note.txt; '
        'cat docs/note.txt | grep iPhone\r',
      ),
    );

    final text = _takeText(backend, sessionId);
    expect(text, contains('Hello iPhone'));
    expect(
      File('${root.path}/docs/note.txt').readAsStringSync(),
      'Hello iPhone\n',
    );

    backend.writeInput(sessionId, utf8.encode('cd docs; pwd; ls -l\r'));
    final directoryText = _takeText(backend, sessionId);
    expect(directoryText, contains('/docs'));
    expect(directoryText, contains('note.txt'));
  });

  test('keeps traversal and symlink targets outside the sandbox blocked', () {
    _takeText(backend, sessionId);
    final outside = Directory.systemTemp.createTempSync('ianvs-outside-');
    addTearDown(() {
      if (outside.existsSync()) {
        outside.deleteSync(recursive: true);
      }
    });
    File('${outside.path}/secret.txt').writeAsStringSync('secret');
    Link('${root.path}/escape').createSync(outside.path);

    backend.writeInput(sessionId, utf8.encode('cat ../../secret.txt\r'));
    expect(_takeText(backend, sessionId), contains('cannot escape'));

    backend.writeInput(sessionId, utf8.encode('cat escape/secret.txt\r'));
    final symlinkText = _takeText(backend, sessionId);
    expect(symlinkText, contains('cannot escape'));
    expect(symlinkText, isNot(contains('\nsecret\n')));
  });

  test('supports cursor editing, history, and control characters', () {
    _takeText(backend, sessionId);
    backend.writeInput(sessionId, utf8.encode('echo helo'));
    backend.writeInput(sessionId, const <int>[0x1b, 0x5b, 0x44]);
    backend.writeInput(sessionId, utf8.encode('l\r'));
    expect(_takeText(backend, sessionId), contains('hello'));

    backend.writeInput(sessionId, const <int>[0x1b, 0x5b, 0x41]);
    backend.writeInput(sessionId, const <int>[0x03]);
    final interrupted = _takeText(backend, sessionId);
    expect(interrupted, contains('echo hello^C'));

    backend.writeInput(sessionId, utf8.encode('echo hidden'));
    backend.writeInput(sessionId, const <int>[0x0c]);
    final cleared = _takeText(backend, sessionId);
    expect(cleared, isNot(contains('Ianvs Sandbox Shell')));
    expect(cleared, contains(r'ios:~ $ echo hidden'));
  });

  test('positions the cursor by terminal cell width for Chinese input', () {
    _takeFrame(backend, sessionId);

    backend.writeInput(sessionId, utf8.encode('A中B'));
    var frame = _takeFrame(backend, sessionId);
    expect(_cursor(frame)['col'], 12);

    backend.writeInput(sessionId, const <int>[0x1b, 0x5b, 0x44]);
    frame = _takeFrame(backend, sessionId);
    expect(_cursor(frame)['col'], 11);

    backend.writeInput(sessionId, const <int>[0x7f]);
    frame = _takeFrame(backend, sessionId);
    expect(_cursor(frame)['col'], 9);
    expect(_frameText(frame), contains(r'ios:~ $ AB'));
  });

  test('wraps a wide Chinese glyph before a one-cell remainder', () {
    _takeFrame(backend, sessionId);
    backend.resizeSession(
      sessionId,
      cols: 20,
      rows: 10,
      pixelWidth: 200,
      pixelHeight: 200,
    );

    backend.writeInput(sessionId, utf8.encode('12345678901中'));

    final frame = _takeFrame(backend, sessionId);
    final rows = frame['rows']! as List<Object?>;
    final cursorRow = _cursor(frame)['row']! as int;
    final rowAtCursor = rows[cursorRow]! as Map<String, Object?>;
    expect((rowAtCursor['text']! as String).trimRight(), '中');
    expect(_cursor(frame)['col'], 2);
  });

  test('routes SSH sessions to native while preserving the sandbox shell', () {
    final routingRoot = Directory.systemTemp.createTempSync(
      'ianvs-ios-routing-test-',
    );
    final routingBackend = _RoutingPtyBackend();
    final composite = IosSandboxShellBackend(
      rootDirectory: routingRoot,
      terminalBackend: routingBackend,
    );
    addTearDown(() {
      if (routingRoot.existsSync()) {
        routingRoot.deleteSync(recursive: true);
      }
    });

    expect(composite.runtimeCapabilities?.supports('ssh-session.v1'), isTrue);

    final sandboxId = composite.createSessionV1(_sessionConfig('local'));
    final sshId = composite.createSessionV1(_sshSessionConfig('ssh'));

    expect(routingBackend.replayConfigs, hasLength(1));
    expect(routingBackend.liveConfigs, hasLength(1));
    expect(sandboxId, 'replay-session');
    expect(sshId, 'live-session');
    final routedSsh = TerminalSessionConfigV1.fromJsonString(
      routingBackend.liveConfigs.single,
    );
    expect(
      routedSsh.config.connection.knownHostsFile,
      '${routingRoot.resolveSymbolicLinksSync()}/.ssh/known_hosts',
    );

    composite.resizeSession(
      sshId,
      cols: 90,
      rows: 30,
      pixelWidth: 900,
      pixelHeight: 600,
    );
    composite.writeInput(sshId, const <int>[0x61, 0x62]);
    composite.scrollViewport(sshId, 3);
    composite.scrollViewportTo(sshId, 7);

    expect(routingBackend.resizedSessions, <String>[sshId]);
    expect(routingBackend.writes[sshId], <int>[0x61, 0x62]);
    expect(routingBackend.scrolledSessions, <String>[sshId]);
    expect(routingBackend.scrolledToSessions, <String>[sshId]);
    expect(
      composite.takeFramePacketV1Protobuf(sshId, afterSequence: null),
      <int>[1, 2, 3],
    );
    expect(composite.pollEvents(sshId).single.kind, 'native-event');

    composite.closeSession(sshId);
    composite.closeSession(sandboxId);
    expect(routingBackend.closedSessions, <String>[sshId, sandboxId]);
  });
}

String _takeText(IosSandboxShellBackend backend, String sessionId) {
  return _frameText(_takeFrame(backend, sessionId));
}

Map<String, Object?> _takeFrame(
  IosSandboxShellBackend backend,
  String sessionId,
) {
  final decoded = TerminalFrameTransportCoordinator(
    backend: backend,
  ).take(sessionId);
  expect(decoded, isNotNull);
  final frame = decoded!.frame;
  return <String, Object?>{
    'rows': frame.rows
        .map(
          (row) => <String, Object?>{
            'index': row.index,
            'text': row.text,
            'wrapped': row.wrapped,
          },
        )
        .toList(growable: false),
    'cursor': <String, Object?>{
      'row': frame.cursor.row,
      'col': frame.cursor.col,
      'visible': frame.cursor.visible,
    },
  };
}

String _sessionConfig(String sessionId) {
  return TerminalSessionConfigV1(
    sessionId: sessionId,
    displayName: 'iOS Sandbox',
    config: const TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: '/bin/false'),
    ),
  ).toJsonString();
}

String _sshSessionConfig(String sessionId) {
  return TerminalSessionConfigV1(
    sessionId: sessionId,
    displayName: 'SSH',
    config: const TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: ''),
      connection: TerminalConnectionConfig.ssh(
        host: 'ssh.example.test',
        user: 'operator',
      ),
    ),
  ).toJsonString();
}

String _frameText(Map<String, Object?> frame) {
  final rows = frame['rows']! as List<Object?>;
  return rows
      .cast<Map<String, Object?>>()
      .map((row) => row['text']! as String)
      .join('\n');
}

Map<String, Object?> _cursor(Map<String, Object?> frame) =>
    frame['cursor']! as Map<String, Object?>;

final class _RoutingPtyBackend
    implements
        PtySessionBackend,
        PtyReplaySessionBackend,
        PtySessionConfigV1Backend,
        PtyReplaySessionConfigV1Backend,
        PtySessionFramePacketV1Backend,
        PtyRuntimeCapabilityBackend {
  final List<String> liveConfigs = <String>[];
  final List<String> replayConfigs = <String>[];
  final List<String> closedSessions = <String>[];
  final List<String> resizedSessions = <String>[];
  final Map<String, List<int>> writes = <String, List<int>>{};
  final List<String> scrolledSessions = <String>[];
  final List<String> scrolledToSessions = <String>[];

  @override
  final PtyRuntimeCapabilities runtimeCapabilities =
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
      });

  @override
  int ping() => 1;

  @override
  String createSessionV1(String sessionConfigV1Json) {
    liveConfigs.add(sessionConfigV1Json);
    return 'live-session';
  }

  @override
  String createReplaySessionV1(String sessionConfigV1Json) {
    replayConfigs.add(sessionConfigV1Json);
    return 'replay-session';
  }

  @override
  void replayOutput(String sessionId, List<int> bytes) {}

  @override
  void replayExit(String sessionId, {int? exitCode}) {}

  @override
  void closeSession(String sessionId) {
    closedSessions.add(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    resizedSessions.add(sessionId);
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    writes[sessionId] = List<int>.of(bytes);
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    scrolledSessions.add(sessionId);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    scrolledToSessions.add(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => <PtyEvent>[
    PtyEvent(kind: 'native-event', sessionId: sessionId),
  ];

  @override
  Uint8List takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) => Uint8List.fromList(const <int>[1, 2, 3]);
}

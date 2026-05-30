import 'dart:ffi' as ffi;
import 'dart:io';

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
    expect(bindings.lastSessionId, isNull);
  });

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
      <String, Object?>{
        'kind': 'exit',
        'session_id': ' 8 ',
        'payload': 'bad-payload',
      },
    ]);

    expect(events, hasLength(2));
    expect(events.first.kind, 'started');
    expect(events.first.sessionId, '7');
    expect(events.first.payload, <String, Object?>{'cwd': '/tmp/project'});
    expect(events.last.kind, 'exit');
    expect(events.last.sessionId, '8');
    expect(events.last.payload, isNull);
  });

  test('pty event decoding rejects invalid single events', () {
    expect(
      () => PtyEvent.fromJson(<String, Object?>{'kind': 'started'}),
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
    int pixelHeight,
  ) => 0;

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
  List<PtyEvent> sessionPollEvents(int sessionId) => const [];
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

class _RequestRecordingPtyBindings extends _NoopPtyBindings {
  int? lastSessionId;
  String? lastRequestJson;
  String? response = '{"ok":true}';

  @override
  String? sessionRequestJson(int sessionId, String requestJson) {
    lastSessionId = sessionId;
    lastRequestJson = requestJson;
    return response;
  }
}

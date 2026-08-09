import 'dart:convert';
import 'dart:io';

import 'package:app/features/pty/pty.dart';
import 'package:flutter_test/flutter_test.dart';

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
    sessionId = backend.createSession(
      '{"id":"ios-test","name":"iOS Sandbox","shell":"/bin/false"}',
    );
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
}

String _takeText(IosSandboxShellBackend backend, String sessionId) {
  return _frameText(_takeFrame(backend, sessionId));
}

Map<String, Object?> _takeFrame(
  IosSandboxShellBackend backend,
  String sessionId,
) {
  final raw = backend.takeFrameDiffJson(sessionId);
  expect(raw, isNotNull);
  return jsonDecode(raw!) as Map<String, Object?>;
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

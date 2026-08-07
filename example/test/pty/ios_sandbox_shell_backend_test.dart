import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/pty/pty.dart';

void main() {
  late Directory root;
  late IosSandboxShellBackend backend;
  late String sessionId;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ianvs-ios-shell-test-');
    backend = IosSandboxShellBackend(
      rootDirectory: root,
      clock: () => DateTime.utc(2026, 8, 7, 12, 30),
    );
    sessionId = backend.createSessionV1(
      '{"session_id":"ios-test","config":{}}',
    );
  });

  tearDown(() {
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
}

String _takeText(IosSandboxShellBackend backend, String sessionId) {
  final raw = backend.takeFrameDiffJson(sessionId);
  expect(raw, isNotNull);
  final frame = jsonDecode(raw!) as Map<String, Object?>;
  final rows = frame['rows']! as List<Object?>;
  return rows
      .cast<Map<String, Object?>>()
      .map((row) => row['text'] as String)
      .join('\n');
}

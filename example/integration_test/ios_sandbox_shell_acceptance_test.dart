import 'dart:convert';
import 'dart:io';

import 'package:app/features/pty/pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('iOS native PTY linkage', () {
    late Directory rootDirectory;
    late NativePtyBackend nativeBackend;
    late IosSandboxShellBackend sandboxBackend;
    late String sessionID;

    setUp(() {
      rootDirectory = Directory.systemTemp.createTempSync(
        'ianvs-ios-sandbox-acceptance-',
      );
      nativeBackend = NativePtyBackend.load();
      sandboxBackend = IosSandboxShellBackend(
        rootDirectory: rootDirectory,
        terminalBackend: nativeBackend,
      );
      sessionID = sandboxBackend.createSession(
        '{"id":"ios-acceptance","name":"iOS Acceptance","shell":"/bin/false"}',
      );
    });

    tearDown(() {
      sandboxBackend.closeSession(sessionID);
      if (rootDirectory.existsSync()) {
        rootDirectory.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'loads Rust symbols from the process and drives the sandbox shell',
      (_) async {
        expect(Platform.isIOS, isTrue);
        expect(nativeBackend.ping(), 42);
        _takeText(sandboxBackend, sessionID);

        sandboxBackend.writeInput(
          sessionID,
          utf8.encode('echo simulator-linked > proof.txt; cat proof.txt\r'),
        );

        expect(
          _takeText(sandboxBackend, sessionID),
          contains('simulator-linked'),
        );
        expect(
          File('${rootDirectory.path}/proof.txt').readAsStringSync(),
          'simulator-linked\n',
        );
      },
    );
  });
}

String _takeText(IosSandboxShellBackend backend, String sessionID) {
  final raw = backend.takeFrameDiffJson(sessionID);
  expect(raw, isNotNull);
  final frame = jsonDecode(raw!) as Map<String, Object?>;
  final rows = frame['rows']! as List<Object?>;
  return rows
      .cast<Map<String, Object?>>()
      .map((row) => row['text']! as String)
      .join('\n');
}

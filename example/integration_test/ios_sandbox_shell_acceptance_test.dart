import 'dart:convert';
import 'dart:io';

import 'package:app/features/pty/pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_transport_coordinator.dart';
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
      sessionID = sandboxBackend.createSessionV1(
        const TerminalSessionConfigV1(
          sessionId: 'ios-acceptance',
          displayName: 'iOS Acceptance',
          config: TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/false'),
          ),
        ).toJsonString(),
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
  final decoded = TerminalFrameTransportCoordinator(
    backend: backend,
  ).take(sessionID);
  expect(decoded, isNotNull);
  return decoded!.frame.rows.map((row) => row.text).join('\n');
}

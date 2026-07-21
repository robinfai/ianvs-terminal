import 'dart:convert';

import 'package:app/features/workspace/local_session_descriptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalSessionDescriptor', () {
    test('roundtrips the complete v1 contract without environment values', () {
      final descriptor = TerminalSessionDescriptor(
        id: ' session-1 ',
        profileId: ' default ',
        command: const TerminalSessionCommand(
          program: ' /bin/zsh ',
          arguments: ['-l', '--no-rcs'],
        ),
        cwd: ' /repo ',
        environment: const TerminalSessionEnvironmentMetadata(
          keys: ['TOKEN', 'LANG', 'TOKEN'],
        ),
        title: ' Build ',
        createdAtUtc: DateTime.utc(2026, 7, 21, 4, 30),
        exitState: TerminalSessionExitState.exited,
        exitCode: 17,
        recordingPath: ' /recordings/session-1.ndjson ',
        restartPolicy: TerminalSessionRestartPolicy.relaunch,
      );

      final json = descriptor.toJson();
      final decoded = TerminalSessionDescriptor.fromJson({
        ...json,
        'environment': {
          ...(json['environment']! as Map<String, Object?>),
          'values': {'TOKEN': 'secret-value'},
        },
        'futureField': true,
      });

      expect(json['schemaVersion'], currentTerminalSessionDescriptorVersion);
      expect(jsonEncode(decoded.toJson()), isNot(contains('secret-value')));
      expect(decoded.id, 'session-1');
      expect(decoded.profileId, 'default');
      expect(decoded.command!.program, '/bin/zsh');
      expect(decoded.command!.arguments, ['-l', '--no-rcs']);
      expect(decoded.cwd, '/repo');
      expect(decoded.environment.keys, ['LANG', 'TOKEN']);
      expect(decoded.environment.valuesRedacted, isTrue);
      expect(decoded.title, 'Build');
      expect(decoded.createdAtUtc, DateTime.utc(2026, 7, 21, 4, 30));
      expect(decoded.exitState, TerminalSessionExitState.exited);
      expect(decoded.exitCode, 17);
      expect(decoded.recordingPath, '/recordings/session-1.ndjson');
      expect(decoded.restartPolicy, TerminalSessionRestartPolicy.relaunch);
    });

    test('rejects unsupported descriptor versions without guessing', () {
      expect(
        () => TerminalSessionDescriptor.fromJson(const {
          'schemaVersion': currentTerminalSessionDescriptorVersion + 1,
          'id': 'session-1',
          'profileId': 'default',
        }),
        throwsA(isA<UnsupportedTerminalSessionDescriptorVersion>()),
      );
    });
  });
}

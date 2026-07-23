import 'dart:convert';

import 'package:app/features/workspace/local_terminal_relaunch_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalRelaunchSpec', () {
    test('roundtrips only the launch contract', () {
      const spec = TerminalRelaunchSpec(
        profileId: ' default ',
        command: TerminalRelaunchCommand(
          program: ' /bin/zsh ',
          arguments: <String>['-l', '--no-rcs'],
        ),
        cwd: ' /repo ',
      );

      final json = spec.toJson();
      final decoded = TerminalRelaunchSpec.fromJson(json);

      expect(json.keys, <String>{
        'schemaVersion',
        'contract',
        'profileId',
        'command',
        'cwd',
      });
      expect(json['schemaVersion'], currentTerminalRelaunchSpecVersion);
      expect(json['contract'], terminalRelaunchSpecContract);
      expect(decoded.profileId, 'default');
      expect(decoded.command!.program, '/bin/zsh');
      expect(decoded.command!.arguments, <String>['-l', '--no-rcs']);
      expect(decoded.cwd, '/repo');
    });

    test('legacy descriptors shed runtime and recording metadata', () {
      final migrated = TerminalRelaunchSpec.fromLegacyJson(<Object?, Object?>{
        'profileId': 'default',
        'command': <String, Object?>{
          'program': '/bin/zsh',
          'arguments': <String>['-l'],
        },
        'cwd': '/repo',
        'id': 'descriptor-1',
        'title': 'Build',
        'createdAtUtc': '2026-07-21T04:30:00.000Z',
        'environment': <String, Object?>{
          'keys': <String>['TOKEN'],
          'values': <String, String>{'TOKEN': 'secret-value'},
        },
        'exitState': 'exited',
        'exitCode': 17,
        'recordingPath': '/recordings/session-1.ndjson',
        'restartPolicy': 'never',
      });

      final encoded = jsonEncode(migrated.toJson());
      expect(migrated.profileId, 'default');
      expect(migrated.cwd, '/repo');
      expect(encoded, isNot(contains('descriptor-1')));
      expect(encoded, isNot(contains('Build')));
      expect(encoded, isNot(contains('secret-value')));
      expect(encoded, isNot(contains('recording')));
      expect(encoded, isNot(contains('restartPolicy')));
    });

    test('rejects unsupported versions and contracts', () {
      expect(
        () => TerminalRelaunchSpec.fromJson(const <Object?, Object?>{
          'schemaVersion': currentTerminalRelaunchSpecVersion + 1,
          'contract': terminalRelaunchSpecContract,
          'profileId': 'default',
        }),
        throwsA(isA<UnsupportedTerminalRelaunchSpecVersion>()),
      );
      expect(
        () => TerminalRelaunchSpec.fromJson(const <Object?, Object?>{
          'schemaVersion': currentTerminalRelaunchSpecVersion,
          'contract': 'unknown-contract',
          'profileId': 'default',
        }),
        throwsFormatException,
      );
    });
  });
}

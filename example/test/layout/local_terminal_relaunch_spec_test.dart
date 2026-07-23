import 'dart:convert';

import 'package:app/features/layout/local_terminal_relaunch_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalRelaunchSpec', () {
    test('canonical writes omit compatibility command data', () {
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
        'cwd',
      });
      expect(json['schemaVersion'], currentTerminalRelaunchSpecVersion);
      expect(json['contract'], terminalRelaunchSpecContract);
      expect(decoded.profileId, 'default');
      expect(decoded.command, isNull);
      expect(decoded.cwd, '/repo');
    });

    test('reads command data from existing version one documents', () {
      final decoded = TerminalRelaunchSpec.fromJson(const {
        'schemaVersion': currentTerminalRelaunchSpecVersion,
        'contract': terminalRelaunchSpecContract,
        'profileId': 'default',
        'command': {
          'program': '/bin/zsh',
          'arguments': ['-l'],
        },
        'cwd': '/repo',
      });

      expect(decoded.command!.program, '/bin/zsh');
      expect(decoded.command!.arguments, ['-l']);
      expect(decoded.toJson(), isNot(contains('command')));
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

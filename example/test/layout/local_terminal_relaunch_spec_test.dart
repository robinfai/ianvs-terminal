import 'package:app/features/layout/local_terminal_relaunch_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalRelaunchSpec', () {
    test('round-trips only the profile reference and working directory', () {
      const spec = TerminalRelaunchSpec(profileId: ' default ', cwd: ' /repo ');

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
      expect(decoded.cwd, '/repo');
    });

    test('ignores stale command payloads in current-schema documents', () {
      final decoded = TerminalRelaunchSpec.fromJson({
        ...const TerminalRelaunchSpec(
          profileId: 'default',
          cwd: '/repo',
        ).toJson(),
        'command': {
          'program': '/bin/echo',
          'arguments': ['obsolete'],
        },
      });

      expect(decoded.profileId, 'default');
      expect(decoded.cwd, '/repo');
      expect(decoded.toJson(), isNot(contains('command')));
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

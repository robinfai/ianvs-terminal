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

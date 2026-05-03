import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'package:ianvs_terminal/src/session_launch.dart';

void main() {
  test('ssh command profile rewrites launch program and args', () {
    const profile = TerminalSessionLaunchProfile.sshCommand(
      host: 'prod.example.internal',
      account: 'ops-user',
    );
    const baseConfig = terminal.TerminalSessionConfig(
      launch: terminal.TerminalLaunchConfig(
        program: '/bin/zsh',
        args: <String>['-i'],
        cwd: '/Users/robin',
        env: <String, String>{'TERM': 'xterm-256color'},
      ),
    );

    final config = profile.applyTo(baseConfig);

    expect(config.launch.program, endsWith('ssh'));
    expect(config.launch.args, <String>['ops-user@prod.example.internal']);
    expect(config.launch.cwd, '/Users/robin');
    expect(config.launch.env['TERM'], 'xterm-256color');
  });

  test('invalid ssh json falls back to local shell profile', () {
    final profile = TerminalSessionLaunchProfile.fromJson(<String, Object?>{
      'kind': 'sshCommand',
      'host': '-oProxyCommand=bad',
      'account': 'ops-user',
    });

    expect(profile.isLocalShell, isTrue);
    expect(profile.isSshCommand, isFalse);
  });

  test('invalid ssh host does not rewrite launch config', () {
    const profile = TerminalSessionLaunchProfile.sshCommand(host: '-V');
    const baseConfig = terminal.TerminalSessionConfig(
      launch: terminal.TerminalLaunchConfig(
        program: '/bin/zsh',
        args: <String>['-i'],
        cwd: '/Users/robin',
      ),
    );

    final config = profile.applyTo(baseConfig);

    expect(config.launch.program, '/bin/zsh');
    expect(config.launch.args, <String>['-i']);
  });

  test('host validation rejects ssh options and whitespace', () {
    expect(sshHostValidationError('prod.example.internal'), isNull);
    expect(
      sshHostValidationError('-oProxyCommand=bad'),
      'Host must be a hostname or address, not ssh options.',
    );
    expect(
      sshHostValidationError('prod internal'),
      'Host must be a hostname or address, not ssh options.',
    );
  });
}

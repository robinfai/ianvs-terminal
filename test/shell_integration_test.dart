import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;
import 'package:ianvs_terminal/src/shell_integration.dart';

void main() {
  test('generic shell hook encoder emits hex json dcs', () {
    final encoded = encodeShellHookDcs(<String, Object?>{
      'hook': 'preexec',
      'command': 'echo ianvs',
    });

    expect(encoded, startsWith('\x1bPhook;'));
    expect(encoded, endsWith('\x1b\\'));
    expect(encoded, contains('69616e7673'));
  });

  test('zsh integration sets generated zdotdir and sources user config', () {
    final supportDir = Directory.systemTemp.createTempSync(
      'ianvs_terminal_shell_',
    );
    final originalZdotdir = Directory('${supportDir.path}/user-zdotdir')
      ..createSync(recursive: true);
    addTearDown(() {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    });

    final config = applyShellIntegration(
      const terminal.TerminalSessionConfig(
        launch: terminal.TerminalLaunchConfig(
          program: '/bin/zsh',
          env: <String, String>{'TERM': 'xterm-256color'},
        ),
      ),
      stateDirectory: supportDir,
      environment: <String, String>{
        'HOME': supportDir.path,
        'ZDOTDIR': originalZdotdir.path,
      },
    );

    final zdotdir = Directory('${supportDir.path}/shell-integration/zsh');
    final zshenv = File('${zdotdir.path}/.zshenv');
    final zshrc = File('${zdotdir.path}/.zshrc');

    expect(config.launch.env['ZDOTDIR'], zdotdir.path);
    expect(config.launch.env['FLUTTERM_SHELL_HOOKS'], '1');
    expect(
      config.launch.env['FLUTTERM_ORIGINAL_ZDOTDIR'],
      originalZdotdir.path,
    );
    expect(zshenv.readAsStringSync(), contains('FLUTTERM_ORIGINAL_ZDOTDIR'));
    expect(zshrc.readAsStringSync(), contains('add-zsh-hook preexec'));
    expect(zshrc.readAsStringSync(), contains('hook;'));
    expect(
      zshrc.readAsStringSync(),
      contains('local exit_code=\$?\n    emulate -L zsh'),
    );
  });

  test('non zsh shells are left without shell hook env', () {
    final supportDir = Directory.systemTemp.createTempSync(
      'ianvs_terminal_shell_',
    );
    addTearDown(() {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    });

    final config = applyShellIntegration(
      const terminal.TerminalSessionConfig(
        launch: terminal.TerminalLaunchConfig(
          program: '/bin/bash',
          env: <String, String>{'TERM': 'xterm-256color'},
        ),
      ),
      stateDirectory: supportDir,
      environment: <String, String>{'HOME': supportDir.path},
    );

    expect(config.launch.env.containsKey('ZDOTDIR'), isFalse);
    expect(config.launch.env.containsKey('FLUTTERM_SHELL_HOOKS'), isFalse);
    expect(
      Directory('${supportDir.path}/shell-integration/zsh').existsSync(),
      isFalse,
    );
  });
}

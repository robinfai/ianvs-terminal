import 'dart:io';

import 'package:app/platform/default_terminal_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Linux default terminal shell', () {
    String resolve({
      Map<String, String> environment = const {},
      Set<String> executables = const {'/bin/bash', '/bin/sh'},
      String configuredShell = '',
    }) => resolveDefaultTerminalShell(
      operatingSystem: 'linux',
      environment: environment,
      configuredShell: configuredShell,
      isExecutable: executables.contains,
    );

    test('uses an executable absolute login shell from the environment', () {
      expect(
        resolve(
          environment: {'SHELL': '/usr/bin/fish'},
          executables: {'/usr/bin/fish', '/bin/bash'},
        ),
        '/usr/bin/fish',
      );
    });

    test('supports a program path with spaces without parsing it', () {
      expect(
        resolve(
          environment: {'SHELL': '/opt/user shells/bash'},
          executables: {'/opt/user shells/bash'},
        ),
        '/opt/user shells/bash',
      );
    });

    test('falls back for missing, invalid or non-executable SHELL', () {
      for (final shell in <String?>[
        null,
        '',
        'bash',
        '/missing/zsh',
        '/bin/bash -l',
        '/bin/bash\u0000',
      ]) {
        expect(resolve(environment: {'SHELL': ?shell}), '/bin/bash');
      }
    });

    test('supports merged usr and a POSIX sh-only host', () {
      expect(resolve(executables: {'/usr/bin/bash'}), '/usr/bin/bash');
      expect(resolve(executables: {'/bin/sh'}), '/bin/sh');
      expect(resolve(executables: {'/usr/bin/sh'}), '/usr/bin/sh');
    });

    test('explicit build override remains authoritative', () {
      expect(
        resolve(configuredShell: '/custom/shell', executables: {}),
        '/custom/shell',
      );
    });

    test('fails clearly rather than choosing a missing shell', () {
      expect(() => resolve(executables: {}), throwsStateError);
    });

    test('does not change the Apple default', () {
      for (final platform in ['macos', 'ios']) {
        expect(
          resolveDefaultTerminalShell(
            operatingSystem: platform,
            environment: {'SHELL': '/bin/bash'},
            configuredShell: '',
          ),
          '/bin/zsh',
        );
      }
    });

    test('the real Linux fallback is an executable file', () {
      final shell = resolveDefaultTerminalShell(
        operatingSystem: 'linux',
        environment: const {},
        configuredShell: '',
      );
      expect(File(shell).statSync().type, FileSystemEntityType.file);
      expect(File(shell).statSync().mode & 0x49, isNot(0));
    }, skip: !Platform.isLinux);
  });
}

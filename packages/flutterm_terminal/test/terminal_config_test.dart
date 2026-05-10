import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

void main() {
  test('terminal session config parses legacy profile JSON with warnings', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/bash',
        'args': <Object?>['-l', 42],
        'terminalEmulation': 'vt220',
        'terminal': <String, Object?>{'scrollbackLines': -1},
        'appearance': <String, Object?>{
          'font': <String, Object?>{
            'family': '',
            'fallback': <Object?>['Monaco', ''],
          },
          'colors': <String, Object?>{'foreground': 'not-a-color'},
        },
      },
      defaultProgram: '/bin/zsh',
      onWarning: warnings.add,
    );

    expect(config.launch.program, '/bin/bash');
    expect(config.launch.args, <String>['-l']);
    expect(config.emulation, TerminalEmulation.vt220);
    expect(config.scrollbackLines, defaultTerminalScrollbackLines);
    expect(config.shellIntegration.enabled, isTrue);
    expect(config.display.font.family, terminalPrimaryFontFamily);
    expect(config.display.font.fallback, <String>['Monaco']);
    expect(config.display.colors.foreground, isNull);
    expect(
      warnings.map((warning) => warning.path),
      containsAll(<String>[
        'args[1]',
        'terminal.scrollbackLines',
        'appearance.font.family',
        'appearance.font.fallback[1]',
        'appearance.colors.foreground',
      ]),
    );
  });

  test('terminal session config forwards shell integration settings', () {
    final config = TerminalSessionConfig.fromJson(<String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
      'shellIntegration': <String, Object?>{'enabled': false},
    });

    expect(config.shellIntegration.enabled, isFalse);
    expect(config.toJson()['shellIntegration'], <String, Object?>{
      'enabled': false,
    });
  });

  test('terminal profile JSON validates shell integration settings', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/zsh',
        'shellIntegration': <String, Object?>{'enabled': 'yes'},
      },
      defaultProgram: '/bin/zsh',
      onWarning: warnings.add,
    );

    expect(config.shellIntegration.enabled, isTrue);
    expect(warnings.map((warning) => warning.path), <String>[
      'shellIntegration.enabled',
    ]);
  });
}

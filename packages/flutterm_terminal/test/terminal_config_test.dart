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
}

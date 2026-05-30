import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test('terminal color palette roundtrips grouped special and ansi colors', () {
    const palette = TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#112233',
        background: '#445566',
        cursor: '#778899',
        selection: '#AABBCC',
      ),
      normal: TerminalAnsiColors(
        black: '#010101',
        red: '#020202',
        green: '#030303',
        yellow: '#040404',
        blue: '#050505',
        magenta: '#060606',
        cyan: '#070707',
        white: '#080808',
      ),
      bright: TerminalAnsiColors(
        black: '#111111',
        red: '#121212',
        green: '#131313',
        yellow: '#141414',
        blue: '#151515',
        magenta: '#161616',
        cyan: '#171717',
        white: '#181818',
      ),
    );

    expect(palette.toJson(), <String, Object?>{
      'special': <String, Object?>{
        'foreground': '#112233',
        'background': '#445566',
        'cursor': '#778899',
        'selection': '#AABBCC',
      },
      'normal': <String, Object?>{
        'black': '#010101',
        'red': '#020202',
        'green': '#030303',
        'yellow': '#040404',
        'blue': '#050505',
        'magenta': '#060606',
        'cyan': '#070707',
        'white': '#080808',
      },
      'bright': <String, Object?>{
        'black': '#111111',
        'red': '#121212',
        'green': '#131313',
        'yellow': '#141414',
        'blue': '#151515',
        'magenta': '#161616',
        'cyan': '#171717',
        'white': '#181818',
      },
    });

    final roundTrip = TerminalColorPalette.fromJson(palette.toJson());
    expect(roundTrip.special.foreground, '#112233');
    expect(roundTrip.special.background, '#445566');
    expect(roundTrip.special.cursor, '#778899');
    expect(roundTrip.special.selection, '#AABBCC');
    expect(roundTrip.normal.red, '#020202');
    expect(roundTrip.normal.blue, '#050505');
    expect(roundTrip.bright.red, '#121212');
    expect(roundTrip.bright.white, '#181818');
  });

  test('terminal color palette ignores invalid direct json colors', () {
    final palette = TerminalColorPalette.fromJson(const <String, Object?>{
      'special': <String, Object?>{
        'foreground': ' #112233 ',
        'background': '   ',
        'cursor': 'not-a-color',
        'selection': 42,
      },
      'normal': <String, Object?>{'red': ' #020202 ', 'blue': 'bad'},
      'bright': <String, Object?>{'white': '#abcdef'},
    }).resolveWith();

    expect(palette.special.foreground, '#112233');
    expect(palette.special.background, defaultTerminalSpecialColors.background);
    expect(palette.special.cursor, defaultTerminalSpecialColors.cursor);
    expect(palette.special.selection, defaultTerminalSpecialColors.selection);
    expect(palette.normal.red, '#020202');
    expect(palette.normal.blue, defaultTerminalAnsiColors.blue);
    expect(palette.bright.white, '#ABCDEF');
  });

  test('terminal font config trims direct json strings', () {
    final font = TerminalFontConfig.fromJson(const <String, Object?>{
      'family': '  JetBrains Mono  ',
      'fallback': <Object?>['  Monaco  ', '', 7],
    });
    final blank = TerminalFontConfig.fromJson(const <String, Object?>{
      'family': '   ',
      'fallback': <Object?>['   ', 7],
    });

    expect(font.family, 'JetBrains Mono');
    expect(font.fallback, <String>['Monaco']);
    expect(blank.family, terminalPrimaryFontFamily);
    expect(blank.fallback, terminalFontFamilyFallback);
  });

  test('terminal launch config trims direct json string fields', () {
    final launch = TerminalLaunchConfig.fromJson(const <String, Object?>{
      'program': '  /bin/zsh  ',
      'env': <Object?, Object?>{
        ' TERM ': 'xterm-256color',
        'EMPTY': '',
        'BAD_BOOL': false,
        'BAD_NULL': null,
        '   ': 'blank-key',
        7: 'numeric-key',
      },
      'cwd': '  /tmp/project  ',
    });
    final blank = TerminalLaunchConfig.fromJson(const <String, Object?>{
      'program': '   ',
      'cwd': '   ',
    });

    expect(launch.program, '/bin/zsh');
    expect(launch.env, const <String, String>{
      'TERM': 'xterm-256color',
      'EMPTY': '',
    });
    expect(launch.cwd, '/tmp/project');
    expect(blank.program, '');
    expect(blank.cwd, isNull);
  });

  test('terminal session config parses grouped profile colors', () {
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
          'colors': <String, Object?>{
            'special': <String, Object?>{
              'foreground': '#112233',
              'background': '#445566',
              'cursor': '#778899',
              'selection': '#AABBCC',
            },
            'normal': <String, Object?>{
              'black': '#010101',
              'red': '#020202',
              'green': '#030303',
              'yellow': '#040404',
              'blue': '#050505',
              'magenta': '#060606',
              'cyan': '#070707',
              'white': '#080808',
            },
            'bright': <String, Object?>{
              'black': '#111111',
              'red': '#121212',
              'green': '#131313',
              'yellow': '#141414',
              'blue': '#151515',
              'magenta': '#161616',
              'cyan': '#171717',
              'white': '#181818',
            },
          },
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
    expect(config.display.colors.special.foreground, '#112233');
    expect(config.display.colors.special.background, '#445566');
    expect(config.display.colors.special.cursor, '#778899');
    expect(config.display.colors.special.selection, '#AABBCC');
    expect(config.display.colors.normal.blue, '#050505');
    expect(config.display.colors.bright.white, '#181818');
    expect(
      warnings.map((warning) => warning.path),
      containsAll(<String>[
        'args[1]',
        'terminal.scrollbackLines',
        'appearance.font.family',
        'appearance.font.fallback[1]',
      ]),
    );
  });

  test('terminal session config trims nullable cwd fields', () {
    final warnings = <TerminalConfigWarning>[];

    final trimmed = TerminalSessionConfig.fromProfileJson(
      const <String, Object?>{
        'launch': <String, Object?>{
          'program': '/bin/zsh',
          'cwd': '  /tmp/project  ',
        },
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );
    final blank = TerminalSessionConfig.fromProfileJson(
      const <String, Object?>{
        'launch': <String, Object?>{'program': '/bin/zsh', 'cwd': '   '},
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );

    expect(trimmed.launch.cwd, '/tmp/project');
    expect(blank.launch.cwd, isNull);
    expect(warnings.map((warning) => warning.path), contains('launch.cwd'));
  });

  test(
    'terminal session config ignores legacy flat profile color fields and warns',
    () {
      final warnings = <TerminalConfigWarning>[];

      final config = TerminalSessionConfig.fromProfileJson(
        <String, Object?>{
          'shell': '/bin/bash',
          'appearance': <String, Object?>{
            'colors': <String, Object?>{
              'foreground': '#112233',
              'background': '#445566',
              'cursor': '#778899',
              'selection': '#AABBCC',
            },
          },
        },
        defaultProgram: '/bin/zsh',
        onWarning: warnings.add,
      );

      expect(config.display.colors.special.foreground, isNull);
      expect(config.display.colors.special.background, isNull);
      expect(config.display.colors.special.cursor, isNull);
      expect(config.display.colors.special.selection, isNull);
      expect(
        warnings.map((warning) => warning.path),
        containsAll(<String>[
          'appearance.colors.foreground',
          'appearance.colors.background',
          'appearance.colors.cursor',
          'appearance.colors.selection',
        ]),
      );
    },
  );

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

  test('terminal session config defaults malformed boolean fields', () {
    final config = TerminalSessionConfig.fromJson(<String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
      'shellIntegration': <String, Object?>{'enabled': 'yes'},
      'appearance': <String, Object?>{
        'cursor': <String, Object?>{'blink': 'no'},
      },
      'interaction': <String, Object?>{'copyOnSelect': 'yes'},
    });

    expect(config.shellIntegration.enabled, isTrue);
    expect(config.display.cursor.blink, isTrue);
    expect(config.interaction.copyOnSelect, isFalse);
  });

  test('terminal session config defaults invalid font dimensions', () {
    final config = TerminalSessionConfig.fromJson(<String, Object?>{
      'appearance': <String, Object?>{
        'font': <String, Object?>{'size': double.infinity, 'lineHeight': -1},
      },
    });

    expect(config.display.font.size, terminalFontSize);
    expect(config.display.font.lineHeight, terminalLineHeight);
  });

  test('terminal session config defaults invalid scrollback lines', () {
    final config = TerminalSessionConfig.fromJson(<String, Object?>{
      'terminal': <String, Object?>{'scrollbackLines': -1},
    });
    final fractional = TerminalSessionConfig.fromJson(<String, Object?>{
      'terminal': <String, Object?>{'scrollbackLines': 20.5},
    });

    expect(config.scrollbackLines, defaultTerminalScrollbackLines);
    expect(fractional.scrollbackLines, defaultTerminalScrollbackLines);
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

  test('terminal profile JSON warns for non-finite font dimensions', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/zsh',
        'appearance': <String, Object?>{
          'font': <String, Object?>{
            'size': double.infinity,
            'lineHeight': double.nan,
          },
        },
      },
      defaultProgram: '/bin/zsh',
      onWarning: warnings.add,
    );

    expect(config.display.font.size, terminalFontSize);
    expect(config.display.font.lineHeight, terminalLineHeight);
    expect(warnings.map((warning) => warning.path), <String>[
      'appearance.font.size',
      'appearance.font.lineHeight',
    ]);
  });

  test('terminal profile JSON warns for invalid scrollback lines', () {
    final warnings = <TerminalConfigWarning>[];
    final fractionalWarnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/zsh',
        'terminal': <String, Object?>{'scrollbackLines': double.infinity},
      },
      defaultProgram: '/bin/zsh',
      onWarning: warnings.add,
    );
    final fractional = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/zsh',
        'terminal': <String, Object?>{'scrollbackLines': 20.5},
      },
      defaultProgram: '/bin/zsh',
      onWarning: fractionalWarnings.add,
    );

    expect(config.scrollbackLines, defaultTerminalScrollbackLines);
    expect(warnings.map((warning) => warning.path), <String>[
      'terminal.scrollbackLines',
    ]);
    expect(fractional.scrollbackLines, defaultTerminalScrollbackLines);
    expect(fractionalWarnings.map((warning) => warning.path), <String>[
      'terminal.scrollbackLines',
    ]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test('SSH connection roundtrips forwarding and removes every secret', () {
    const connection = TerminalConnectionConfig.ssh(
      host: 'ssh.example.test',
      user: 'operator',
      auth: TerminalSshAuthMethod.keyboardInteractive,
      password: 'password',
      privateKeys: <String>['/keys/target_ed25519'],
      privateKeyPassphrase: 'passphrase',
      proxyJump: 'jump-a,jump-b',
      proxyJumpProfiles: <TerminalSshJumpConfig>[
        TerminalSshJumpConfig(
          host: 'jump-a.internal',
          user: 'jump-user',
          port: 2222,
          auth: TerminalSshAuthMethod.publicKey,
          password: 'jump-password',
          privateKeys: <String>['/keys/jump_ed25519'],
          privateKeyPassphrase: 'jump-passphrase',
          hostKeyPolicy: TerminalSshHostKeyPolicy.acceptNew,
          knownHostsFile: '/known/jump_hosts',
          connectTimeoutSeconds: 12,
          keepaliveSeconds: 20,
          keepaliveCountMax: 4,
        ),
      ],
      portForwards: <TerminalSshPortForwardConfig>[
        TerminalSshPortForwardConfig(
          type: TerminalSshPortForwardType.remote,
          bindHost: '127.0.0.1',
          bindPort: 9000,
          targetHost: '127.0.0.1',
          targetPort: 9001,
        ),
      ],
      agentForwarding: true,
      x11Forwarding: true,
      x11TargetHost: '127.0.0.1',
      x11TargetPort: 6000,
      x11AuthCookie: 'x11-cookie',
    );

    final decoded = TerminalConnectionConfig.fromJson(connection.toJson());
    final redacted = connection.withoutSensitiveFields();
    final persisted = connection.toJson(includeSensitiveFields: false);
    final persistedJump =
        (persisted['proxyJumpProfiles']! as List).single as Map;

    expect(decoded.auth, TerminalSshAuthMethod.keyboardInteractive);
    expect(decoded.proxyJump, 'jump-a,jump-b');
    expect(decoded.privateKeys, <String>['/keys/target_ed25519']);
    expect(decoded.proxyJumpProfiles, hasLength(1));
    expect(decoded.proxyJumpProfiles.single.host, 'jump-a.internal');
    expect(decoded.proxyJumpProfiles.single.user, 'jump-user');
    expect(decoded.proxyJumpProfiles.single.port, 2222);
    expect(
      decoded.proxyJumpProfiles.single.auth,
      TerminalSshAuthMethod.publicKey,
    );
    expect(decoded.proxyJumpProfiles.single.password, 'jump-password');
    expect(decoded.proxyJumpProfiles.single.privateKeys, <String>[
      '/keys/jump_ed25519',
    ]);
    expect(
      decoded.proxyJumpProfiles.single.privateKeyPassphrase,
      'jump-passphrase',
    );
    expect(
      decoded.proxyJumpProfiles.single.hostKeyPolicy,
      TerminalSshHostKeyPolicy.acceptNew,
    );
    expect(decoded.portForwards.single.type, TerminalSshPortForwardType.remote);
    expect(decoded.agentForwarding, isTrue);
    expect(decoded.x11AuthCookie, 'x11-cookie');
    expect(redacted.password, isNull);
    expect(redacted.privateKeyPassphrase, isNull);
    expect(redacted.x11AuthCookie, isNull);
    expect(redacted.proxyJumpProfiles.single.password, isNull);
    expect(redacted.proxyJumpProfiles.single.privateKeyPassphrase, isNull);
    expect(persisted, isNot(contains('password')));
    expect(persisted, isNot(contains('privateKeyPassphrase')));
    expect(persisted, isNot(contains('x11AuthCookie')));
    expect(persistedJump, isNot(contains('password')));
    expect(persistedJump, isNot(contains('privateKeyPassphrase')));
    expect(persistedJump['privateKeys'], <String>['/keys/jump_ed25519']);
  });

  test('terminal color palette roundtrips grouped special and ansi colors', () {
    const palette = TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#112233',
        background: '#445566',
        cursor: '#778899',
        selection: '#AABBCC',
        tab: '#CCDDEE',
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
        'tab': '#CCDDEE',
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
    expect(roundTrip.special.tab, '#CCDDEE');
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
        'tab': ' #ccddff ',
      },
      'normal': <String, Object?>{'red': ' #020202 ', 'blue': 'bad'},
      'bright': <String, Object?>{'white': '#abcdef'},
    }).resolveWith();

    expect(palette.special.foreground, '#112233');
    expect(palette.special.background, defaultTerminalSpecialColors.background);
    expect(palette.special.cursor, defaultTerminalSpecialColors.cursor);
    expect(palette.special.selection, defaultTerminalSpecialColors.selection);
    expect(palette.special.tab, '#CCDDFF');
    expect(palette.normal.red, '#020202');
    expect(palette.normal.blue, defaultTerminalAnsiColors.blue);
    expect(palette.bright.white, '#ABCDEF');
  });

  test('default terminal background uses the dark canvas base color', () {
    expect(defaultTerminalSpecialColors.background, '#000000');
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

  test('terminal font config caps direct json fallback entries', () {
    final font = TerminalFontConfig.fromJson(<String, Object?>{
      'fallback': <Object?>[
        for (
          var index = 0;
          index < maxTerminalFontFallbackFamilies + 2;
          index += 1
        )
          ' Font $index ',
      ],
    });

    expect(font.fallback, hasLength(maxTerminalFontFallbackFamilies));
    expect(font.fallback.first, 'Font 0');
    expect(font.fallback.last, 'Font ${maxTerminalFontFallbackFamilies - 1}');
  });

  test('terminal font config scans direct fallback past invalid entries', () {
    final font = TerminalFontConfig.fromJson(<String, Object?>{
      'fallback': <Object?>[
        for (var index = 0; index < maxTerminalFontFallbackFamilies; index += 1)
          '   ',
        for (var index = 0; index < maxTerminalFontFallbackFamilies; index += 1)
          ' Font $index ',
      ],
    });

    expect(font.fallback, hasLength(maxTerminalFontFallbackFamilies));
    expect(font.fallback.first, 'Font 0');
    expect(font.fallback.last, 'Font ${maxTerminalFontFallbackFamilies - 1}');
  });

  test('terminal font config defaults invalid direct dimensions', () {
    const invalid = TerminalFontConfig(
      size: double.nan,
      lineHeight: double.infinity,
    );
    const nonPositive = TerminalFontConfig(size: 0, lineHeight: -1);
    const valid = TerminalFontConfig(size: 15, lineHeight: 1.3);

    expect(invalid.size, terminalFontSize);
    expect(invalid.lineHeight, terminalLineHeight);
    expect(nonPositive.size, terminalFontSize);
    expect(nonPositive.lineHeight, terminalLineHeight);
    expect(valid.size, 15);
    expect(valid.lineHeight, 1.3);
  });

  test('terminal session config normalizes direct enum tokens', () {
    final config = TerminalSessionConfig.fromJson(const <String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
      'terminal': <String, Object?>{'emulation': ' VT220 '},
      'appearance': <String, Object?>{
        'cursor': <String, Object?>{'shape': ' Beam '},
      },
      'interaction': <String, Object?>{
        'copyOnSelect': true,
        'optionDragMode': ' Normal_Selection ',
      },
    });

    expect(config.emulation, TerminalEmulation.vt220);
    expect(config.display.cursor.shape, TerminalCursorShape.beam);
    expect(config.interaction.copyOnSelect, isTrue);
    expect(
      config.interaction.optionDragMode,
      TerminalOptionDragMode.normalSelection,
    );
  });

  test('terminal session config roundtrips graphics settings', () {
    final config = TerminalSessionConfig.fromJson(const <String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
      'terminal': <String, Object?>{
        'graphics': <String, Object?>{
          'enabled': false,
          'advertise': 'kitty',
          'maxImageBytes': 4096,
          'maxTotalBytes': 8192,
        },
      },
    });

    expect(config.graphics.enabled, isFalse);
    expect(config.graphics.advertise, 'kitty');
    expect(config.graphics.maxImageBytes, 4096);
    expect(config.graphics.maxTotalBytes, 8192);
    expect(
      config.toJson()['terminal'],
      containsPair('graphics', <String, Object?>{
        'enabled': false,
        'advertise': 'kitty',
        'maxImageBytes': 4096,
        'maxTotalBytes': 8192,
      }),
    );

    final profile = TerminalSessionConfig.fromProfileJson(
      const <String, Object?>{
        'shell': '/bin/zsh',
        'terminal': <String, Object?>{
          'graphics': <String, Object?>{
            'enabled': true,
            'advertise': 'auto',
            'maxImageBytes': 1024,
            'maxTotalBytes': 2048,
          },
        },
      },
      defaultProgram: '/bin/sh',
    );

    expect(profile.graphics.enabled, isTrue);
    expect(profile.graphics.advertise, 'auto');
    expect(profile.graphics.maxImageBytes, 1024);
    expect(profile.graphics.maxTotalBytes, 2048);

    final defaultGraphics = TerminalSessionConfig.fromProfileJson(
      const <String, Object?>{'shell': '/bin/zsh'},
      defaultProgram: '/bin/sh',
    );
    expect(defaultGraphics.graphics.enabled, isTrue);
    expect(defaultGraphics.graphics.advertise, 'kitty');
  });

  test('terminal session config keeps OSC 72 opt-in and roundtrips it', () {
    final denied = TerminalSessionConfig.fromJson(const <String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
    });
    final enabled = TerminalSessionConfig.fromJson(const <String, Object?>{
      'launch': <String, Object?>{'program': '/bin/zsh'},
      'terminal': <String, Object?>{'dragDropEnabled': true},
    });

    expect(denied.dragDropEnabled, isFalse);
    expect(enabled.dragDropEnabled, isTrue);
    expect(enabled.toJson()['terminal'], containsPair('dragDropEnabled', true));
  });

  test('terminal launch config trims direct json string fields', () {
    final launch = TerminalLaunchConfig.fromJson(const <String, Object?>{
      'program': '  /bin/zsh  ',
      'args': <Object?>['  -l  ', '   ', 42, ' --noprofile '],
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
    expect(launch.args, const ['-l', '--noprofile']);
    expect(launch.env, const <String, String>{
      'TERM': 'xterm-256color',
      'EMPTY': '',
    });
    expect(launch.cwd, '/tmp/project');
    expect(blank.program, '');
    expect(blank.cwd, isNull);
  });

  test('terminal launch config caps direct json args and env entries', () {
    final launch = TerminalLaunchConfig.fromJson(<String, Object?>{
      'program': '/bin/zsh',
      'args': <Object?>[
        for (var index = 0; index < maxTerminalLaunchArgs + 2; index += 1)
          'arg-$index',
      ],
      'env': <Object?, Object?>{
        for (
          var index = 0;
          index < maxTerminalEnvironmentEntries + 2;
          index += 1
        )
          'KEY_$index': 'value-$index',
      },
    });

    expect(launch.args, hasLength(maxTerminalLaunchArgs));
    expect(launch.args.last, 'arg-${maxTerminalLaunchArgs - 1}');
    expect(launch.env, hasLength(maxTerminalEnvironmentEntries));
    expect(
      launch.env['KEY_${maxTerminalEnvironmentEntries - 1}'],
      'value-${maxTerminalEnvironmentEntries - 1}',
    );
    expect(launch.env, isNot(contains('KEY_$maxTerminalEnvironmentEntries')));
  });

  test(
    'terminal launch config scans direct json args and env past invalids',
    () {
      final launch = TerminalLaunchConfig.fromJson(<String, Object?>{
        'program': '/bin/zsh',
        'args': <Object?>[
          for (var index = 0; index < maxTerminalLaunchArgs; index += 1) '   ',
          for (var index = 0; index < maxTerminalLaunchArgs; index += 1)
            ' arg-$index ',
        ],
        'env': <Object?, Object?>{
          for (var index = 0; index < maxTerminalEnvironmentEntries; index += 1)
            'BAD_$index': false,
          for (var index = 0; index < maxTerminalEnvironmentEntries; index += 1)
            ' KEY_$index ': 'value-$index',
        },
      });

      expect(launch.args, hasLength(maxTerminalLaunchArgs));
      expect(launch.args.first, 'arg-0');
      expect(launch.args.last, 'arg-${maxTerminalLaunchArgs - 1}');
      expect(launch.env, hasLength(maxTerminalEnvironmentEntries));
      expect(launch.env['KEY_0'], 'value-0');
      expect(
        launch.env['KEY_${maxTerminalEnvironmentEntries - 1}'],
        'value-${maxTerminalEnvironmentEntries - 1}',
      );
      expect(launch.env, isNot(contains('BAD_0')));
    },
  );

  test('terminal profile JSON normalizes enum tokens', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      const <String, Object?>{
        'shell': '/bin/zsh',
        'terminal': <String, Object?>{'emulation': ' VT220 '},
        'appearance': <String, Object?>{
          'cursor': <String, Object?>{'shape': ' Underline '},
        },
        'interaction': <String, Object?>{
          'optionDragMode': ' Normal_Selection ',
        },
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );

    expect(config.emulation, TerminalEmulation.vt220);
    expect(config.display.cursor.shape, TerminalCursorShape.underline);
    expect(
      config.interaction.optionDragMode,
      TerminalOptionDragMode.normalSelection,
    );
    expect(warnings, isEmpty);
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
              'tab': '#CCDDEE',
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
    expect(config.display.colors.special.tab, '#CCDDEE');
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

  test('terminal profile JSON caps collection fields with warnings', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'launch': <String, Object?>{
          'program': '/bin/zsh',
          'args': <Object?>[
            for (var index = 0; index < maxTerminalLaunchArgs + 2; index += 1)
              'arg-$index',
          ],
          'env': <Object?, Object?>{
            for (
              var index = 0;
              index < maxTerminalEnvironmentEntries + 2;
              index += 1
            )
              'KEY_$index': 'value-$index',
          },
        },
        'appearance': <String, Object?>{
          'font': <String, Object?>{
            'fallback': <Object?>[
              for (
                var index = 0;
                index < maxTerminalFontFallbackFamilies + 2;
                index += 1
              )
                'Font $index',
            ],
          },
        },
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );

    expect(config.launch.args, hasLength(maxTerminalLaunchArgs));
    expect(config.launch.env, hasLength(maxTerminalEnvironmentEntries));
    expect(
      config.display.font.fallback,
      hasLength(maxTerminalFontFallbackFamilies),
    );
    expect(
      warnings.map((warning) => warning.path),
      containsAll(<String>[
        'launch.args',
        'launch.env',
        'appearance.font.fallback',
      ]),
    );
    expect(
      warnings.map((warning) => warning.fallbackSummary),
      containsAll(<String>[
        'loaded first $maxTerminalLaunchArgs valid entries',
        'loaded first $maxTerminalEnvironmentEntries valid entries',
        'loaded first $maxTerminalFontFallbackFamilies valid fallback font entries',
      ]),
    );
  });

  test('terminal profile JSON scans launch entries past invalids', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'launch': <String, Object?>{
          'program': '/bin/zsh',
          'args': <Object?>[
            for (var index = 0; index < maxTerminalLaunchArgs; index += 1) '',
            for (var index = 0; index < maxTerminalLaunchArgs; index += 1)
              'arg-$index',
          ],
          'env': <Object?, Object?>{
            for (
              var index = 0;
              index < maxTerminalEnvironmentEntries;
              index += 1
            )
              'BAD_$index': false,
            for (
              var index = 0;
              index < maxTerminalEnvironmentEntries;
              index += 1
            )
              ' KEY_$index ': 'value-$index',
          },
        },
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );

    expect(config.launch.args, hasLength(maxTerminalLaunchArgs));
    expect(config.launch.args.first, 'arg-0');
    expect(config.launch.args.last, 'arg-${maxTerminalLaunchArgs - 1}');
    expect(config.launch.env, hasLength(maxTerminalEnvironmentEntries));
    expect(config.launch.env['KEY_0'], 'value-0');
    expect(
      config.launch.env['KEY_${maxTerminalEnvironmentEntries - 1}'],
      'value-${maxTerminalEnvironmentEntries - 1}',
    );
    expect(config.launch.env, isNot(contains('BAD_0')));
    expect(
      warnings.map((warning) => warning.fallbackSummary),
      containsAll(<String>[
        'loaded first $maxTerminalLaunchArgs valid entries',
        'loaded first $maxTerminalEnvironmentEntries valid entries',
      ]),
    );
  });

  test('terminal profile JSON scans font fallback past invalid entries', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'launch': const <String, Object?>{'program': '/bin/zsh'},
        'appearance': <String, Object?>{
          'font': <String, Object?>{
            'fallback': <Object?>[
              for (
                var index = 0;
                index < maxTerminalFontFallbackFamilies;
                index += 1
              )
                '   ',
              for (
                var index = 0;
                index < maxTerminalFontFallbackFamilies;
                index += 1
              )
                ' Font $index ',
            ],
          },
        },
      },
      defaultProgram: '/bin/sh',
      onWarning: warnings.add,
    );

    expect(
      config.display.font.fallback,
      hasLength(maxTerminalFontFallbackFamilies),
    );
    expect(config.display.font.fallback.first, 'Font 0');
    expect(
      config.display.font.fallback.last,
      'Font ${maxTerminalFontFallbackFamilies - 1}',
    );
    expect(
      warnings.map((warning) => warning.fallbackSummary),
      contains(
        'loaded first $maxTerminalFontFallbackFamilies valid fallback font entries',
      ),
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
              'tab': '#CCDDEE',
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
      expect(config.display.colors.special.tab, isNull);
      expect(
        warnings.map((warning) => warning.path),
        containsAll(<String>[
          'appearance.colors.foreground',
          'appearance.colors.background',
          'appearance.colors.cursor',
          'appearance.colors.selection',
          'appearance.colors.tab',
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

  test('terminal session config caps excessive scrollback lines', () {
    const constructed = TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: '/bin/zsh'),
      scrollbackLines: maxTerminalScrollbackLines + 1,
    );
    final fromJson = TerminalSessionConfig.fromJson(<String, Object?>{
      'terminal': <String, Object?>{
        'scrollbackLines': maxTerminalScrollbackLines + 1,
      },
    });
    const options = TerminalOptions(scrollback: maxTerminalScrollbackLines + 1);

    expect(constructed.scrollbackLines, maxTerminalScrollbackLines);
    expect(constructed.toJson()['terminal'], <String, Object?>{
      'emulation': 'xterm256',
      'scrollbackLines': maxTerminalScrollbackLines,
      'graphics': const TerminalGraphicsConfig().toJson(),
      'dragDropEnabled': false,
    });
    expect(fromJson.scrollbackLines, maxTerminalScrollbackLines);
    expect(options.scrollback, maxTerminalScrollbackLines);
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

  test('terminal profile JSON warns and caps excessive scrollback lines', () {
    final warnings = <TerminalConfigWarning>[];

    final config = TerminalSessionConfig.fromProfileJson(
      <String, Object?>{
        'shell': '/bin/zsh',
        'terminal': <String, Object?>{
          'scrollbackLines': maxTerminalScrollbackLines + 1,
        },
      },
      defaultProgram: '/bin/zsh',
      onWarning: warnings.add,
    );

    expect(config.scrollbackLines, maxTerminalScrollbackLines);
    expect(warnings, hasLength(1));
    expect(warnings.single.path, 'terminal.scrollbackLines');
    expect(
      warnings.single.fallbackSummary,
      'clamped to maximum value $maxTerminalScrollbackLines',
    );
  });
}

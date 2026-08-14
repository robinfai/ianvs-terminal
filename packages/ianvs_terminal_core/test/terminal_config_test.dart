import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  test('current terminal config round-trips its exact nested shape', () {
    const config = TerminalSessionConfig(
      launch: TerminalLaunchConfig(
        program: '/bin/zsh',
        args: <String>['-l'],
        env: <String, String>{'LANG': 'C.UTF-8'},
        cwd: '/tmp/project',
      ),
      scrollbackLines: 1234,
      graphics: TerminalGraphicsConfig(
        enabled: true,
        advertise: 'kitty',
        maxImageBytes: 4096,
        maxTotalBytes: 8192,
      ),
      dragDropEnabled: true,
      shellIntegration: TerminalShellIntegrationConfig(enabled: false),
      display: TerminalDisplayConfig(
        font: TerminalFontConfig(
          family: 'Menlo',
          fallback: <String>['Monaco'],
          size: 15,
          lineHeight: 1.3,
        ),
        colors: TerminalColorPalette(
          special: TerminalSpecialColors(
            foreground: '#112233',
            background: '#445566',
          ),
          normal: TerminalAnsiColors(red: '#AA0000'),
          bright: TerminalAnsiColors(red: '#FF0000'),
        ),
        cursor: TerminalCursorConfig(
          shape: TerminalCursorShape.beam,
          blink: false,
        ),
      ),
      interaction: TerminalInteractionConfig(
        copyOnSelect: true,
        optionDragMode: TerminalOptionDragMode.normalSelection,
      ),
    );

    final decoded = TerminalSessionConfig.fromJson(config.toJson());

    expect(decoded.launch.program, '/bin/zsh');
    expect(decoded.launch.args, const <String>['-l']);
    expect(decoded.launch.env, const <String, String>{'LANG': 'C.UTF-8'});
    expect(decoded.scrollbackLines, 1234);
    expect(decoded.graphics.maxTotalBytes, 8192);
    expect(decoded.dragDropEnabled, isTrue);
    expect(decoded.shellIntegration.enabled, isFalse);
    expect(decoded.display.font.family, 'Menlo');
    expect(decoded.display.colors.special.foreground, '#112233');
    expect(decoded.display.cursor.shape, TerminalCursorShape.beam);
    expect(decoded.interaction.copyOnSelect, isTrue);
  });

  test(
    'current parser rejects predecessor, unknown, and case-alias fields',
    () {
      for (final mutation in <void Function(Map<String, Object?>)>{
        (json) => json['shell'] = '/bin/zsh',
        (json) => json['terminalEmulation'] = 'vt220',
        (json) => json['Launch'] = json.remove('launch'),
        (json) => (json['launch']! as Map<String, Object?>)['Program'] =
            (json['launch']! as Map<String, Object?>).remove('program'),
        (json) =>
            ((json['appearance']! as Map<String, Object?>)['colors']!
                    as Map<String, Object?>)['foreground'] =
                '#112233',
      }) {
        final json = const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ).toJson();
        mutation(json);
        expect(
          () => TerminalSessionConfig.fromJson(json),
          throwsFormatException,
        );
      }
    },
  );

  test('current parser rejects unknown nested SSH fields', () {
    final json = const TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: ''),
      connection: TerminalConnectionConfig.ssh(
        host: 'host.example',
        user: 'user',
      ),
    ).toJson();
    final connection = json['connection']! as Map<String, Object?>;
    final jump = const TerminalSshJumpConfig(
      host: 'jump.example',
      user: 'jump',
    ).toJson();
    jump['legacyAuth'] = true;
    connection['proxyJumpProfiles'] = <Object?>[
      <String, Object?>{...jump},
    ];

    expect(() => TerminalSessionConfig.fromJson(json), throwsFormatException);
  });

  test('SSH connection redaction removes every transient secret', () {
    const connection = TerminalConnectionConfig.ssh(
      host: 'target.example',
      user: 'operator',
      password: 'target-password',
      privateKeys: <String>['target-private-key'],
      privateKeyPassphrase: 'target-passphrase',
      proxyJumpProfiles: <TerminalSshJumpConfig>[
        TerminalSshJumpConfig(
          host: 'jump.example',
          user: 'jump',
          password: 'jump-password',
          privateKeys: <String>['jump-private-key'],
          privateKeyPassphrase: 'jump-passphrase',
        ),
      ],
      x11AuthCookie: '00112233445566778899aabbccddeeff',
    );

    final json = connection.toJson(includeSensitiveFields: false);

    expect(json, isNot(contains('password')));
    expect(json, isNot(contains('privateKeys')));
    expect(json, isNot(contains('privateKeyPassphrase')));
    expect(json, isNot(contains('x11AuthCookie')));
    final jumpProfiles = switch (json['proxyJumpProfiles']) {
      final List<Object?> value => value,
      _ => fail('proxyJumpProfiles must be a list'),
    };
    final jump = switch (jumpProfiles.single) {
      final Map<String, Object?> value => value,
      _ => fail('proxyJumpProfiles entries must be objects'),
    };
    expect(jump, isNot(contains('password')));
    expect(jump['privateKeys'], const <String>['jump-private-key']);
    expect(jump, isNot(contains('privateKeyPassphrase')));
  });

  test('direct collection decoders remain bounded', () {
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
    expect(launch.env, hasLength(maxTerminalEnvironmentEntries));
  });

  test('terminal font dimensions and scrollback stay bounded', () {
    const invalidFont = TerminalFontConfig(
      size: double.nan,
      lineHeight: double.infinity,
    );
    const config = TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: '/bin/zsh'),
      scrollbackLines: maxTerminalScrollbackLines + 1,
    );

    expect(invalidFont.size, terminalFontSize);
    expect(invalidFont.lineHeight, terminalLineHeight);
    expect(config.scrollbackLines, maxTerminalScrollbackLines);
  });
}

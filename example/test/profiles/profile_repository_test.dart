import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/terminal/terminal_defaults.dart';

void main() {
  test(
    'profile repository persists profiles to disk without legacy default field',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles',
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_profiles.json');

      final document = TerminalProfilesDocument(
        profiles: [
          defaultTerminalProfile().copyWith(
            name: 'Custom Shell',
            tags: const ['work', 'prod'],
            triggers: const [
              TerminalProfileTrigger(pattern: 'ERROR'),
              TerminalProfileTrigger(
                pattern: 'Password:',
                action: TerminalProfileTriggerAction.sendText,
                value: 'secret\n',
              ),
            ],
            switchRules: const [
              TerminalProfileSwitchRule(
                kind: TerminalProfileSwitchRuleKind.hostname,
                pattern: '*.prod.example.com',
              ),
              TerminalProfileSwitchRule(
                kind: TerminalProfileSwitchRuleKind.directory,
                pattern: '/srv/app',
              ),
            ],
          ),
        ],
      );

      await repository.save(document);
      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(loaded.profiles.single.name, 'Custom Shell');
      expect(loaded.profiles.single.tags, const ['work', 'prod']);
      expect(loaded.profiles.single.triggers, const [
        TerminalProfileTrigger(pattern: 'ERROR'),
        TerminalProfileTrigger(
          pattern: 'Password:',
          action: TerminalProfileTriggerAction.sendText,
          value: 'secret\n',
        ),
      ]);
      expect(loaded.profiles.single.switchRules, const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.hostname,
          pattern: '*.prod.example.com',
        ),
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.directory,
          pattern: '/srv/app',
        ),
      ]);
      expect(
        raw['schemaVersion'],
        TerminalProfilesDocument.currentSchemaVersion,
      );
      expect(raw.containsKey('defaultProfileId'), isFalse);
      expect(
        (raw['profiles'] as List<dynamic>).single,
        containsPair(
          'launch',
          containsPair('program', defaultTerminalProfile().shell),
        ),
      );
      expect(
        (raw['profiles'] as List<dynamic>).single,
        containsPair('tags', const ['work', 'prod']),
      );
      expect(
        (raw['profiles'] as List<dynamic>).single,
        containsPair(
          'triggers',
          containsAll([
            containsPair('pattern', 'ERROR'),
            containsPair('action', 'send_text'),
          ]),
        ),
      );
      expect(
        (raw['profiles'] as List<dynamic>).single,
        containsPair(
          'automaticProfileSwitching',
          containsAll([
            containsPair('kind', 'hostname'),
            containsPair('kind', 'directory'),
          ]),
        ),
      );
    },
  );

  test(
    'profile repository seeds a strict VT220 preset on first launch without legacy default field',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-seeded',
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_profiles.json');

      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(
        loaded.profiles.map((profile) => profile.id),
        containsAll(<String>[
          defaultTerminalProfile().id,
          vt220TerminalProfile().id,
        ]),
      );
      expect(
        loaded.profiles
            .firstWhere((profile) => profile.id == vt220TerminalProfile().id)
            .terminalEmulation,
        TerminalEmulation.vt220,
      );
      expect(
        loaded.profiles
            .where(
              (profile) =>
                  profile.id == defaultTerminalProfile().id ||
                  profile.id == vt220TerminalProfile().id,
            )
            .map((profile) => profile.args),
        everyElement(const ['-l']),
      );
      expect(
        raw['schemaVersion'],
        TerminalProfilesDocument.currentSchemaVersion,
      );
      expect(raw.containsKey('defaultProfileId'), isFalse);
    },
  );

  test(
    'profile repository ignores legacy defaultProfileId from older documents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-migration',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'defaultProfileId': 'legacy',
          'profiles': [
            {
              'id': 'legacy',
              'name': 'Legacy Shell',
              'shell': '/bin/zsh',
              'args': const <String>[],
              'env': const <String, String>{},
              'cwd': null,
            },
          ],
        }),
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.profiles.single.terminalEmulation,
        TerminalEmulation.xterm256,
      );
      expect(loaded.schemaVersion, 1);
      expect(loaded.toJson()['schemaVersion'], 1);
      expect(loaded.toJson().containsKey('defaultProfileId'), isFalse);
    },
  );

  test(
    'profile repository tolerates documents that omit defaultProfileId',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-missing-default',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'profiles': [
            {
              'id': 'default',
              'name': 'Local Shell',
              'shell': '/bin/zsh',
              'args': const <String>[],
              'env': const <String, String>{},
              'cwd': null,
            },
          ],
        }),
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded.profiles.single.id, 'default');
      expect(
        loaded.profiles.single.terminalEmulation,
        TerminalEmulation.xterm256,
      );
      expect(loaded.schemaVersion, 1);
    },
  );

  test('profile repository reads nested schema v3 documents', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-profiles-v3',
    );
    final file = File('${directory.path}/ianvs_profiles.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 3,
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'tags': const ['prod', 'ops', 'prod', ' '],
            'triggers': const [
              {'pattern': 'ERROR', 'action': 'notify'},
              {
                'pattern': 'Password:',
                'action': 'send_text',
                'value': 'secret\n',
              },
            ],
            'launch': {
              'program': '/bin/zsh',
              'args': const ['-l'],
              'env': const {'TERM_PROGRAM': 'ianvs terminal'},
              'cwd': '/tmp',
            },
            'terminal': {'emulation': 'vt220', 'scrollbackLines': 4096},
            'appearance': {
              'font': {
                'family': 'Menlo',
                'fallback': const ['Monaco'],
                'size': 13,
                'lineHeight': 1.4,
              },
              'colors': {
                'special': {
                  'foreground': '#eeeeee',
                  'background': '#111111',
                  'cursor': '#22c55e',
                  'selection': '#334155',
                },
                'normal': {'red': '#ff5544', 'blue': '#3366cc'},
                'bright': {'yellow': '#ffd166', 'white': '#fafafa'},
              },
              'cursor': {'shape': 'beam', 'blink': false},
            },
            'interaction': {
              'copyOnSelect': true,
              'optionDragMode': 'normal_selection',
            },
          },
        ],
      }),
    );
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );

    final loaded = await repository.load();

    expect(loaded.schemaVersion, 3);
    expect(loaded.profiles.single.shell, '/bin/zsh');
    expect(loaded.profiles.single.tags, const ['prod', 'ops']);
    expect(loaded.profiles.single.triggers, const [
      TerminalProfileTrigger(pattern: 'ERROR'),
      TerminalProfileTrigger(
        pattern: 'Password:',
        action: TerminalProfileTriggerAction.sendText,
        value: 'secret\n',
      ),
    ]);
    expect(loaded.profiles.single.args, const ['-l']);
    expect(loaded.profiles.single.env, const {
      'TERM_PROGRAM': 'ianvs terminal',
    });
    expect(loaded.profiles.single.cwd, '/tmp');
    expect(loaded.profiles.single.terminalEmulation, TerminalEmulation.vt220);
    expect(loaded.profiles.single.scrollbackLines, 4096);
    expect(loaded.profiles.single.appearance.font.family, 'Menlo');
    expect(
      loaded.profiles.single.appearance.cursor.shape,
      TerminalCursorShape.beam,
    );
    expect(loaded.profiles.single.appearance.cursor.blink, isFalse);
    expect(loaded.profiles.single.interaction.copyOnSelect, isTrue);
    expect(
      loaded.profiles.single.interaction.optionDragMode,
      TerminalOptionDragMode.normalSelection,
    );
    expect(loaded.profiles.single.appearance.colors.foreground, '#EEEEEE');
    expect(loaded.profiles.single.appearance.colors.background, '#111111');
    expect(loaded.profiles.single.appearance.colors.cursor, '#22C55E');
    expect(loaded.profiles.single.appearance.colors.selection, '#334155');
    expect(loaded.profiles.single.appearance.colors.normal.red, '#FF5544');
    expect(loaded.profiles.single.appearance.colors.normal.blue, '#3366CC');
    expect(loaded.profiles.single.appearance.colors.bright.yellow, '#FFD166');
    expect(loaded.profiles.single.appearance.colors.bright.white, '#FAFAFA');
  });

  test('profile document imports iTerm dynamic profiles JSON', () {
    final document = TerminalProfilesDocument.fromJson({
      'Profiles': [
        {
          'Name': 'prod.example.com',
          'Guid': 'prod-host',
          'Custom Command': 'Yes',
          'Command': 'ssh prod.example.com',
          'Tags': ['ssh', 'prod'],
        },
      ],
    });

    final profile = document.profiles.single;
    expect(profile.id, 'prod-host');
    expect(profile.name, 'prod.example.com');
    expect(profile.tags, const ['ssh', 'prod', 'Dynamic']);
    expect(profile.shell, '/bin/sh');
    expect(profile.args, const ['-lc', 'ssh prod.example.com']);
  });

  test(
    'profile repository tolerates invalid nested fields and reports warnings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-invalid-fields',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      await file.parent.create(recursive: true);
      final rawDocument = jsonEncode({
        'schemaVersion': 3,
        'profiles': [
          {
            'name': '',
            'tags': const ['ops', 7, ' ops ', ' '],
            'triggers': const [
              {'pattern': 'ERROR', 'action': 7},
              {'pattern': '[', 'action': 'notify'},
              {'pattern': 'Prompt:', 'action': 'send_text'},
            ],
            'automaticProfileSwitching': const [
              {'kind': 'host', 'pattern': 'prod.example.com'},
              {'kind': 'role', 'pattern': 'root'},
              {'kind': 'user', 'pattern': ''},
              {'kind': 'dir', 'pattern': '/srv', 'caseSensitive': 'yes'},
            ],
            'launch': {
              'program': 7,
              'args': const ['-l', 3, ''],
              'env': const {
                'TERM_PROGRAM': 'ianvs terminal',
                'BAD': 9,
                '': 'empty',
              },
              'cwd': 42,
            },
            'terminal': {'emulation': 'ansi', 'scrollbackLines': -1},
            'appearance': {
              'font': {
                'family': '',
                'fallback': const ['Monaco', 4, ' '],
                'size': 0,
                'lineHeight': -1,
              },
              'colors': {
                'foreground': 'red',
                'background': '#112233',
                'cursor': 12,
                'selection': '#334455',
                'special': {
                  'foreground': 'red',
                  'background': '#112233',
                  'cursor': 12,
                  'selection': '#334455',
                },
                'normal': {'black': '#010203', 'red': 'tomato'},
                'bright': const ['wrong-shape'],
              },
              'cursor': {'shape': 'triangle', 'blink': 'yes'},
            },
            'interaction': {'copyOnSelect': 'no', 'optionDragMode': 'diagonal'},
          },
        ],
      });
      await file.writeAsString(rawDocument);
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();
      final rawAfterLoad = await file.readAsString();

      expect(rawAfterLoad, rawDocument);
      expect(loaded.profiles.single.id, 'profile-1');
      expect(loaded.profiles.single.name, 'profile-1');
      expect(loaded.profiles.single.tags, const ['ops']);
      expect(loaded.profiles.single.triggers, const [
        TerminalProfileTrigger(pattern: 'ERROR'),
      ]);
      expect(loaded.profiles.single.switchRules, const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.hostname,
          pattern: 'prod.example.com',
        ),
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.directory,
          pattern: '/srv',
        ),
      ]);
      expect(loaded.profiles.single.shell, defaultTerminalProfile().shell);
      expect(loaded.profiles.single.args, const ['-l']);
      expect(loaded.profiles.single.env, const {
        'TERM_PROGRAM': 'ianvs terminal',
      });
      expect(loaded.profiles.single.cwd, isNull);
      expect(
        loaded.profiles.single.terminalEmulation,
        TerminalEmulation.xterm256,
      );
      expect(loaded.profiles.single.scrollbackLines, 8000);
      expect(
        loaded.profiles.single.appearance.font.family,
        terminalPrimaryFontFamily,
      );
      expect(loaded.profiles.single.appearance.font.fallback, const ['Monaco']);
      expect(loaded.profiles.single.appearance.font.size, terminalFontSize);
      expect(
        loaded.profiles.single.appearance.font.lineHeight,
        terminalLineHeight,
      );
      expect(loaded.profiles.single.appearance.colors.foreground, isNull);
      expect(loaded.profiles.single.appearance.colors.background, '#112233');
      expect(loaded.profiles.single.appearance.colors.cursor, isNull);
      expect(loaded.profiles.single.appearance.colors.selection, '#334455');
      expect(loaded.profiles.single.appearance.colors.normal.black, '#010203');
      expect(loaded.profiles.single.appearance.colors.normal.red, isNull);
      expect(loaded.profiles.single.appearance.colors.bright.blue, isNull);
      expect(
        loaded.profiles.single.appearance.cursor.shape,
        TerminalCursorShape.block,
      );
      expect(loaded.profiles.single.appearance.cursor.blink, isTrue);
      expect(loaded.profiles.single.interaction.copyOnSelect, isFalse);
      expect(
        loaded.profiles.single.interaction.optionDragMode,
        TerminalOptionDragMode.blockSelection,
      );
      expect(loaded.loadWarnings, isNotEmpty);
      expect(
        loaded.loadWarnings.map((warning) => warning.path),
        containsAll(<String>[
          'id',
          'name',
          'tags[1]',
          'triggers[0].action',
          'triggers[1].pattern',
          'triggers[2].value',
          'automaticProfileSwitching[1].kind',
          'automaticProfileSwitching[2].pattern',
          'automaticProfileSwitching[3].caseSensitive',
          'launch.program',
          'launch.args[1]',
          'launch.env.BAD',
          'launch.cwd',
          'terminal.emulation',
          'terminal.scrollbackLines',
          'appearance.font.family',
          'appearance.font.fallback[1]',
          'appearance.font.size',
          'appearance.font.lineHeight',
          'appearance.colors.foreground',
          'appearance.colors.background',
          'appearance.colors.cursor',
          'appearance.colors.selection',
          'appearance.colors.special.foreground',
          'appearance.colors.special.cursor',
          'appearance.colors.normal.red',
          'appearance.cursor.shape',
          'appearance.cursor.blink',
          'interaction.copyOnSelect',
          'interaction.optionDragMode',
        ]),
      );
      expect(loaded.toJson().containsKey('loadWarnings'), isFalse);
    },
  );

  test('profile repository tolerates invalid schema version', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-profiles-invalid-schema',
    );
    final file = File('${directory.path}/ianvs_profiles.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 'latest',
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'launch': {
              'program': '/bin/zsh',
              'args': const ['-l'],
            },
          },
        ],
      }),
    );
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );

    final loaded = await repository.load();

    expect(loaded.schemaVersion, 1);
    expect(loaded.profiles.single.id, 'default');
    expect(
      loaded.loadWarnings,
      contains(
        const TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: '"latest"',
          fallbackSummary: 'used schema version 1',
        ),
      ),
    );
  });

  test('profile repository tolerates non-finite schema version', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-profiles-non-finite-schema',
    );
    final file = File('${directory.path}/ianvs_profiles.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('''
{
  "schemaVersion": 1e999,
  "profiles": [
    {
      "id": "default",
      "name": "Local Shell",
      "launch": {"program": "/bin/zsh", "args": ["-l"]}
    }
  ]
}
''');
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );

    final loaded = await repository.load();

    expect(loaded.schemaVersion, 1);
    expect(loaded.profiles.single.id, 'default');
    expect(
      loaded.loadWarnings,
      contains(
        const TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: 'Infinity',
          fallbackSummary: 'used schema version 1',
        ),
      ),
    );
  });

  test(
    'profile repository upgrades built-in shell presets without explicit login args',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-login-shell-upgrade',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'profiles': [
            {
              'id': 'default',
              'name': 'Local Shell',
              'launch': {
                'program': defaultTerminalProfile().shell,
                'env': const {'TERM_PROGRAM': 'ianvs terminal'},
                'cwd': null,
              },
              'terminal': {'emulation': 'xterm256', 'scrollbackLines': 8000},
            },
            {
              'id': 'vt220',
              'name': 'Strict VT220',
              'launch': {
                'program': vt220TerminalProfile().shell,
                'env': const {'TERM_PROGRAM': 'ianvs terminal'},
                'cwd': null,
              },
              'terminal': {'emulation': 'vt220', 'scrollbackLines': 8000},
            },
          ],
        }),
      );
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.profiles
            .firstWhere((profile) => profile.id == defaultTerminalProfile().id)
            .args,
        const ['-l'],
      );
      expect(
        loaded.profiles
            .firstWhere((profile) => profile.id == vt220TerminalProfile().id)
            .args,
        const ['-l'],
      );
    },
  );

  test(
    'profile repository falls back in-memory when the json document is malformed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-malformed-json',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('{bad json');
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.profiles.map((profile) => profile.id),
        containsAll(<String>[
          defaultTerminalProfile().id,
          vt220TerminalProfile().id,
        ]),
      );
      expect(loaded.loadWarnings, hasLength(1));
      expect(loaded.loadWarnings.single.profileId, 'document');
      expect(loaded.loadWarnings.single.path, 'document');
      expect(
        loaded.loadWarnings.single.fallbackSummary,
        'loaded in-memory fallback profiles',
      );
      expect(await file.readAsString(), '{bad json');
    },
  );
}

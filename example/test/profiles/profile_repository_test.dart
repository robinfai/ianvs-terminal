import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:app/features/terminal/terminal_defaults.dart';

void main() {
  test(
    'encrypts SSH secrets at rest and restores them with the saved key',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-encrypted-ssh-profile',
      );
      final keyStore = _MemoryProfileSecretKeyStore();
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: keyStore),
      );
      final profile = defaultTerminalProfile().copyWith(
        id: 'ssh-production',
        name: 'Production SSH',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'ssh.example.test',
          user: 'operator',
          auth: terminal.TerminalSshAuthMethod.password,
          password: 'plain-password-must-not-leak',
          privateKeyPassphrase: 'plain-passphrase-must-not-leak',
          proxyJump: 'jump-user@jump.example.test',
          proxyJumpProfiles: <terminal.TerminalSshJumpConfig>[
            terminal.TerminalSshJumpConfig(
              host: 'jump.example.test',
              user: 'jump-user',
              port: 22,
              auth: terminal.TerminalSshAuthMethod.publicKey,
              password: 'plain-jump-password-must-not-leak',
              privateKeys: <String>['/keys/jump_ed25519'],
              privateKeyPassphrase: 'plain-jump-passphrase-must-not-leak',
            ),
          ],
          x11Forwarding: true,
          x11TargetHost: '127.0.0.1',
          x11TargetPort: 6000,
          x11AuthCookie: 'plain-x11-cookie-must-not-leak',
        ),
      );

      await repository.save(TerminalProfilesDocument(profiles: [profile]));
      final raw = await File(
        '${directory.path}/ianvs_profiles.json',
      ).readAsString();

      expect(raw, isNot(contains('plain-password-must-not-leak')));
      expect(raw, isNot(contains('plain-passphrase-must-not-leak')));
      expect(raw, isNot(contains('plain-x11-cookie-must-not-leak')));
      expect(raw, isNot(contains('plain-jump-password-must-not-leak')));
      expect(raw, isNot(contains('plain-jump-passphrase-must-not-leak')));
      expect(raw, contains('aes-256-gcm'));
      expect(raw, contains('encryptedSecrets'));
      expect(keyStore.writeCount, 1);

      final reloaded = await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: keyStore),
      ).load();
      expect(
        reloaded.profiles.single.connection.password,
        'plain-password-must-not-leak',
      );
      expect(
        reloaded.profiles.single.connection.privateKeyPassphrase,
        'plain-passphrase-must-not-leak',
      );
      expect(
        reloaded.profiles.single.connection.x11AuthCookie,
        'plain-x11-cookie-must-not-leak',
      );
      expect(
        reloaded.profiles.single.connection.proxyJumpProfiles.single.password,
        isNull,
      );
      expect(
        reloaded
            .profiles
            .single
            .connection
            .proxyJumpProfiles
            .single
            .privateKeyPassphrase,
        isNull,
      );
      expect(
        reloaded
            .profiles
            .single
            .connection
            .proxyJumpProfiles
            .single
            .privateKeys,
        <String>['/keys/jump_ed25519'],
      );
    },
  );

  test(
    'preserves an undecryptable secret envelope while saving other profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-opaque-ssh-secret',
      );
      final originalKeyStore = _MemoryProfileSecretKeyStore();
      final sshProfile = defaultTerminalProfile().copyWith(
        id: 'ssh-opaque',
        name: 'Opaque SSH',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'opaque.example.test',
          user: 'operator',
          password: 'recover-me',
        ),
      );
      final localProfile = defaultTerminalProfile().copyWith(id: 'local-1');
      final originalRepository = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      );
      await originalRepository.save(
        TerminalProfilesDocument(profiles: [sshProfile, localProfile]),
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      final before = jsonDecode(await file.readAsString()) as Map;
      final beforeEnvelope = _encryptedSecretsFor(before, 'ssh-opaque');

      final wrongKeyStore = _MemoryProfileSecretKeyStore()
        ..value = base64Encode(List<int>.filled(32, 7));
      final repositoryWithWrongKey = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: wrongKeyStore),
      );
      final loaded = await repositoryWithWrongKey.load();
      expect(loaded.profiles.first.connection.password, isNull);
      expect(loaded.loadWarnings, isNotEmpty);

      await repositoryWithWrongKey.save(
        TerminalProfilesDocument(
          profiles: [
            loaded.profiles.first,
            loaded.profiles.last.copyWith(name: 'Renamed local'),
          ],
        ),
      );
      final after = jsonDecode(await file.readAsString()) as Map;
      expect(_encryptedSecretsFor(after, 'ssh-opaque'), beforeEnvelope);

      final recovered = await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      ).load();
      expect(recovered.profiles.first.connection.password, 'recover-me');
      expect(recovered.profiles.last.name, 'Renamed local');
    },
  );

  test(
    'explicitly clearing an undecryptable secret removes it permanently',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-clear-opaque-ssh-secret',
      );
      final originalKeyStore = _MemoryProfileSecretKeyStore();
      final profile = defaultTerminalProfile().copyWith(
        id: 'ssh-clear-opaque',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'opaque.example.test',
          user: 'operator',
          password: 'must-not-resurrect',
        ),
      );
      await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      ).save(TerminalProfilesDocument(profiles: [profile]));

      final wrongKeyStore = _MemoryProfileSecretKeyStore()
        ..value = base64Encode(List<int>.filled(32, 7));
      final wrongKeyRepository = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: wrongKeyStore),
      );
      final loaded = await wrongKeyRepository.load();
      expect(loaded.profiles.single.connection.password, isNull);

      await wrongKeyRepository.save(
        TerminalProfilesDocument(
          profiles: loaded.profiles,
          secretClearIntents: const <String, Set<ProfileSecretField>>{
            'ssh-clear-opaque': <ProfileSecretField>{
              ProfileSecretField.password,
            },
          },
        ),
      );
      // A second unrelated save exercises the repository's refreshed opaque
      // snapshot; the removed envelope must not be copied back into the file.
      await wrongKeyRepository.save(
        TerminalProfilesDocument(
          profiles: [loaded.profiles.single.copyWith(name: 'Renamed')],
        ),
      );

      final file = File('${directory.path}/ianvs_profiles.json');
      final raw = jsonDecode(await file.readAsString()) as Map;
      expect(
        _connectionFor(raw, 'ssh-clear-opaque').containsKey('encryptedSecrets'),
        isFalse,
      );
      final recovered = await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      ).load();
      expect(recovered.profiles.single.connection.password, isNull);
      expect(recovered.profiles.single.name, 'Renamed');
    },
  );

  test(
    'secret clear intents remove only the requested encrypted fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-field-scoped-secret-clear',
      );
      final originalKeyStore = _MemoryProfileSecretKeyStore();
      final profile = defaultTerminalProfile().copyWith(
        id: 'ssh-field-clear',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'fields.example.test',
          user: 'operator',
          password: 'keep-password',
          privateKeys: <String>['~/.ssh/id_ed25519'],
          privateKeyPassphrase: 'remove-passphrase',
          x11Forwarding: true,
          x11TargetHost: '127.0.0.1',
          x11TargetPort: 6000,
          x11AuthCookie: 'remove-cookie',
        ),
      );
      await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      ).save(TerminalProfilesDocument(profiles: [profile]));

      final wrongKeyStore = _MemoryProfileSecretKeyStore()
        ..value = base64Encode(List<int>.filled(32, 9));
      final wrongKeyRepository = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: wrongKeyStore),
      );
      final loaded = await wrongKeyRepository.load();
      await wrongKeyRepository.save(
        TerminalProfilesDocument(
          profiles: loaded.profiles,
          secretClearIntents: const <String, Set<ProfileSecretField>>{
            'ssh-field-clear': <ProfileSecretField>{
              ProfileSecretField.privateKeyPassphrase,
              ProfileSecretField.x11AuthCookie,
            },
          },
        ),
      );

      final raw =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_profiles.json',
                ).readAsString(),
              )
              as Map;
      final encrypted = _encryptedSecretsFor(raw, 'ssh-field-clear');
      expect(encrypted, contains('password'));
      expect(encrypted, isNot(contains('privateKeyPassphrase')));
      expect(encrypted, isNot(contains('x11AuthCookie')));

      final recovered = await ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: originalKeyStore),
      ).load();
      expect(recovered.profiles.single.connection.password, 'keep-password');
      expect(recovered.profiles.single.connection.privateKeyPassphrase, isNull);
      expect(recovered.profiles.single.connection.x11AuthCookie, isNull);
    },
  );

  test('preserves an unknown encryptedSecrets version across save', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-future-ssh-secret',
    );
    final file = File('${directory.path}/ianvs_profiles.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': TerminalProfilesDocument.currentSchemaVersion,
        'profiles': <Object?>[
          <String, Object?>{
            ...defaultTerminalProfile()
                .copyWith(
                  id: 'future-ssh',
                  connection: const terminal.TerminalConnectionConfig.ssh(
                    host: 'future.example.test',
                    user: 'operator',
                  ),
                )
                .toJson(),
            'connection': <String, Object?>{
              'type': 'ssh',
              'host': 'future.example.test',
              'user': 'operator',
              'port': 22,
              'encryptedSecrets': <String, Object?>{
                'format': 'ianvs-profile-secrets-v2',
                'payload': <String, Object?>{
                  'ciphertext': 'opaque-future-value',
                },
              },
            },
          },
        ],
      }),
    );
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );

    final loaded = await repository.load();
    await repository.save(
      TerminalProfilesDocument(
        profiles: [loaded.profiles.single.copyWith(name: 'Future renamed')],
      ),
    );

    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(_encryptedSecretsFor(saved, 'future-ssh'), <String, Object?>{
      'format': 'ianvs-profile-secrets-v2',
      'payload': <String, Object?>{'ciphertext': 'opaque-future-value'},
    });
  });

  test(
    'does not quarantine valid legacy JSON when secret migration cannot save',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-failed-secret-migration',
      );
      final file = File('${directory.path}/ianvs_profiles.json');
      final source = jsonEncode(<String, Object?>{
        'schemaVersion': TerminalProfilesDocument.currentSchemaVersion,
        'profiles': <Object?>[
          <String, Object?>{
            ...defaultTerminalProfile().copyWith(id: 'legacy-ssh').toJson(),
            'connection': <String, Object?>{
              'type': 'ssh',
              'host': 'legacy.example.test',
              'user': 'operator',
              'port': 22,
              'password': 'legacy-plaintext',
            },
          },
        ],
      });
      await file.writeAsString(source);
      final invalidKeyStore = _MemoryProfileSecretKeyStore()
        ..value = 'not-a-valid-base64-key';
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
        secretCipher: ProfileSecretCipher(keyStore: invalidKeyStore),
      );

      await expectLater(repository.load(), throwsA(isA<FormatException>()));

      expect(await file.readAsString(), source);
      final quarantined = await directory
          .list()
          .where((entry) => entry.path.contains('.corrupt'))
          .toList();
      expect(quarantined, isEmpty);
    },
  );

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

  test('profile repository exports a profile document', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-profiles-export',
    );
    final repository = ProfileRepository(
      directoryResolver: () async => directory,
    );
    final document = TerminalProfilesDocument(
      profiles: [
        defaultTerminalProfile().copyWith(
          name: 'Exported Shell',
          tags: const ['exported'],
        ),
      ],
    );

    final file = await repository.exportDocument(document);
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

    expect(file.path, contains('ianvs-profiles.ianvs-terminal-profiles.json'));
    expect(raw['schemaVersion'], TerminalProfilesDocument.currentSchemaVersion);
    expect(
      (raw['profiles'] as List<dynamic>).single,
      containsPair('name', 'Exported Shell'),
    );
    expect(
      (raw['profiles'] as List<dynamic>).single,
      containsPair('tags', const ['exported']),
    );
  });

  test(
    'profile repository sanitizes exported profile document basename',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs terminal-profiles-export-safe-name',
      );
      final directory = Directory('${root.path}/profiles');
      final repository = ProfileRepository(
        directoryResolver: () async => directory,
      );

      final file = await repository.exportDocument(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        basename: '../escaped profiles',
      );

      final directoryPath = await directory.resolveSymbolicLinks();
      final filePath = await file.resolveSymbolicLinks();
      expect(filePath, startsWith('$directoryPath${Platform.pathSeparator}'));
      expect(
        file.path,
        contains('..-escaped-profiles.ianvs-terminal-profiles.json'),
      );
      expect(
        File(
          '${root.path}/escaped profiles.ianvs-terminal-profiles.json',
        ).existsSync(),
        isFalse,
      );
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
      expect(
        loaded.schemaVersion,
        TerminalProfilesDocument.currentSchemaVersion,
      );
      expect(
        loaded.toJson()['schemaVersion'],
        TerminalProfilesDocument.currentSchemaVersion,
      );
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
      expect(
        loaded.schemaVersion,
        TerminalProfilesDocument.currentSchemaVersion,
      );
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
                  'tab': '#2563eb',
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
    expect(loaded.profiles.single.appearance.colors.tab, '#2563EB');
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
          'Use Tab Color': true,
          'Tab Color': {
            'Red Component': 0.2,
            'Green Component': 0.4,
            'Blue Component': 0.6,
          },
        },
        {
          'Name': 'dev.example.com',
          'Guid': 'dev-host',
          'Use Tab Color': false,
          'Tab Color': '#112233',
        },
      ],
    });

    final profile = document.profiles.first;
    expect(profile.id, 'prod-host');
    expect(profile.name, 'prod.example.com');
    expect(profile.tags, const ['ssh', 'prod', 'Dynamic']);
    expect(profile.shell, '/bin/sh');
    expect(profile.args, const ['-lc', 'ssh prod.example.com']);
    expect(profile.appearance.colors.tab, '#336699');

    final disabledProfile = document.profiles.last;
    expect(disabledProfile.id, 'dev-host');
    expect(disabledProfile.appearance.colors.tab, isNull);
  });

  test('profile document bounds dynamic profile tags and keeps marker', () {
    final document = TerminalProfilesDocument.fromJson({
      'Profiles': [
        {
          'Name': 'prod.example.com',
          'Guid': 'prod-host',
          'Tags': [
            for (var index = 0; index < maxTerminalProfileTags + 10; index += 1)
              'tag-$index',
          ],
        },
      ],
    });

    final profile = document.profiles.single;
    expect(profile.tags, hasLength(maxTerminalProfileTags));
    expect(profile.tags.first, 'tag-0');
    expect(
      profile.tags[maxTerminalProfileTags - 2],
      'tag-${maxTerminalProfileTags - 2}',
    );
    expect(profile.tags.last, 'Dynamic');
  });

  test('profile document skips duplicate profile ids', () {
    final document = TerminalProfilesDocument.fromJson({
      'schemaVersion': 4,
      'profiles': [
        {
          'id': 'shared',
          'name': 'First Shell',
          'launch': {
            'program': '/bin/zsh',
            'args': const ['-l'],
          },
        },
        {
          'id': 'shared',
          'name': 'Second Shell',
          'launch': {
            'program': '/bin/bash',
            'args': const ['-l'],
          },
        },
        {
          'id': 'unique',
          'name': 'Unique Shell',
          'launch': {
            'program': '/bin/sh',
            'args': const ['-l'],
          },
        },
      ],
    });

    expect(document.profiles.map((profile) => profile.name), const [
      'First Shell',
      'Unique Shell',
    ]);
    expect(
      document.loadWarnings,
      contains(
        const TerminalProfileLoadWarning(
          profileId: 'shared',
          profileName: 'Second Shell',
          path: 'profiles[1].id',
          rawValueSummary: '"shared"',
          fallbackSummary: 'ignored duplicate profile id',
        ),
      ),
    );
  });

  test('profile document caps restored profile entries', () {
    final inputCount = maxTerminalProfiles + 2;
    final document = TerminalProfilesDocument.fromJson({
      'schemaVersion': 4,
      'profiles': [
        for (var index = 0; index < inputCount; index += 1)
          {
            'id': 'profile-$index',
            'name': 'Profile $index',
            'launch': {
              'program': '/bin/zsh',
              'args': const ['-l'],
            },
          },
      ],
    });

    expect(document.profiles, hasLength(maxTerminalProfiles));
    expect(document.profiles.last.id, 'profile-${maxTerminalProfiles - 1}');
    expect(
      document.profiles.map((profile) => profile.id),
      isNot(contains('profile-$maxTerminalProfiles')),
    );
    expect(
      document.loadWarnings,
      contains(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'profiles',
          rawValueSummary: _profileCollectionRawValueSummary(
            inputCount,
            'profile',
          ),
          fallbackSummary: _profileCollectionFallbackSummary(
            maxTerminalProfiles,
            'profile',
          ),
        ),
      ),
    );
  });

  test('profile document caps restored profile metadata collections', () {
    final tagInputCount = maxTerminalProfileTags + 2;
    final triggerInputCount = maxTerminalProfileTriggers + 2;
    final switchRuleInputCount = maxTerminalProfileSwitchRules + 2;
    final document = TerminalProfilesDocument.fromJson({
      'schemaVersion': 4,
      'profiles': [
        {
          'id': 'bounded',
          'name': 'Bounded Shell',
          'tags': [
            for (var index = 0; index < tagInputCount; index += 1) 'tag-$index',
          ],
          'triggers': [
            for (var index = 0; index < triggerInputCount; index += 1)
              {'pattern': 'TRIGGER_$index'},
          ],
          'automaticProfileSwitching': [
            for (var index = 0; index < switchRuleInputCount; index += 1)
              {'kind': 'host', 'pattern': 'host-$index.example.com'},
          ],
          'launch': {
            'program': '/bin/zsh',
            'args': const ['-l'],
          },
        },
      ],
    });

    final profile = document.profiles.single;
    expect(profile.tags, hasLength(maxTerminalProfileTags));
    expect(profile.tags.last, 'tag-${maxTerminalProfileTags - 1}');
    expect(profile.triggers, hasLength(maxTerminalProfileTriggers));
    expect(
      profile.triggers.last.pattern,
      'TRIGGER_${maxTerminalProfileTriggers - 1}',
    );
    expect(profile.switchRules, hasLength(maxTerminalProfileSwitchRules));
    expect(
      profile.switchRules.last.pattern,
      'host-${maxTerminalProfileSwitchRules - 1}.example.com',
    );
    expect(
      document.loadWarnings,
      containsAll([
        TerminalProfileLoadWarning(
          profileId: 'bounded',
          profileName: 'Bounded Shell',
          path: 'tags',
          rawValueSummary: _profileCollectionRawValueSummary(
            tagInputCount,
            'tag',
          ),
          fallbackSummary: _profileCollectionFallbackSummary(
            maxTerminalProfileTags,
            'tag',
          ),
        ),
        TerminalProfileLoadWarning(
          profileId: 'bounded',
          profileName: 'Bounded Shell',
          path: 'triggers',
          rawValueSummary: _profileCollectionRawValueSummary(
            triggerInputCount,
            'trigger',
          ),
          fallbackSummary: _profileCollectionFallbackSummary(
            maxTerminalProfileTriggers,
            'trigger',
          ),
        ),
        TerminalProfileLoadWarning(
          profileId: 'bounded',
          profileName: 'Bounded Shell',
          path: 'automaticProfileSwitching',
          rawValueSummary: _profileCollectionRawValueSummary(
            switchRuleInputCount,
            'switching rule',
          ),
          fallbackSummary: _profileCollectionFallbackSummary(
            maxTerminalProfileSwitchRules,
            'switching rule',
          ),
        ),
      ]),
    );
  });

  test('profile document scans past invalid metadata entries', () {
    final document = TerminalProfilesDocument.fromJson({
      'schemaVersion': 4,
      'profiles': [
        {
          'id': 'recovered',
          'name': 'Recovered Shell',
          'tags': [
            for (var index = 0; index < maxTerminalProfileTags; index += 1)
              '   ',
            for (var index = 0; index < maxTerminalProfileTags; index += 1)
              'tag-$index',
          ],
          'triggers': [
            for (var index = 0; index < maxTerminalProfileTriggers; index += 1)
              {'pattern': '['},
            for (var index = 0; index < maxTerminalProfileTriggers; index += 1)
              {'pattern': 'TRIGGER_$index'},
          ],
          'automaticProfileSwitching': [
            for (
              var index = 0;
              index < maxTerminalProfileSwitchRules;
              index += 1
            )
              {'kind': 'unknown', 'pattern': 'ignored-$index'},
            for (
              var index = 0;
              index < maxTerminalProfileSwitchRules;
              index += 1
            )
              {'kind': 'host', 'pattern': 'host-$index.example.com'},
          ],
          'launch': {
            'program': '/bin/zsh',
            'args': const ['-l'],
          },
        },
      ],
    });

    final profile = document.profiles.single;
    expect(profile.tags, hasLength(maxTerminalProfileTags));
    expect(profile.tags.first, 'tag-0');
    expect(profile.tags.last, 'tag-${maxTerminalProfileTags - 1}');
    expect(profile.triggers, hasLength(maxTerminalProfileTriggers));
    expect(profile.triggers.first.pattern, 'TRIGGER_0');
    expect(
      profile.triggers.last.pattern,
      'TRIGGER_${maxTerminalProfileTriggers - 1}',
    );
    expect(profile.switchRules, hasLength(maxTerminalProfileSwitchRules));
    expect(profile.switchRules.first.pattern, 'host-0.example.com');
    expect(
      profile.switchRules.last.pattern,
      'host-${maxTerminalProfileSwitchRules - 1}.example.com',
    );
  });

  test(
    'profile document migrates only the built-in default pure black background',
    () {
      final document = TerminalProfilesDocument.fromJson({
        'schemaVersion': 4,
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'launch': {
              'program': defaultTerminalProfile().shell,
              'args': const ['-l'],
            },
            'appearance': {
              'colors': {
                'special': {'background': '#000000'},
              },
            },
          },
          {
            'id': 'custom-black',
            'name': 'Custom Black',
            'launch': {'program': '/bin/zsh'},
            'appearance': {
              'colors': {
                'special': {'background': '#000000'},
              },
            },
          },
        ],
      });

      final defaultProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'default',
      );
      final customProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'custom-black',
      );

      expect(defaultProfile.appearance.colors.background, '#000000');
      expect(customProfile.appearance.colors.background, '#000000');
    },
  );

  test(
    'profile document migrates the previous built-in default background',
    () {
      final document = TerminalProfilesDocument.fromJson({
        'schemaVersion': 4,
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'launch': {
              'program': defaultTerminalProfile().shell,
              'args': const ['-l'],
            },
            'appearance': {
              'colors': {
                'special': {'background': '#14191E'},
              },
            },
          },
          {
            'id': 'custom-previous-default',
            'name': 'Custom Previous Default',
            'launch': {'program': '/bin/zsh'},
            'appearance': {
              'colors': {
                'special': {'background': '#14191E'},
              },
            },
          },
        ],
      });

      final defaultProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'default',
      );
      final customProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'custom-previous-default',
      );

      expect(defaultProfile.appearance.colors.background, '#000000');
      expect(customProfile.appearance.colors.background, '#14191E');
    },
  );

  test(
    'profile document migrates the temporary blue built-in default background',
    () {
      final document = TerminalProfilesDocument.fromJson({
        'schemaVersion': 4,
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'launch': {
              'program': defaultTerminalProfile().shell,
              'args': const ['-l'],
            },
            'appearance': {
              'colors': {
                'special': {'background': '#203A4F'},
              },
            },
          },
          {
            'id': 'custom-temporary-blue',
            'name': 'Custom Temporary Blue',
            'launch': {'program': '/bin/zsh'},
            'appearance': {
              'colors': {
                'special': {'background': '#203A4F'},
              },
            },
          },
        ],
      });

      final defaultProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'default',
      );
      final customProfile = document.profiles.firstWhere(
        (profile) => profile.id == 'custom-temporary-blue',
      );

      expect(defaultProfile.appearance.colors.background, '#000000');
      expect(customProfile.appearance.colors.background, '#203A4F');
    },
  );

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

    expect(loaded.schemaVersion, TerminalProfilesDocument.currentSchemaVersion);
    expect(loaded.profiles.single.id, 'default');
    expect(
      loaded.loadWarnings,
      contains(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: '"latest"',
          fallbackSummary: _currentSchemaFallbackSummary(),
        ),
      ),
    );
  });

  test('profile document rejects fractional schema versions', () {
    final document = TerminalProfilesDocument.fromJson(const {
      'schemaVersion': 2.5,
      'profiles': [],
    });

    expect(
      document.schemaVersion,
      TerminalProfilesDocument.currentSchemaVersion,
    );
    expect(
      document.loadWarnings,
      contains(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: '2.5',
          fallbackSummary: _currentSchemaFallbackSummary(),
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

    expect(loaded.schemaVersion, TerminalProfilesDocument.currentSchemaVersion);
    expect(loaded.profiles.single.id, 'default');
    expect(
      loaded.loadWarnings,
      contains(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: 'Infinity',
          fallbackSummary: _currentSchemaFallbackSummary(),
        ),
      ),
    );
  });

  test('profile repository tolerates non-positive schema version', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-profiles-non-positive-schema',
    );
    final file = File('${directory.path}/ianvs_profiles.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': -2,
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

    expect(loaded.schemaVersion, TerminalProfilesDocument.currentSchemaVersion);
    expect(loaded.profiles.single.id, 'default');
    expect(
      loaded.loadWarnings,
      contains(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'schemaVersion',
          rawValueSummary: '-2',
          fallbackSummary: _currentSchemaFallbackSummary(),
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
    'profile repository quarantines malformed json and saves fallback profiles',
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
      final repairedRaw = jsonDecode(await file.readAsString());
      final quarantinedFiles = await directory
          .list()
          .where(
            (entity) => entity.path.contains('ianvs_profiles.json.corrupt'),
          )
          .toList();

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
        'quarantined corrupt file and saved fallback profiles',
      );
      expect(repairedRaw, isA<Map<String, Object?>>());
      expect(quarantinedFiles, hasLength(1));
      expect(
        await File(quarantinedFiles.single.path).readAsString(),
        '{bad json',
      );
    },
  );
}

String _currentSchemaFallbackSummary() {
  return 'used schema version ${TerminalProfilesDocument.currentSchemaVersion}';
}

String _profileCollectionRawValueSummary(int inputCount, String entryLabel) {
  return '$inputCount $entryLabel entries';
}

String _profileCollectionFallbackSummary(int maxEntries, String entryLabel) {
  if (entryLabel == 'profile') {
    return 'loaded first $maxEntries $entryLabel entries';
  }
  return 'loaded first $maxEntries valid $entryLabel entries';
}

final class _MemoryProfileSecretKeyStore implements ProfileSecretKeyStore {
  String? value;
  int writeCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
    writeCount += 1;
  }
}

Map<String, Object?> _encryptedSecretsFor(Map document, String profileId) {
  final connection = _connectionFor(document, profileId);
  return Map<String, Object?>.from(connection['encryptedSecrets']! as Map);
}

Map _connectionFor(Map document, String profileId) {
  final profiles = document['profiles']! as List;
  final profile = profiles.cast<Map>().singleWhere(
    (entry) => entry['id'] == profileId,
  );
  return profile['connection']! as Map;
}

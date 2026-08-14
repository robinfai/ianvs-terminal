import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/features/config/data_api_terminal_config_repository.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/data_api_terminal_layout_repository.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/persistence/versioned_document.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/data_api_app_preferences_repository.dart';
import 'package:app/features/profiles/data_api_profile_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/data_api_paste_history_repository.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../support/memory_data_api_resource_client.dart';

void main() {
  group('TerminalConfigRepository contract', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-config-contract-',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('local JSON adapter', () async {
      await _verifyTerminalConfigContract(
        LocalTerminalConfigRepository(
          directoryResolver: () async => temporaryDirectory,
        ),
      );
    });

    test('Data API adapter', () async {
      await _verifyTerminalConfigContract(
        DataApiTerminalConfigRepository(client: MemoryDataApiResourceClient()),
      );
    });
  });

  test(
    'profile adapter atomically stores one document and separates secrets',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiProfileRepository(client: client);
      final profile = TerminalProfile(
        id: 'work',
        name: 'Work',
        shell: '/bin/zsh',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'work.example.com',
          user: 'alice',
          password: 'profile-secret',
          privateKeys: <String>['private-key-contents'],
        ),
      );

      var snapshot = await repository.loadVersioned();
      snapshot = await repository.saveVersioned(
        snapshot.withValue(
          TerminalProfilesDocument(profiles: <TerminalProfile>[profile]),
        ),
      );

      final stored = client.resources['profile/default']!;
      expect(stored.data.toString(), isNot(contains('profile-secret')));
      expect(stored.data.toString(), isNot(contains('private-key-contents')));
      expect(stored.sensitive.toString(), contains('profile-secret'));
      expect(stored.sensitive.toString(), contains('private-key-contents'));
      final loaded = await repository.load();
      expect(loaded.profiles.single.connection.password, 'profile-secret');
      expect(loaded.profiles.single.connection.privateKeys, const <String>[
        'private-key-contents',
      ]);

      final cleared = loaded.profiles.single.copyWith(
        connection: loaded.profiles.single.connection.copyWith(password: null),
      );
      snapshot = await repository.saveVersioned(
        snapshot.withValue(
          TerminalProfilesDocument(
            profiles: <TerminalProfile>[cleared],
            secretClearIntents: const <String, Set<ProfileSecretField>>{
              'work': <ProfileSecretField>{ProfileSecretField.password},
            },
          ),
        ),
      );
      expect(client.resources['profile/default']!.hasSensitive, isTrue);
      expect(
        client.resources['profile/default']!.sensitive.toString(),
        contains('private-key-contents'),
      );

      await repository.saveVersioned(
        snapshot.withValue(
          const TerminalProfilesDocument(profiles: <TerminalProfile>[]),
        ),
      );
      expect(client.resources, contains('profile/default'));
      expect((await repository.load()).profiles, isEmpty);
    },
  );

  test(
    'passwordless SSH profiles do not allocate a sensitive envelope',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiProfileRepository(client: client);
      final profile = TerminalProfile(
        id: 'agent-only',
        name: 'Agent only',
        shell: '/bin/zsh',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'agent.example.com',
          user: 'alice',
        ),
      );

      final snapshot = await repository.loadVersioned();
      await repository.saveVersioned(
        snapshot.withValue(
          TerminalProfilesDocument(profiles: <TerminalProfile>[profile]),
        ),
      );

      final stored = client.resources['profile/default']!;
      expect(stored.hasSensitive, isFalse);
      expect(stored.sensitive, isNull);
    },
  );

  test('profile default initialization adopts a concurrent winner', () async {
    final client = MemoryDataApiResourceClient();
    final winner = TerminalProfilesDocument(
      profiles: <TerminalProfile>[
        defaultTerminalProfile().copyWith(name: 'Remote winner'),
      ],
    );
    client.beforePut = (memory, kind, id) {
      memory.resources[memory.key(kind, id)] = dataApiTestResource(
        id: id,
        kind: kind,
        data: winner.toJson(),
        sensitive: null,
        hasSensitive: false,
        revision: 1,
      );
    };
    final repository = DataApiProfileRepository(client: client);

    final loaded = await repository.load();

    expect(loaded.profiles.single.name, 'Remote winner');
    expect(client.resources['profile/default']?.revision, 1);
    expect(
      client.getCount,
      2,
      reason:
          'Initialization must PUT expected_revision=0 immediately after the '
          '404, then perform only the bounded winner reread after conflict.',
    );
  });

  test(
    'profile update rebases once without losing a concurrent profile',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiProfileRepository(client: client);
      final base = await repository.loadVersioned();
      final concurrentProfile = defaultTerminalProfile().copyWith(
        id: 'phone',
        name: 'Added on iPhone',
      );
      final macProfile = defaultTerminalProfile().copyWith(
        id: 'mac-ssh',
        name: 'Mac SSH',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'ssh.example.test',
          user: 'operator',
        ),
      );
      client.beforePut = (memory, kind, id) {
        final existing = memory.resources[memory.key(kind, id)]!;
        final remote = TerminalProfilesDocument(
          profiles: <TerminalProfile>[
            ...base.value.profiles,
            concurrentProfile,
          ],
        );
        memory.resources[memory.key(kind, id)] = dataApiTestResource(
          id: id,
          kind: kind,
          data: remote.toJson(),
          revision: existing.revision + 1,
        );
      };

      final saved = await repository.updateVersioned(
        (current) => TerminalProfilesDocument(
          profiles: <TerminalProfile>[...current.profiles, macProfile],
        ),
        base: base,
      );

      expect(
        saved.value.profiles.map((profile) => profile.id),
        containsAll(<String>['phone', 'mac-ssh']),
      );
      expect(
        (await repository.load()).profiles.map((profile) => profile.id),
        containsAll(<String>['phone', 'mac-ssh']),
      );
    },
  );

  test(
    'paste history adapter stores the document only as sensitive data',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiPasteHistoryRepository(client: client);
      final document = PasteHistoryDocument(
        entries: <PasteHistoryEntry>[
          PasteHistoryEntry(
            text: 'secret command',
            kind: PasteHistoryKind.paste,
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      var snapshot = await repository.loadVersioned();
      snapshot = await repository.saveVersioned(snapshot.withValue(document));

      final stored = client.resources['paste_history/default']!;
      expect(stored.data.toString(), isNot(contains('secret command')));
      expect(stored.sensitive.toString(), contains('secret command'));
      expect((await repository.load())?.entries.single.text, 'secret command');

      snapshot = await repository.clearDiskHistoryVersioned(snapshot);
      final cleared = client.resources['paste_history/default']!;
      expect(cleared.hasSensitive, isFalse);
      expect((await repository.load())?.entries, isEmpty);

      await repository.saveVersioned(snapshot.withValue(document));
      expect((await repository.load())?.entries.single.text, 'secret command');
      expect(client.resources['paste_history/default']?.revision, 3);
      expect(client.deleteCount, 0);
    },
  );

  group('Data API wire decoders fail closed', () {
    test(
      'layout revalidates identity and tombstones on load and save',
      () async {
        await _verifyResourceIdentityBoundary(
          kind: DataApiTerminalLayoutRepository.resourceKind,
          id: DataApiTerminalLayoutRepository.resourceId,
          validResource: dataApiTestResource(
            id: DataApiTerminalLayoutRepository.resourceId,
            kind: DataApiTerminalLayoutRepository.resourceKind,
            data: const <String, Object?>{'format': 'ianvs-terminal-layout-v1'},
            sensitive: const TerminalLayout().toJson(),
            hasSensitive: true,
            revision: 1,
          ),
          load: (client) =>
              DataApiTerminalLayoutRepository(client: client).loadVersioned(),
          save: (client) =>
              DataApiTerminalLayoutRepository(client: client).saveVersioned(
                const VersionedDocument<TerminalLayout>(
                  value: TerminalLayout(),
                  revision: 0,
                ),
              ),
        );
      },
    );

    test(
      'preferences revalidate identity and tombstones on load and save',
      () async {
        await _verifyResourceIdentityBoundary(
          kind: DataApiAppPreferencesRepository.resourceKind,
          id: DataApiAppPreferencesRepository.resourceId,
          validResource: dataApiTestResource(
            id: DataApiAppPreferencesRepository.resourceId,
            kind: DataApiAppPreferencesRepository.resourceKind,
            data: const TerminalAppPreferencesDocument().toJson(),
            sensitive: null,
            hasSensitive: false,
            revision: 1,
          ),
          load: (client) =>
              DataApiAppPreferencesRepository(client: client).loadVersioned(),
          save: (client) =>
              DataApiAppPreferencesRepository(client: client).saveVersioned(
                const VersionedDocument<TerminalAppPreferencesDocument>(
                  value: TerminalAppPreferencesDocument(),
                  revision: 0,
                ),
              ),
        );
      },
    );

    test(
      'paste revalidates identity and tombstones on load and save',
      () async {
        await _verifyResourceIdentityBoundary(
          kind: DataApiPasteHistoryRepository.resourceKind,
          id: DataApiPasteHistoryRepository.resourceId,
          validResource: dataApiTestResource(
            id: DataApiPasteHistoryRepository.resourceId,
            kind: DataApiPasteHistoryRepository.resourceKind,
            data: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
            sensitive: const PasteHistoryDocument().toJson(),
            hasSensitive: true,
            revision: 1,
          ),
          load: (client) =>
              DataApiPasteHistoryRepository(client: client).loadVersioned(),
          save: (client) =>
              DataApiPasteHistoryRepository(client: client).saveVersioned(
                const VersionedDocument<PasteHistoryDocument>(
                  value: PasteHistoryDocument(),
                  revision: 0,
                ),
              ),
        );
      },
    );

    test(
      'profiles revalidate identity and tombstones on load and save',
      () async {
        const document = TerminalProfilesDocument(
          profiles: <TerminalProfile>[],
        );
        await _verifyResourceIdentityBoundary(
          kind: DataApiProfileRepository.resourceKind,
          id: DataApiProfileRepository.resourceId,
          validResource: dataApiTestResource(
            id: DataApiProfileRepository.resourceId,
            kind: DataApiProfileRepository.resourceKind,
            data: document.toJson(),
            sensitive: null,
            hasSensitive: false,
            revision: 1,
          ),
          load: (client) =>
              DataApiProfileRepository(client: client).loadVersioned(),
          save: (client) =>
              DataApiProfileRepository(client: client).saveVersioned(
                const VersionedDocument<TerminalProfilesDocument>(
                  value: document,
                  revision: 0,
                ),
              ),
        );
      },
    );

    test(
      'layout rejects a dangling active-tab reference without PUT',
      () async {
        final client = MemoryDataApiResourceClient();
        client.resources['session/layout'] = dataApiTestResource(
          id: 'layout',
          kind: 'session',
          data: <String, Object?>{'format': 'ianvs-terminal-layout-v1'},
          sensitive: <String, Object?>{
            'schemaVersion': currentTerminalLayoutSchemaVersion,
            'contract': terminalLayoutContract,
            'tabs': <Object?>[],
            'activeTabId': 'missing-tab',
          },
          hasSensitive: true,
          revision: 7,
        );

        await expectLater(
          DataApiTerminalLayoutRepository(client: client).loadVersioned(),
          throwsFormatException,
        );
        expect(client.putCount, 0);
      },
    );

    test('preferences reject missing schema without PUT', () async {
      final client = MemoryDataApiResourceClient();
      client.resources['config/preferences'] = dataApiTestResource(
        id: 'preferences',
        kind: 'config',
        data: <String, Object?>{
          'defaults': <String, Object?>{'defaultProfileId': null},
          'appearance': <String, Object?>{
            'themeMode': 'system',
            'terminalViewportPadding': 8.0,
          },
          'notifications': <String, Object?>{
            'commandFinished': true,
            'bell': true,
            'activity': true,
          },
        },
        sensitive: null,
        hasSensitive: false,
        revision: 4,
      );

      await expectLater(
        DataApiAppPreferencesRepository(client: client).loadVersioned(),
        throwsA(isA<UnsupportedTerminalAppPreferencesSchemaVersion>()),
      );
      expect(client.putCount, 0);
    });

    test(
      'terminal config rejects missing and noncurrent schemas without PUT',
      () async {
        for (final data in <Map<String, Object?>>[
          const <String, Object?>{},
          const <String, Object?>{'schemaVersion': 0},
        ]) {
          final client = MemoryDataApiResourceClient();
          client.resources['config/local-terminal'] = dataApiTestResource(
            id: DataApiTerminalConfigRepository.resourceId,
            kind: DataApiTerminalConfigRepository.resourceKind,
            data: data,
            sensitive: null,
            hasSensitive: false,
            revision: 3,
          );
          final repository = DataApiTerminalConfigRepository(client: client);

          await expectLater(
            repository.loadVersioned(),
            throwsA(isA<UnsupportedLocalTerminalConfigSchemaVersion>()),
          );
          await expectLater(
            repository.update((current) => current),
            throwsA(isA<UnsupportedLocalTerminalConfigSchemaVersion>()),
          );
          expect(client.putCount, 0);
        }
      },
    );

    test(
      'terminal config rejects noncanonical current data without PUT',
      () async {
        final client = MemoryDataApiResourceClient();
        client.resources['config/local-terminal'] = dataApiTestResource(
          id: DataApiTerminalConfigRepository.resourceId,
          kind: DataApiTerminalConfigRepository.resourceKind,
          data: const <String, Object?>{'schemaVersion': 1},
          sensitive: null,
          hasSensitive: false,
          revision: 3,
        );
        final repository = DataApiTerminalConfigRepository(client: client);

        await expectLater(repository.loadVersioned(), throwsFormatException);
        await expectLater(
          repository.update((current) => current),
          throwsFormatException,
        );
        expect(client.putCount, 0);
      },
    );

    test('paste history rejects duplicate entries without PUT', () async {
      final client = MemoryDataApiResourceClient();
      final duplicate = <String, Object?>{
        'text': 'secret',
        'kind': 'paste',
        'createdAt': DateTime.utc(2026).toIso8601String(),
      };
      client.resources['paste_history/default'] = dataApiTestResource(
        id: 'default',
        kind: 'paste_history',
        data: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
        sensitive: <String, Object?>{
          'schema_version': pasteHistoryCurrentSchemaVersion,
          'entries': <Object?>[duplicate, duplicate],
        },
        hasSensitive: true,
        revision: 9,
      );

      await expectLater(
        DataApiPasteHistoryRepository(client: client).loadVersioned(),
        throwsFormatException,
      );
      expect(client.putCount, 0);
    });

    test('profiles reject duplicate identities without PUT', () async {
      final client = MemoryDataApiResourceClient();
      final profile = defaultTerminalProfile().toJson();
      client.resources['profile/default'] = dataApiTestResource(
        id: 'default',
        kind: 'profile',
        data: <String, Object?>{
          'schemaVersion': TerminalProfilesDocument.currentSchemaVersion,
          'profiles': <Object?>[profile, profile],
        },
        sensitive: null,
        hasSensitive: false,
        revision: 6,
      );

      await expectLater(
        DataApiProfileRepository(client: client).loadVersioned(),
        throwsFormatException,
      );
      expect(client.putCount, 0);
    });

    test('profiles reject sensitive identity overrides without PUT', () async {
      final client = MemoryDataApiResourceClient();
      final profile = defaultTerminalProfile().toJson();
      client.resources['profile/default'] = dataApiTestResource(
        id: 'default',
        kind: 'profile',
        data: <String, Object?>{
          'schemaVersion': TerminalProfilesDocument.currentSchemaVersion,
          'profiles': <Object?>[profile],
        },
        sensitive: const <String, Object?>{
          'profiles': <Object?>[
            <String, Object?>{'id': 'overridden'},
          ],
        },
        hasSensitive: true,
        revision: 6,
      );

      await expectLater(
        DataApiProfileRepository(client: client).loadVersioned(),
        throwsFormatException,
      );
      expect(client.putCount, 0);
    });
  });

  test(
    'layout adopts a committed write after its response times out',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiTerminalLayoutRepository(client: client);
      final missing = await repository.loadVersioned();
      client.putResponse = (_) =>
          throw const DataApiTimeoutException(Duration(seconds: 15));

      final saved = await repository.saveVersioned(
        missing.withValue(const TerminalLayout()),
      );

      expect(saved.revision, 1);
      expect(client.putCount, 1);
      expect(client.getCount, 2);
    },
  );

  test(
    'layout exposes a retryable error when timeout was not committed',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiTerminalLayoutRepository(client: client);
      final missing = await repository.loadVersioned();
      client.beforePut = (_, _, _) =>
          throw const DataApiTimeoutException(Duration(seconds: 15));

      await expectLater(
        repository.saveVersioned(missing.withValue(const TerminalLayout())),
        throwsA(isA<TerminalLayoutSaveUnavailableException>()),
      );
      expect(client.putCount, 0);
      expect(client.getCount, 2);
    },
  );

  test(
    'an inaccessible API adapter fails instead of using a local source',
    () async {
      final repository = DataApiTerminalConfigRepository(
        client: MemoryDataApiResourceClient(canAccessResources: false),
      );

      await expectLater(
        repository.load(),
        throwsA(isA<DataApiAuthenticationRequiredException>()),
      );
    },
  );

  test('memory API preserves tombstone revisions after delete', () async {
    final client = MemoryDataApiResourceClient();
    await client.putResource(
      kind: 'config',
      id: 'deleted',
      data: const <String, Object?>{'value': 1},
      expectedRevision: 0,
    );

    expect(
      await client.deleteResource(
        kind: 'config',
        id: 'deleted',
        expectedRevision: 1,
      ),
      isTrue,
    );
    expect(await client.getResource(kind: 'config', id: 'deleted'), isNull);
    await expectLater(
      client.putResource(
        kind: 'config',
        id: 'deleted',
        data: const <String, Object?>{'value': 2},
        expectedRevision: 0,
      ),
      throwsA(isA<DataApiRevisionConflictException>()),
    );
  });

  test(
    'terminal config update rebases a pure transform after conflict',
    () async {
      final client = MemoryDataApiResourceClient();
      final repository = DataApiTerminalConfigRepository(client: client);
      final snapshot = await repository.loadVersioned();
      await repository.saveVersioned(
        snapshot.withValue(
          const LocalTerminalConfigDocument(defaultProfileId: 'work'),
        ),
      );
      client.beforePut = (memory, kind, id) {
        final key = memory.key(kind, id);
        final existing = memory.resources[key]!;
        memory.resources[key] = dataApiTestResource(
          id: existing.id,
          kind: existing.kind,
          data: const LocalTerminalConfigDocument(
            defaultProfileId: 'remote',
          ).toJson(),
          sensitive: existing.sensitive,
          hasSensitive: existing.hasSensitive,
          revision: existing.revision + 1,
        );
      };

      final updated = await repository.update(
        (current) => current.copyWith(
          defaultProfileId: '${current.defaultProfileId}-local',
        ),
      );

      expect(updated.defaultProfileId, 'remote-local');
      expect((await repository.load())?.defaultProfileId, 'remote-local');
    },
  );

  test('a stale aggregate cannot borrow a later load revision', () async {
    final client = MemoryDataApiResourceClient();
    final repository = DataApiTerminalConfigRepository(client: client);
    final missing = await repository.loadVersioned();
    await repository.saveVersioned(
      missing.withValue(
        const LocalTerminalConfigDocument(defaultProfileId: 'work'),
      ),
    );
    final staleA = await repository.loadVersioned();
    await client.putResource(
      kind: DataApiTerminalConfigRepository.resourceKind,
      id: DataApiTerminalConfigRepository.resourceId,
      data: const LocalTerminalConfigDocument(
        defaultProfileId: 'remote-b',
      ).toJson(),
      expectedRevision: staleA.revision,
    );
    final laterB = await repository.loadVersioned();
    expect(laterB.revision, 2);

    await expectLater(
      repository.saveVersioned(
        staleA.withValue(
          const LocalTerminalConfigDocument(defaultProfileId: 'stale-a'),
        ),
      ),
      throwsA(isA<DataApiRevisionConflictException>()),
    );
    expect((await repository.load())?.defaultProfileId, 'remote-b');
  });
}

typedef _AdapterOperation =
    Future<Object?> Function(MemoryDataApiResourceClient client);

Future<void> _verifyResourceIdentityBoundary({
  required String kind,
  required String id,
  required DataApiResource validResource,
  required _AdapterOperation load,
  required _AdapterOperation save,
}) async {
  final invalidResponses = <DataApiResource>[
    _copyResource(validResource, id: 'wrong-id'),
    _copyResource(validResource, kind: 'wrong-kind'),
    _copyResource(validResource, deleted: true),
  ];
  for (final invalid in invalidResponses) {
    final loadClient = MemoryDataApiResourceClient();
    loadClient.resources[loadClient.key(kind, id)] = invalid;
    await expectLater(load(loadClient), throwsFormatException);
    expect(loadClient.putCount, 0);

    final saveClient = MemoryDataApiResourceClient()
      ..putResponse = (_) => invalid;
    await expectLater(save(saveClient), throwsFormatException);
    expect(saveClient.putCount, 1);
  }
}

DataApiResource _copyResource(
  DataApiResource source, {
  String? id,
  String? kind,
  bool? deleted,
}) {
  return dataApiTestResource(
    id: id ?? source.id,
    kind: kind ?? source.kind,
    data: source.data,
    sensitive: source.sensitive,
    hasSensitive: source.hasSensitive,
    revision: source.revision,
    sourceId: source.sourceId,
    sourceRevision: source.sourceRevision,
    sourceUpdatedAt: source.sourceUpdatedAt,
    deleted: deleted ?? source.deleted,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
  );
}

Future<void> _verifyTerminalConfigContract(
  TerminalConfigRepository repository,
) async {
  final missing = await repository.loadVersioned();
  expect(missing.value, isNull);

  await repository.saveVersioned(
    missing.withValue(
      const LocalTerminalConfigDocument(defaultProfileId: 'work'),
    ),
  );
  expect((await repository.load())?.defaultProfileId, 'work');

  final updated = await repository.update(
    (current) => current.copyWith(defaultProfileId: 'personal'),
  );
  expect(updated.defaultProfileId, 'personal');
  expect((await repository.load())?.defaultProfileId, 'personal');
}

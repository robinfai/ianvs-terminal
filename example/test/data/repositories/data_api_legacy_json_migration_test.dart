import 'dart:async';
import 'dart:io';

import 'package:app/data/repositories/data_api_installation_identity_repository.dart';
import 'package:app/data/repositories/data_api_legacy_json_migration.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_recent_items_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/shell/paste_history_repository.dart';
import 'package:app/features/visual/local_terminal_layout_template_repository.dart';
import 'package:app/features/visual/local_terminal_theme_repository.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_data_api_resource_client.dart';

void main() {
  const installationIdentity = DataApiInstallationIdentity(
    '12345678-1234-4234-9234-123456789abc',
  );
  late Directory temporaryDirectory;
  late MemoryDataApiResourceClient client;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-data-api-migration-',
    );
    client = MemoryDataApiResourceClient();
    Future<Directory> resolveDirectory() async => temporaryDirectory;
    await ProfileRepository(directoryResolver: resolveDirectory).save(
      TerminalProfilesDocument(
        profiles: <TerminalProfile>[defaultTerminalProfile()],
      ),
    );
    await AppPreferencesRepository(
      directoryResolver: resolveDirectory,
    ).save(const TerminalAppPreferencesDocument());
    await LocalTerminalConfigRepository(
      directoryResolver: resolveDirectory,
    ).save(const LocalTerminalConfigDocument(defaultProfileId: 'default'));
    await LocalTerminalLayoutRepository(
      directoryResolver: resolveDirectory,
    ).save(const TerminalLayout());
    await LocalTerminalThemeRepository(
      directoryResolver: resolveDirectory,
    ).save(const []);
    await LocalTerminalLayoutTemplateRepository(
      directoryResolver: resolveDirectory,
    ).save(const []);
    await ShellRecentItemsRepository(
      directoryResolver: resolveDirectory,
    ).save(const ShellRecentItemsState());
    await PasteHistoryRepository(
      directoryResolver: resolveDirectory,
    ).save(const PasteHistoryDocument());
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('imports every production-wired resource and writes a marker', () async {
    final migration = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    );

    final report = await migration.run();

    expect(report.alreadyCompleted, isFalse);
    expect(report.resources.keys, <String>{
      'profiles',
      'preferences',
      'terminalConfig',
      'terminalLayout',
      'pasteHistory',
    });
    expect(
      report.resources.values,
      everyElement(DataApiLegacyResourceMigrationStatus.migrated),
    );
    expect(client.resources, contains('profile/default'));
    expect(client.resources, contains('config/preferences'));
    expect(client.resources, contains('config/local-terminal'));
    expect(client.resources, contains('session/layout'));
    expect(client.resources, contains('paste_history/default'));
    expect(client.resources.keys, isNot(contains(startsWith('theme/'))));
    expect(
      client.resources.keys,
      isNot(contains(startsWith('layout_template/'))),
    );
    expect(client.resources, isNot(contains('recent_items/default')));
    expect(
      client.resources,
      contains(
        '${DataApiLegacyJsonMigration.markerKind}/'
        '${installationIdentity.migrationMarkerId}',
      ),
    );
    final marker =
        client.resources['${DataApiLegacyJsonMigration.markerKind}/'
            '${installationIdentity.migrationMarkerId}']!;
    expect(marker.data.toString(), contains('source_snapshot'));
    expect(marker.data.toString(), contains('ianvs_profiles.json'));
    expect((await migration.run()).alreadyCompleted, isTrue);
  });

  test('a completed marker is rejected after a local source changes', () async {
    final migration = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    );
    await migration.run();
    final preferencesFile = File(
      '${temporaryDirectory.path}/ianvs_preferences.json',
    );
    await preferencesFile.writeAsString(
      (await preferencesFile.readAsString()).replaceFirst('"system"', '"dark"'),
      flush: true,
    );

    await expectLater(
      migration.run(),
      throwsA(isA<DataApiLegacyJsonMigrationSourceChangedException>()),
    );
  });

  test('a source change during marker write leaves startup locked', () async {
    final preferencesFile = File(
      '${temporaryDirectory.path}/ianvs_preferences.json',
    );
    client.beforePut = (memory, kind, id) {
      if (kind == DataApiLegacyJsonMigration.markerKind &&
          id == installationIdentity.migrationMarkerId) {
        preferencesFile.writeAsStringSync(
          preferencesFile.readAsStringSync().replaceFirst(
            '"system"',
            '"light"',
          ),
          flush: true,
        );
      }
    };
    final migration = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    );

    await expectLater(
      migration.run(),
      throwsA(isA<DataApiLegacyJsonMigrationSourceChangedException>()),
    );
    await expectLater(
      migration.run(),
      throwsA(isA<DataApiLegacyJsonMigrationSourceChangedException>()),
    );
  });

  test('a legacy marker without a source snapshot fails closed', () async {
    await client.putResource(
      kind: DataApiLegacyJsonMigration.markerKind,
      id: installationIdentity.migrationMarkerId,
      data: const <String, Object?>{'version': 1},
      expectedRevision: 0,
    );

    await expectLater(
      DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      ).run(),
      throwsA(
        isA<DataApiProtocolException>().having(
          (error) => error.message,
          'message',
          contains('identity, decision, or source snapshot'),
        ),
      ),
    );
  });

  test(
    'marker identity decision and decision-specific fields are strict',
    () async {
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      await migration.run();
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );
      final original = client.resources[markerKey]!;
      final originalData = (original.data! as Map).cast<String, Object?>();
      final originalSnapshot = (originalData['source_snapshot']! as Map)
          .cast<String, Object?>();
      final invalidDocuments = <Map<String, Object?>>[
        <String, Object?>{
          ...originalData,
          'source_id': 'different-installation-source',
        },
        <String, Object?>{...originalData, 'decision': 'automatic'},
        <String, Object?>{...originalData}..remove('completed_at'),
        <String, Object?>{
          ...originalData,
          'decision': 'keep_remote',
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        },
        <String, Object?>{
          ...originalData,
          'source_snapshot': <String, Object?>{
            ...originalSnapshot,
            'unexpected': true,
          },
        },
      ];

      for (final invalid in invalidDocuments) {
        client.resources[markerKey] = dataApiTestResource(
          id: original.id,
          kind: original.kind,
          data: invalid,
          sensitive: null,
          hasSensitive: false,
          revision: original.revision,
        );
        await expectLater(
          migration.run(),
          throwsA(isA<DataApiProtocolException>()),
        );
      }
    },
  );

  test('an oversized legacy source is rejected before it is read', () async {
    final profilesFile = File('${temporaryDirectory.path}/ianvs_profiles.json');
    final handle = await profilesFile.open(mode: FileMode.write);
    await handle.truncate(DataApiClient.maximumJsonResponseBytes + 1);
    await handle.close();

    await expectLater(
      DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      ).run(),
      throwsA(
        isA<DataApiLegacyJsonMigrationSourceTooLargeException>().having(
          (error) => error.path,
          'path',
          profilesFile.path,
        ),
      ),
    );
    expect(client.resources, isEmpty);
  });

  test('conflict preserves destination and does not write marker', () async {
    await client.putResource(
      kind: 'config',
      id: 'preferences',
      data: const <String, Object?>{'destination': true},
    );
    final migration = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    );

    await expectLater(
      migration.run(),
      throwsA(
        isA<DataApiLegacyJsonMigrationConflictException>().having(
          (error) => error.resources['preferences'],
          'preferences',
          DataApiLegacyResourceMigrationStatus.destinationAlreadyExists,
        ),
      ),
    );
    expect(client.resources['config/preferences']?.data, <String, Object?>{
      'destination': true,
    });
    expect(
      client.resources,
      isNot(
        contains(
          '${DataApiLegacyJsonMigration.markerKind}/'
          '${installationIdentity.migrationMarkerId}',
        ),
      ),
    );
  });

  test(
    'a failed transactional merge retries without writing the marker',
    () async {
      client.mergeFailuresRemaining = 1;
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );

      await expectLater(migration.run(), throwsA(isA<Exception>()));
      expect(client.resources, isEmpty);

      final retried = await migration.run();

      expect(retried.alreadyCompleted, isFalse);
      expect(client.resources, contains('profile/default'));
      expect(
        client.resources,
        contains(
          '${DataApiLegacyJsonMigration.markerKind}/'
          '${installationIdentity.migrationMarkerId}',
        ),
      );
    },
  );

  test(
    'a marker write failure retries an idempotent merge before completion',
    () async {
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );
      client.failNextPutKeys.add(markerKey);
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );

      await expectLater(
        migration.run(),
        throwsA(isA<DataApiRequestException>()),
      );
      expect(client.resources, contains('profile/default'));
      expect(client.resources, isNot(contains(markerKey)));

      final retried = await migration.run();

      expect(retried.alreadyCompleted, isFalse);
      expect(client.resources, contains(markerKey));
      expect(client.mergeCount, 10);
    },
  );

  test(
    'third resource failure retries skipped batches and completes the marker',
    () async {
      client.failMergeCalls.add(3);
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );

      await expectLater(
        migration.run(),
        throwsA(isA<DataApiRequestException>()),
      );

      expect(client.resources, contains('profile/default'));
      expect(client.resources, contains('config/preferences'));
      expect(client.resources, isNot(contains('config/local-terminal')));
      expect(client.resources, isNot(contains(markerKey)));

      final retried = await migration.run();

      expect(retried.alreadyCompleted, isFalse);
      expect(client.resources, contains('config/local-terminal'));
      expect(client.resources, contains('session/layout'));
      expect(client.resources, contains('paste_history/default'));
      expect(client.resources, contains(markerKey));
      expect(client.mergeCount, 8);
    },
  );

  test(
    'corrupt revision journal stays locked until an explicit reset',
    () async {
      client.failMergeCalls.add(3);
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      await expectLater(
        migration.run(),
        throwsA(isA<DataApiRequestException>()),
      );
      final journal = File(
        '${temporaryDirectory.path}/data-api/'
        'migration-revisions-${installationIdentity.id}.json',
      );
      await journal.writeAsString('{not-json', flush: true);

      late DataApiLegacyJsonMigrationJournalRecoveryRequiredException error;
      try {
        await migration.run();
        fail('Expected the corrupt journal to keep migration locked.');
      } on DataApiLegacyJsonMigrationJournalRecoveryRequiredException catch (
        caught
      ) {
        error = caught;
      }
      expect(await journal.readAsString(), '{not-json');
      expect(client.mergeCount, 3);

      await migration.acknowledgeResetRevisionJournal(error);
      expect(await journal.exists(), isFalse);
      expect(
        journal.parent.listSync().whereType<File>().any(
          (file) => file.path.contains('.json.reset-'),
        ),
        isTrue,
      );

      client.failMergeCalls.add(4);
      await expectLater(
        migration.run(),
        throwsA(isA<DataApiRequestException>()),
      );
      final quarantineCount = journal.parent
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.json.reset-'))
          .length;
      await migration.acknowledgeResetRevisionJournal(error);
      expect(
        journal.parent.listSync().whereType<File>().where(
          (file) => file.path.contains('.json.reset-'),
        ),
        hasLength(quarantineCount),
      );

      final report = await migration.run();
      expect(report.alreadyCompleted, isFalse);
      expect(
        client.resources,
        contains(
          client.key(
            DataApiLegacyJsonMigration.markerKind,
            installationIdentity.migrationMarkerId,
          ),
        ),
      );
    },
  );

  test(
    'a forged skipped result must match the stored source and payload',
    () async {
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );
      client.failNextPutKeys.add(markerKey);
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      await expectLater(
        migration.run(),
        throwsA(isA<DataApiRequestException>()),
      );
      final preferencesKey = client.key('config', 'preferences');
      final existing = client.resources[preferencesKey]!;
      client.resources[preferencesKey] = dataApiTestResource(
        id: existing.id,
        kind: existing.kind,
        data: const <String, Object?>{'forged': true},
        sensitive: existing.sensitive,
        hasSensitive: existing.hasSensitive,
        revision: existing.revision,
        sourceId: existing.sourceId,
        sourceRevision: existing.sourceRevision,
        sourceUpdatedAt: existing.sourceUpdatedAt,
        deleted: existing.deleted,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
      );
      client.forceSkippedMergeKeys.add(preferencesKey);

      await expectLater(
        migration.run(),
        throwsA(
          isA<DataApiLegacyJsonMigrationSkippedMismatchException>()
              .having((error) => error.kind, 'kind', 'config')
              .having((error) => error.id, 'id', 'preferences'),
        ),
      );
      expect(client.resources, isNot(contains(markerKey)));
    },
  );

  test(
    'same-size same-mtime source rewrite prevents completion marker',
    () async {
      final preferencesFile = File(
        '${temporaryDirectory.path}/ianvs_preferences.json',
      );
      final original = await preferencesFile.readAsString();
      final originalModified = (await preferencesFile.stat()).modified;
      final replacement = original.replaceFirst('"system"', '"dark  "');
      expect(replacement.length, original.length);
      client.beforeMerge = (memory, mergeCount) async {
        if (mergeCount != 5) {
          return;
        }
        await preferencesFile.writeAsString(replacement, flush: true);
        await preferencesFile.setLastModified(originalModified);
      };
      final migration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );

      await expectLater(
        migration.run(),
        throwsA(
          isA<DataApiLegacyJsonMigrationSourceChangedException>().having(
            (error) => error.paths,
            'paths',
            contains(preferencesFile.path),
          ),
        ),
      );

      expect(client.resources, isNot(contains(markerKey)));
      final preferenceKey = client.key('config', 'preferences');
      final firstRevision = client.migrationSourceRevisions[preferenceKey]!;
      var preferenceData =
          client.resources[preferenceKey]!.data! as Map<String, Object?>;
      var appearance = preferenceData['appearance']! as Map<String, Object?>;
      expect(appearance['themeMode'], 'system');

      client.beforeMerge = null;
      final retried = await DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      ).run();

      expect(retried.alreadyCompleted, isFalse);
      expect(
        client.migrationSourceRevisions[preferenceKey],
        greaterThan(firstRevision),
      );
      preferenceData =
          client.resources[preferenceKey]!.data! as Map<String, Object?>;
      appearance = preferenceData['appearance']! as Map<String, Object?>;
      expect(appearance['themeMode'], 'dark');
      expect(client.resources, contains(markerKey));
    },
  );

  test(
    'a legacy file appearing during migration prevents the marker',
    () async {
      final pasteHistoryFile = File(
        '${temporaryDirectory.path}/ianvs_paste_history.json',
      );
      await pasteHistoryFile.delete();
      client.beforeMerge = (memory, mergeCount) async {
        if (mergeCount != 4) {
          return;
        }
        Future<Directory> resolveDirectory() async => temporaryDirectory;
        await PasteHistoryRepository(
          directoryResolver: resolveDirectory,
        ).save(const PasteHistoryDocument());
      };
      final markerKey = client.key(
        DataApiLegacyJsonMigration.markerKind,
        installationIdentity.migrationMarkerId,
      );

      await expectLater(
        DataApiLegacyJsonMigration(
          appSupportDirectory: temporaryDirectory,
          client: client,
          installationIdentity: installationIdentity,
        ).run(),
        throwsA(
          isA<DataApiLegacyJsonMigrationSourceChangedException>().having(
            (error) => error.paths,
            'paths',
            contains(pasteHistoryFile.path),
          ),
        ),
      );

      expect(client.resources, isNot(contains(markerKey)));
    },
  );

  test('same-installation migration rejects concurrent work', () async {
    final mergeEntered = Completer<void>();
    final releaseMerge = Completer<void>();
    client.beforeMerge = (memory, mergeCount) async {
      if (mergeCount == 1) {
        mergeEntered.complete();
        await releaseMerge.future;
      }
    };
    final first = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    ).run();
    await mergeEntered.future;
    final concurrent = DataApiLegacyJsonMigration(
      appSupportDirectory: temporaryDirectory,
      client: client,
      installationIdentity: installationIdentity,
    );

    await expectLater(
      concurrent.run(),
      throwsA(isA<DataApiLegacyJsonMigrationBusyException>()),
    );
    releaseMerge.complete();
    await first;
  });

  test(
    'a second installation receives typed conflicts and no completion marker',
    () async {
      final firstMigration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: installationIdentity,
      );
      await firstMigration.run();
      const otherInstallation = DataApiInstallationIdentity(
        '87654321-4321-4321-8321-cba987654321',
      );
      final secondMigration = DataApiLegacyJsonMigration(
        appSupportDirectory: temporaryDirectory,
        client: client,
        installationIdentity: otherInstallation,
      );

      late DataApiLegacyJsonMigrationConflictException conflict;
      try {
        await secondMigration.run();
        fail('Expected the second installation to report conflicts.');
      } on DataApiLegacyJsonMigrationConflictException catch (error) {
        conflict = error;
      }

      expect(
        client.resources,
        isNot(
          contains(
            '${DataApiLegacyJsonMigration.markerKind}/'
            '${otherInstallation.migrationMarkerId}',
          ),
        ),
      );
      final runtime = DataApiRuntime.remote(
        baseUri: Uri.parse('https://sync.example.com/'),
        remoteAccessToken: 'access-token',
        encryptionKey: 'encryption-key-material',
      );

      await acknowledgeDataApiMigrationKeepRemote(
        runtime: runtime,
        appSupportDirectory: temporaryDirectory,
        conflict: conflict,
        resourceClient: client,
        installationIdentity: otherInstallation,
      );
      final prepared = await prepareDataApiPersistence(
        runtime: runtime,
        appSupportDirectory: temporaryDirectory,
        resourceClient: client,
        installationIdentity: otherInstallation,
      );

      expect(prepared?.alreadyCompleted, isTrue);
      final marker =
          client.resources['${DataApiLegacyJsonMigration.markerKind}/'
              '${otherInstallation.migrationMarkerId}']!;
      expect(marker.data.toString(), contains('keep_remote'));
      expect(marker.data.toString(), contains('preferences'));
      expect(marker.data.toString(), contains('source_snapshot'));

      final preferencesFile = File(
        '${temporaryDirectory.path}/ianvs_preferences.json',
      );
      await preferencesFile.writeAsString(
        (await preferencesFile.readAsString()).replaceFirst(
          '"system"',
          '"light"',
        ),
        flush: true,
      );
      await expectLater(
        secondMigration.run(),
        throwsA(isA<DataApiLegacyJsonMigrationSourceChangedException>()),
      );
    },
  );

  test(
    'composition exposes migration failure as a typed startup warning',
    () async {
      client.mergeFailuresRemaining = 1;

      await expectLater(
        prepareDataApiPersistence(
          runtime: DataApiRuntime.remote(
            baseUri: Uri.parse('https://sync.example.com/'),
            remoteAccessToken: 'access-token',
            encryptionKey: 'encryption-key-material',
          ),
          appSupportDirectory: temporaryDirectory,
          resourceClient: client,
          installationIdentity: installationIdentity,
        ),
        throwsA(
          isA<DataApiPersistencePreparationException>()
              .having(
                (error) => error.cause,
                'cause',
                isA<DataApiRequestException>(),
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('restart the app to retry'),
              ),
        ),
      );
    },
  );
}

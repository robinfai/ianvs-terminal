import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/data_api_json.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_migration_service.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late FileDataApiConfigurationRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-data-api-configuration-',
    );
    repository = FileDataApiConfigurationRepository(
      appSupportDirectory: temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('missing configuration defaults to disabled', () async {
    final configuration = await repository.load();

    expect(configuration.deployment, DataApiDeployment.disabled);
    expect(await repository.configurationFile.exists(), isFalse);
  });

  test('persists and reloads a remote configuration', () async {
    final configured = DataApiConfiguration.remote(
      'https://sync.example.com/api',
    );

    await repository.save(configured);
    final loaded = await repository.load();

    expect(loaded.deployment, DataApiDeployment.remote);
    expect(loaded.remoteBaseUri, configured.remoteBaseUri);
    expect(
      repository.configurationFile.path,
      contains('${Platform.pathSeparator}data-api${Platform.pathSeparator}'),
    );
  });

  test(
    'quarantines invalid config and requires explicit disabled confirmation',
    () async {
      await repository.configurationFile.parent.create(recursive: true);
      await repository.configurationFile.writeAsString('{"version":1}');

      await expectLater(
        repository.load(),
        throwsA(isA<DataApiConfigurationRecoveryRequiredException>()),
      );

      expect(repository.recoveryRequired, isTrue);
      expect(await repository.recoverySentinelFile.exists(), isTrue);
      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(await repository.configurationFile.exists(), isTrue);
      expect(
        await repository.configurationFile.readAsString(),
        contains('"recovery_required":true'),
      );
      expect(
        repository.configurationFile.parent.listSync().any(
          (entry) => entry.path.contains('configuration.json.corrupt'),
        ),
        isTrue,
      );
      final restartedRepository = FileDataApiConfigurationRepository.forFile(
        repository.configurationFile,
      );

      await expectLater(
        restartedRepository.load(),
        throwsA(isA<DataApiConfigurationRecoveryRequiredException>()),
      );
      expect(restartedRepository.recoveryRequired, isTrue);
      expect(
        await restartedRepository.load(),
        const DataApiConfiguration.disabled(),
      );

      await restartedRepository.save(const DataApiConfiguration.disabled());

      expect(restartedRepository.recoveryRequired, isFalse);
      expect(await restartedRepository.recoverySentinelFile.exists(), isFalse);
      expect(
        await repository.configurationFile.readAsString(),
        isNot(contains('recovery_required')),
      );
    },
  );

  test('duplicate config keys fail closed without mutating evidence', () async {
    await repository.configurationFile.parent.create(recursive: true);
    const contents =
        '{"version":1,"deployment":"local","deployment":"disabled",'
        '"generation":0}\n';
    await repository.configurationFile.writeAsString(contents, flush: true);
    final modified = (await repository.configurationFile.stat()).modified;

    await expectLater(
      repository.load(),
      throwsA(isA<DataApiJsonDuplicateKeyException>()),
    );

    expect(await repository.configurationFile.readAsString(), contents);
    expect((await repository.configurationFile.stat()).modified, modified);
    expect(await repository.recoverySentinelFile.exists(), isFalse);
    expect(
      repository.configurationFile.parent.listSync().map((entry) => entry.path),
      <String>[repository.configurationFile.path],
    );
  });

  test('non-current config is typed and preserved byte-for-byte', () async {
    await repository.configurationFile.parent.create(recursive: true);
    const contents = '{"version":0,"deployment":"disabled","generation":0}\n';
    await repository.configurationFile.writeAsString(contents, flush: true);
    final modified = (await repository.configurationFile.stat()).modified;

    await expectLater(
      repository.load(),
      throwsA(isA<DataApiConfigurationUnsupportedVersionException>()),
    );

    expect(await repository.configurationFile.readAsString(), contents);
    expect((await repository.configurationFile.stat()).modified, modified);
    expect(await repository.recoverySentinelFile.exists(), isFalse);
  });

  test(
    'a durable recovery sentinel keeps startup locked after quarantine crash',
    () async {
      await repository.recoverySentinelFile.parent.create(recursive: true);
      await repository.recoverySentinelFile.writeAsString(
        '{"version":1,"reason":"configuration_corrupt"}\n',
      );
      expect(await repository.configurationFile.exists(), isFalse);

      final restarted = FileDataApiConfigurationRepository.forFile(
        repository.configurationFile,
      );
      await expectLater(
        restarted.load(),
        throwsA(isA<DataApiConfigurationRecoveryRequiredException>()),
      );
      expect(restarted.recoveryRequired, isTrue);
      expect(await restarted.load(), const DataApiConfiguration.disabled());
    },
  );

  test(
    'sentinel cleanup failure reports that configuration was saved',
    () async {
      await repository.recoverySentinelFile.parent.create(recursive: true);
      await repository.recoverySentinelFile.writeAsString('{"version":1}\n');
      final failingCleanup = FileDataApiConfigurationRepository.forFile(
        repository.configurationFile,
        deleteRecoverySentinel: (_) async {
          throw const FileSystemException('injected sentinel delete failure');
        },
      );

      await expectLater(
        failingCleanup.save(const DataApiConfiguration.local()),
        throwsA(
          isA<DataApiConfigurationRecoverySentinelException>()
              .having(
                (error) => error.configurationSaved,
                'configurationSaved',
                isTrue,
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('configuration was saved'),
              ),
        ),
      );

      await expectLater(
        repository.load(),
        throwsA(isA<DataApiConfigurationRecoveryRequiredException>()),
      );
      expect(await repository.load(), const DataApiConfiguration.local());
      expect(await repository.recoverySentinelFile.exists(), isTrue);
    },
  );

  test(
    'URL-only remote save is rejected and preserves the prior mode',
    () async {
      await repository.save(const DataApiConfiguration.local());
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: _MemoryRemoteSessionStore(),
        remoteConnectionValidator: _RecordingRemoteValidator(),
      );

      await expectLater(
        guarded.save(DataApiConfiguration.remote('https://sync.example.com/')),
        throwsA(isA<DataApiAuthenticationRequiredException>()),
      );

      expect(await repository.load(), const DataApiConfiguration.local());
    },
  );

  test('remote encryption key limits are measured in UTF-8 bytes', () {
    final validMultibyte = List.filled(4, '😀').join();
    final tooShort = List.filled(3, '😀').join();
    final tooLong = List.filled(257, '😀').join();

    expect(
      DataApiRemoteLoginRequest(
        baseUri: Uri.parse('https://sync.example.com/'),
        username: ' Alice ',
        password: ' password-1234 ',
        encryptionKey: validMultibyte,
      ),
      isA<DataApiRemoteLoginRequest>()
          .having((request) => request.username, 'username', 'alice')
          .having((request) => request.password, 'password', ' password-1234 ')
          .having(
            (request) => request.encryptionKey,
            'encryptionKey',
            validMultibyte,
          ),
    );
    const spacedKey = '  encryption-key-material  ';
    expect(
      DataApiRemoteLoginRequest(
        baseUri: Uri.parse('https://sync.example.com/'),
        username: 'alice',
        password: 'password-1234',
        encryptionKey: spacedKey,
      ).encryptionKey,
      spacedKey,
    );
    expect(
      DataApiRemoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
        accessToken: 'token',
        encryptionKey: spacedKey,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ).encryptionKey,
      spacedKey,
    );
    for (final invalid in <String>[tooShort, tooLong]) {
      expect(
        () => DataApiRemoteLoginRequest(
          baseUri: Uri.parse('https://sync.example.com/'),
          username: 'alice',
          password: 'password-1234',
          encryptionKey: invalid,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('16–1024 UTF-8 bytes'),
          ),
        ),
      );
      expect(
        () => DataApiRemoteSession(
          baseUri: Uri.parse('https://sync.example.com/'),
          accessToken: 'token',
          encryptionKey: invalid,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'login stores only the resulting secure session before config',
    () async {
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/api/'),
      );
      final store = _MemoryRemoteSessionStore();
      final authenticator = _RecordingRemoteAuthenticator(session: session);
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: authenticator,
        remoteConnectionValidator: _RecordingRemoteValidator(),
      );
      final request = DataApiRemoteLoginRequest(
        baseUri: Uri.parse('https://sync.example.com/api/'),
        username: 'alice',
        password: 'ephemeral-password',
        encryptionKey: 'encryption-key-material',
      );

      await guarded.connectAndSaveRemote(request);

      expect(authenticator.received, same(request));
      expect(store.slots.values, contains(same(session)));
      expect(await _activeSession(repository, store), same(session));
      expect(
        await repository.load(),
        DataApiConfiguration.remote('https://sync.example.com/api/'),
      );
      final plainConfiguration = await repository.configurationFile
          .readAsString();
      expect(plainConfiguration, isNot(contains('ephemeral-password')));
      expect(plainConfiguration, isNot(contains('access-token')));
      expect(plainConfiguration, isNot(contains('encryption-key-material')));
    },
  );

  test('remote login receives the one installed portable master key', () async {
    final masterKeys = PortableMasterKeyRepository(
      storage: _MemoryPortableMasterKeyStorage(),
    );
    final masterKey = await masterKeys.adoptLegacySecret(
      'portable-master-key-material',
    );
    final session = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
      encryptionKey: masterKey.secret,
    );
    final store = _MemoryRemoteSessionStore();
    final authenticator = _RecordingRemoteAuthenticator(session: session);
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteAuthenticator: authenticator,
      remoteConnectionValidator: _RecordingRemoteValidator(),
      masterKeyRepository: masterKeys,
    );

    await guarded.connectAndSaveRemote(
      DataApiRemoteLoginRequest(
        baseUri: session.baseUri,
        username: 'alice',
        password: 'ephemeral-password',
      ),
    );

    expect(authenticator.received?.encryptionKey, masterKey.secret);
    expect(
      (await _activeSession(repository, store))?.encryptionKey,
      masterKey.secret,
    );
  });

  test(
    'explicit local migration merges before committing remote configuration',
    () async {
      await repository.save(const DataApiConfiguration.local());
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final source = _RecordingMigrationClient(
        exportPages: <DataApiMigrationExportPage>[
          DataApiMigrationExportPage(
            sourceId: 'local-api-instance',
            resources: <DataApiMigrationResource>[
              DataApiMigrationResource(
                id: 'default',
                kind: 'profiles',
                data: const <String, Object?>{'schemaVersion': 1},
                sourceRevision: 1,
                sourceUpdatedAt: DateTime.utc(2026),
              ),
            ],
            nextCursor: null,
          ),
        ],
      );
      DataApiDeployment? deploymentObservedDuringMerge;
      final destination = _RecordingMigrationClient(
        mergeReports: const <DataApiMigrationMergeReport>[
          DataApiMigrationMergeReport(
            results: <DataApiMigrationMergeItem>[
              DataApiMigrationMergeItem(
                kind: 'profiles',
                id: 'default',
                status: 'created',
              ),
            ],
          ),
        ],
        beforeMerge: () async {
          deploymentObservedDuringMerge = (await repository.load()).deployment;
        },
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: _MemoryRemoteSessionStore(),
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: session),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        remoteSessionRevoker: _RecordingRemoteRevoker(),
        localToRemoteMigrationFactory: (_, _) =>
            DataApiMigrationService(source: source, destination: destination),
      );
      final localRuntime = DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:42100/'),
        localAccessToken: 'local-access-token',
        encryptionKey: 'local-encryption-key',
        closeLocalSidecar: () async {},
      );

      final summary = await guarded.migrateLocalAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: session.baseUri,
          username: 'alice',
          password: 'password-1234',
          encryptionKey: session.encryptionKey,
        ),
        sourceRuntime: localRuntime,
      );

      expect(deploymentObservedDuringMerge, DataApiDeployment.local);
      expect(summary.resourceCount, 1);
      expect((await repository.load()).deployment, DataApiDeployment.remote);
      expect(source.exportCalls, 1);
      expect(destination.mergeCalls, 1);
    },
  );

  test('local API cannot switch remotely without explicit migration', () async {
    await repository.save(const DataApiConfiguration.local());
    final session = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
    );
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: _MemoryRemoteSessionStore(),
      remoteAuthenticator: _RecordingRemoteAuthenticator(session: session),
      remoteConnectionValidator: _RecordingRemoteValidator(),
    );

    await expectLater(
      guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: session.baseUri,
          username: 'alice',
          password: 'password-1234',
          encryptionKey: session.encryptionKey,
        ),
      ),
      throwsA(isA<DataApiExplicitMigrationRequiredException>()),
    );

    expect((await repository.load()).deployment, DataApiDeployment.local);
  });

  test(
    'failed local migration retains local configuration and source ownership',
    () async {
      await repository.save(const DataApiConfiguration.local());
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final store = _MemoryRemoteSessionStore();
      final revoker = _RecordingRemoteRevoker();
      final destination = _RecordingMigrationClient(
        mergeReports: const <DataApiMigrationMergeReport>[
          DataApiMigrationMergeReport(
            results: <DataApiMigrationMergeItem>[
              DataApiMigrationMergeItem(
                kind: 'profiles',
                id: 'default',
                status: 'conflict',
              ),
            ],
          ),
        ],
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: session),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        remoteSessionRevoker: revoker,
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        localToRemoteMigrationFactory: (_, _) => DataApiMigrationService(
          source: _RecordingMigrationClient(
            exportPages: <DataApiMigrationExportPage>[
              DataApiMigrationExportPage(
                sourceId: 'local-api-instance',
                resources: <DataApiMigrationResource>[
                  DataApiMigrationResource(
                    id: 'default',
                    kind: 'profiles',
                    data: const <String, Object?>{'schemaVersion': 1},
                    sourceRevision: 1,
                    sourceUpdatedAt: DateTime.utc(2026),
                  ),
                ],
                nextCursor: null,
              ),
            ],
          ),
          destination: destination,
        ),
      );
      var localRuntimeClosed = false;
      final localRuntime = DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:42100/'),
        localAccessToken: 'local-access-token',
        encryptionKey: 'local-encryption-key',
        closeLocalSidecar: () async => localRuntimeClosed = true,
      );

      await expectLater(
        guarded.migrateLocalAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: session.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: session.encryptionKey,
          ),
          sourceRuntime: localRuntime,
        ),
        throwsA(isA<DataApiMigrationIncompleteException>()),
      );

      expect((await repository.load()).deployment, DataApiDeployment.local);
      expect(localRuntimeClosed, isFalse);
      expect(store.slots, isEmpty);
      expect(revoker.revoked, <DataApiRemoteSession>[session]);
    },
  );

  test(
    'explicit remote migration merges before committing local configuration',
    () async {
      const activeSlot = 'remoteMigrationSlot01';
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await repository.save(_persistedRemote(session.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()..slots[activeSlot] = session;
      final source = _RecordingMigrationClient(
        exportPages: <DataApiMigrationExportPage>[
          DataApiMigrationExportPage(
            sourceId: 'remote-api-instance',
            resources: <DataApiMigrationResource>[
              DataApiMigrationResource(
                id: 'default',
                kind: 'profiles',
                data: const <String, Object?>{'schemaVersion': 1},
                sourceRevision: 2,
                sourceUpdatedAt: DateTime.utc(2026),
              ),
            ],
            nextCursor: null,
          ),
        ],
      );
      DataApiDeployment? deploymentObservedDuringMerge;
      final destination = _RecordingMigrationClient(
        mergeReports: const <DataApiMigrationMergeReport>[
          DataApiMigrationMergeReport(
            results: <DataApiMigrationMergeItem>[
              DataApiMigrationMergeItem(
                kind: 'profiles',
                id: 'default',
                status: 'created',
              ),
            ],
          ),
        ],
        beforeMerge: () async {
          deploymentObservedDuringMerge = (await repository.load()).deployment;
        },
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: _RecordingRemoteRevoker(),
        runtimeMigrationFactory: (_, _) =>
            DataApiMigrationService(source: source, destination: destination),
      );
      final sourceRuntime = DataApiRuntime.remote(
        baseUri: session.baseUri,
        remoteAccessToken: session.accessToken,
        encryptionKey: session.encryptionKey,
      );
      final destinationRuntime = DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:42100/'),
        localAccessToken: 'local-access-token',
        encryptionKey: 'local-encryption-key',
        closeLocalSidecar: () async {},
      );

      final summary = await guarded.migrateRemoteAndSaveLocal(
        sourceRuntime: sourceRuntime,
        destinationRuntime: destinationRuntime,
      );

      expect(deploymentObservedDuringMerge, DataApiDeployment.remote);
      expect(summary.resourceCount, 1);
      expect((await repository.load()).deployment, DataApiDeployment.local);
      expect(source.exportCalls, 1);
      expect(destination.mergeCalls, 1);
    },
  );

  test(
    'begin capability is durably journaled before complete can issue a token',
    () async {
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      late final _RecordingRemoteAuthenticator authenticator;
      authenticator = _RecordingRemoteAuthenticator(
        session: session,
        beforeComplete: () async {
          final contents = await journal.readAsString();
          expect(contents, contains(authenticator.operation.operationId));
          expect(contents, contains('"phase":"authPrepared"'));
        },
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: _MemoryRemoteSessionStore(),
        remoteAuthenticator: authenticator,
        remoteConnectionValidator: _RecordingRemoteValidator(),
      );

      await guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: session.baseUri,
          username: 'alice',
          password: 'password-1234',
          encryptionKey: session.encryptionKey,
        ),
      );

      expect(authenticator.beginCalls, 1);
      expect(authenticator.completeCalls, 1);
    },
  );

  test(
    'crash persisting begin response never calls complete or issues a token',
    () async {
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final authenticator = _RecordingRemoteAuthenticator(session: session);
      var failedAuthPreparedWrite = false;
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: _MemoryRemoteSessionStore(),
        remoteAuthenticator: authenticator,
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        sagaJournalWriter: (file, contents) async {
          final document = jsonDecode(contents) as Map<String, Object?>;
          final transition = document['transition'];
          if (!failedAuthPreparedWrite &&
              transition is Map &&
              transition['phase'] == 'authPrepared') {
            failedAuthPreparedWrite = true;
            throw StateError('injected prepared capability journal crash');
          }
          await file.parent.create(recursive: true);
          await file.writeAsString(contents, flush: true);
        },
      );

      await expectLater(
        guarded.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: session.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: session.encryptionKey,
          ),
        ),
        throwsStateError,
      );

      expect(authenticator.beginCalls, 1);
      expect(authenticator.completeCalls, 0);
      expect(await repository.load(), const DataApiConfiguration.disabled());
    },
  );

  test('lost begin response cannot issue a token or require cancel', () async {
    final session = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
    );
    final authenticator = _RecordingRemoteAuthenticator(
      session: session,
      beginError: const DataApiTimeoutException(Duration(seconds: 5)),
    );
    final canceler = _RecordingAuthOperationCanceler();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: _MemoryRemoteSessionStore(),
      remoteAuthenticator: authenticator,
      authOperationCanceler: canceler,
    );

    await expectLater(
      guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: session.baseUri,
          username: 'alice',
          password: 'password-1234',
          encryptionKey: session.encryptionKey,
        ),
      ),
      throwsA(isA<DataApiTimeoutException>()),
    );

    expect(authenticator.beginCalls, 1);
    expect(authenticator.completeCalls, 0);
    expect(canceler.canceled, isEmpty);
    expect(await repository.load(), const DataApiConfiguration.disabled());
  });

  test(
    'complete response loss persists cancellation and retries after restart',
    () async {
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final firstCanceler = _RecordingAuthOperationCanceler(
        error: const DataApiTimeoutException(Duration(seconds: 5)),
      );
      final first = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: _MemoryRemoteSessionStore(),
        remoteAuthenticator: _RecordingRemoteAuthenticator(
          session: session,
          error: const DataApiTimeoutException(Duration(seconds: 5)),
        ),
        authOperationCanceler: firstCanceler,
      );

      await expectLater(
        first.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: session.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: session.encryptionKey,
          ),
        ),
        throwsA(isA<DataApiRemoteConfigurationRecoveryException>()),
      );
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      final failedContents = await journal.readAsString();
      expect(failedContents, contains('auth_cancellation_queue'));
      expect(failedContents, contains(List<String>.filled(43, 'A').join()));

      final retryCanceler = _RecordingAuthOperationCanceler();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: _MemoryRemoteSessionStore(),
        authOperationCanceler: retryCanceler,
      );
      await restarted.retryPendingRevocations();

      expect(retryCanceler.canceled, hasLength(1));
      expect(
        (jsonDecode(await journal.readAsString())
            as Map<String, Object?>)['auth_cancellation_queue'],
        isEmpty,
      );
      expect(await repository.load(), const DataApiConfiguration.disabled());
    },
  );

  test('failed key validation preserves mode and previous session', () async {
    await repository.save(const DataApiConfiguration.disabled());
    final store = _MemoryRemoteSessionStore();
    final canceler = _RecordingAuthOperationCanceler();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteAuthenticator: _RecordingRemoteAuthenticator(
        error: const DataApiRequestException(
          statusCode: 401,
          code: 'invalid_encryption_key',
          message: 'the encryption key is invalid',
        ),
      ),
      authOperationCanceler: canceler,
    );

    await expectLater(
      guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: Uri.parse('https://sync.example.com/'),
          username: 'alice',
          password: 'password-1234',
          encryptionKey: 'wrong-key-material',
        ),
      ),
      throwsA(
        isA<DataApiRequestException>().having(
          (error) => error.code,
          'code',
          'invalid_encryption_key',
        ),
      ),
    );

    expect(await repository.load(), const DataApiConfiguration.disabled());
    expect(store.slots, isEmpty);
    expect(canceler.canceled, hasLength(1));
  });

  test(
    'delete-only identity disposition survives a crash before local deletion',
    () async {
      const activeSlot = 'activeCredential0001';
      const duplicateSlot = 'duplicateCredential01';
      final active = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()
        ..slots[activeSlot] = active
        ..slots[duplicateSlot] = active;
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.writeAsString(
        '${jsonEncode(<String, Object?>{
          'version': 1,
          'revocation_queue': <String>[duplicateSlot],
          'delete_only_revocations': <String>[],
          'auth_cancellation_queue': <Object?>[],
        })}\n',
        flush: true,
      );
      var crashed = false;
      final revoker = _RecordingRemoteRevoker();
      final crashing = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
        sagaJournalWriter: (file, contents) async {
          await file.writeAsString(contents, flush: true);
          final root = jsonDecode(contents) as Map<String, Object?>;
          if (!crashed &&
              (root['delete_only_revocations'] as List?)?.contains(
                    duplicateSlot,
                  ) ==
                  true) {
            crashed = true;
            throw StateError('injected delete-only journal crash');
          }
        },
      );

      await expectLater(
        crashing.retryPendingRevocations(),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );
      expect(revoker.revoked, isEmpty);
      expect(
        store.slots.keys,
        containsAll(<String>[activeSlot, duplicateSlot]),
      );
      expect(await _activeSession(repository, store), same(active));

      final persistedJournal =
          jsonDecode(await journal.readAsString()) as Map<String, Object?>;
      expect(persistedJournal['delete_only_revocations'], <String>[
        duplicateSlot,
      ]);
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );
      await restarted.retryPendingRevocations();

      expect(revoker.revoked, isEmpty);
      expect(store.slots, <String, DataApiRemoteSession>{activeSlot: active});
      expect(await _activeSession(repository, store), same(active));
    },
  );

  test(
    'stale delete-only disposition cannot suppress required logout',
    () async {
      const retiredSlot = 'retiredCredential001';
      final retired = _remoteSession(
        baseUri: Uri.parse('https://retired.example.com/'),
      );
      await repository.save(const DataApiConfiguration.disabled());
      final store = _MemoryRemoteSessionStore()..slots[retiredSlot] = retired;
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.writeAsString(
        '${jsonEncode(<String, Object?>{
          'version': 1,
          'revocation_queue': <String>[retiredSlot],
          'delete_only_revocations': <String>[retiredSlot],
          'auth_cancellation_queue': <Object?>[],
        })}\n',
        flush: true,
      );
      final revoker = _RecordingRemoteRevoker();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );

      await guarded.retryPendingRevocations();

      expect(revoker.revoked, <DataApiRemoteSession>[retired]);
      expect(store.slots, isEmpty);
    },
  );

  test(
    'an unreadable active slot keeps revocation queued fail-closed',
    () async {
      const activeSlot = 'activeCredential0001';
      const retiredSlot = 'retiredCredential001';
      final active = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final retired = DataApiRemoteSession(
        baseUri: Uri.parse('https://old.example.com/'),
        accessToken: 'retired-access-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()
        ..slots[activeSlot] = active
        ..slots[retiredSlot] = retired
        ..failingSlotReadCalls[activeSlot] = <int>{2};
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.writeAsString(
        '${jsonEncode(<String, Object?>{
          'version': 1,
          'revocation_queue': <String>[retiredSlot],
          'delete_only_revocations': <String>[],
          'auth_cancellation_queue': <Object?>[],
        })}\n',
        flush: true,
      );
      final revoker = _RecordingRemoteRevoker();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );

      await expectLater(
        guarded.retryPendingRevocations(),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );
      expect(revoker.revoked, isEmpty);
      expect(store.slots[retiredSlot], same(retired));
      expect(
        (jsonDecode(await journal.readAsString())
            as Map<String, Object?>)['revocation_queue'],
        <String>[retiredSlot],
      );

      await guarded.retryPendingRevocations();
      expect(revoker.revoked, <DataApiRemoteSession>[retired]);
      expect(store.slots, <String, DataApiRemoteSession>{activeSlot: active});
    },
  );

  test(
    'remote config failure restores old session and revokes the new token',
    () async {
      final oldSession = _remoteSession(
        baseUri: Uri.parse('https://old.example.com/'),
      );
      final newSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
        accessToken: 'new-access-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      const oldSlot = 'oldCredentialSlot0001';
      final current = _persistedRemote(oldSession.baseUri, oldSlot);
      final store = _MemoryRemoteSessionStore()..slots[oldSlot] = oldSession;
      final revoker = _RecordingRemoteRevoker();
      final canceler = _RecordingAuthOperationCanceler();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: _FailingConfigurationRepository(current),
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: newSession),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        remoteSessionRevoker: revoker,
        authOperationCanceler: canceler,
      );

      await expectLater(
        guarded.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: newSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: 'encryption-key-material',
          ),
        ),
        throwsStateError,
      );

      expect(store.slots[oldSlot], same(oldSession));
      expect(revoker.revoked, <DataApiRemoteSession>[newSession]);
      expect(canceler.canceled, hasLength(1));
    },
  );

  test(
    'vault write failure restores old state and revokes new token',
    () async {
      final newSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
        accessToken: 'new-access-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final store = _MemoryRemoteSessionStore()
        ..writeError = StateError('credential vault write failed');
      final revoker = _RecordingRemoteRevoker(
        error: const DataApiTimeoutException(Duration(seconds: 5)),
      );
      final canceler = _RecordingAuthOperationCanceler();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: newSession),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        remoteSessionRevoker: revoker,
        authOperationCanceler: canceler,
      );

      await expectLater(
        guarded.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: newSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: 'encryption-key-material',
          ),
        ),
        throwsStateError,
      );

      expect(store.slots, isEmpty);
      expect(revoker.revoked, isEmpty);
      expect(canceler.canceled, hasLength(1));
    },
  );

  test(
    'config rollback attempts new-token revocation even if restore fails',
    () async {
      final oldSession = _remoteSession(
        baseUri: Uri.parse('https://old.example.com/'),
      );
      final newSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
        accessToken: 'new-access-token',
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      const oldSlot = 'oldCredentialSlot0001';
      final current = _persistedRemote(oldSession.baseUri, oldSlot);
      final store = _MemoryRemoteSessionStore()..slots[oldSlot] = oldSession;
      final revoker = _RecordingRemoteRevoker(
        error: const DataApiTimeoutException(Duration(seconds: 5)),
      );
      final canceler = _RecordingAuthOperationCanceler(
        error: const DataApiTimeoutException(Duration(seconds: 5)),
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: _FailingConfigurationRepository(current),
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: newSession),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        remoteSessionRevoker: revoker,
        authOperationCanceler: canceler,
      );

      await expectLater(
        guarded.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: newSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: 'encryption-key-material',
          ),
        ),
        throwsA(isA<DataApiRemoteConfigurationRecoveryException>()),
      );

      expect(store.slots[oldSlot], same(oldSession));
      expect(store.slots.values, contains(same(newSession)));
      expect(revoker.revoked, <DataApiRemoteSession>[newSession]);
      expect(canceler.canceled, hasLength(1));
    },
  );

  test(
    'reconnect replaces an expired session without changing the URL',
    () async {
      final baseUri = Uri.parse('https://sync.example.com/');
      final renewed = _remoteSession(baseUri: baseUri);
      final store = _MemoryRemoteSessionStore();
      await repository.save(DataApiConfiguration.remote(baseUri.toString()));
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: renewed),
        remoteConnectionValidator: _RecordingRemoteValidator(),
      );

      await guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: baseUri,
          username: 'alice',
          password: 'new-password',
          encryptionKey: 'encryption-key-material',
        ),
      );

      expect(await _activeSession(repository, store), same(renewed));
      expect(
        await repository.load(),
        DataApiConfiguration.remote(baseUri.toString()),
      );
    },
  );

  test(
    'post-commit journal crash recovers active slot without revoking it',
    () async {
      const oldSlot = 'oldCredentialSlot0001';
      final oldSession = _remoteSession(
        baseUri: Uri.parse('https://old.example.com/'),
      );
      final newSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
        accessToken: 'new-access-token',
        encryptionKey: 'new-encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await repository.save(_persistedRemote(oldSession.baseUri, oldSlot));
      final store = _MemoryRemoteSessionStore()..slots[oldSlot] = oldSession;
      var failedCommittedWrite = false;
      Future<void> crashWriter(File file, String contents) async {
        final document = jsonDecode(contents) as Map<String, Object?>;
        final transition = document['transition'];
        if (!failedCommittedWrite &&
            transition is Map &&
            transition['phase'] == 'committed') {
          failedCommittedWrite = true;
          throw StateError('injected committed journal crash');
        }
        await file.parent.create(recursive: true);
        await file.writeAsString(contents, flush: true);
      }

      final crashing = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: newSession),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        remoteSessionRevoker: _RecordingRemoteRevoker(),
        sagaJournalWriter: crashWriter,
      );
      await expectLater(
        crashing.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: newSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: newSession.encryptionKey,
          ),
        ),
        throwsA(isA<DataApiConfigurationSagaRecoveryRequiredException>()),
      );
      final committed = await repository.load();
      final newSlot = committed.remoteCredentialRef!;
      expect(store.slots[newSlot], same(newSession));

      final revoker = _RecordingRemoteRevoker();
      final recovered = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteConnectionValidator: _RecordingRemoteValidator(),
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        remoteSessionRevoker: revoker,
      );
      await recovered.recoverForStartup();
      expect(await _activeSession(repository, store), same(newSession));
      await recovered.retryPendingRevocations();

      expect(revoker.revoked, <DataApiRemoteSession>[oldSession]);
      expect(store.slots[newSlot], same(newSession));
    },
  );

  test(
    'full-session hash tamper rolls back through a durable transition',
    () async {
      const oldSlot = 'oldCredentialSlot0001';
      final oldSession = _remoteSession(
        baseUri: Uri.parse('https://old.example.com/'),
      );
      final newSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
        accessToken: 'new-access-token',
        encryptionKey: 'new-encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await repository.save(_persistedRemote(oldSession.baseUri, oldSlot));
      final store = _MemoryRemoteSessionStore()..slots[oldSlot] = oldSession;
      var failedCommittedWrite = false;
      final crashing = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: newSession),
        remoteConnectionValidator: _RecordingRemoteValidator(),
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        remoteSessionRevoker: _RecordingRemoteRevoker(),
        sagaJournalWriter: (file, contents) async {
          final document = jsonDecode(contents) as Map<String, Object?>;
          final transition = document['transition'];
          if (!failedCommittedWrite &&
              transition is Map &&
              transition['phase'] == 'committed') {
            failedCommittedWrite = true;
            throw StateError('injected committed journal crash');
          }
          await file.parent.create(recursive: true);
          await file.writeAsString(contents, flush: true);
        },
      );
      await expectLater(
        crashing.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: newSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: newSession.encryptionKey,
          ),
        ),
        throwsA(isA<DataApiConfigurationSagaRecoveryRequiredException>()),
      );
      final committed = await repository.load();
      final newSlot = committed.remoteCredentialRef!;
      store.slots[newSlot] = DataApiRemoteSession(
        baseUri: newSession.baseUri,
        accessToken: newSession.accessToken,
        encryptionKey: 'tampered-encryption-key',
        expiresAt: newSession.expiresAt,
      );

      final recovered = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteConnectionValidator: _RecordingRemoteValidator(),
        authOperationCanceler: _RecordingAuthOperationCanceler(),
        remoteSessionRevoker: _RecordingRemoteRevoker(),
      );
      await recovered.recoverForStartup();

      final restored = await repository.load();
      expect(restored.remoteBaseUri, oldSession.baseUri);
      expect(restored.remoteCredentialRef, oldSlot);
      expect(restored.generation, committed.generation + 1);
      expect(await _activeSession(repository, store), same(oldSession));
    },
  );

  test('non-current saga journal is typed fail-closed and preserved', () async {
    final journal = File(
      '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
      'configuration-saga.json',
    );
    await journal.parent.create(recursive: true);
    const corrupt = '{"version":999,"revocation_queue":[]}\n';
    await journal.writeAsString(corrupt);
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: _MemoryRemoteSessionStore(),
    );

    await expectLater(
      guarded.recoverForStartup(),
      throwsA(isA<DataApiConfigurationSagaUnsupportedVersionException>()),
    );

    expect(guarded.recoveryRequired, isTrue);
    expect(await journal.readAsString(), corrupt);
  });

  test(
    'nested duplicate saga key blocks explicit Disabled with zero mutation',
    () async {
      const activeSlot = 'duplicateCredential01';
      final active = _remoteSession(
        baseUri: Uri.parse('https://active.example.com/'),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      const contents =
          '{"version":1,"transition":null,"revocation_queue":[],'
          '"delete_only_revocations":[],"auth_cancellation_queue":['
          '{"base_url":"https://active.example.com/",'
          '"base_url":"https://other.example.com/",'
          '"operation_id":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}]}\n';
      await journal.writeAsString(contents, flush: true);
      final modified = (await journal.stat()).modified;
      final revoker = _RecordingRemoteRevoker();
      final canceler = _RecordingAuthOperationCanceler();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
        authOperationCanceler: canceler,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiJsonDuplicateKeyException>()),
      );

      expect((await repository.load()).deployment, DataApiDeployment.remote);
      expect(store.slots[activeSlot], same(active));
      expect(revoker.revoked, isEmpty);
      expect(canceler.canceled, isEmpty);
      expect(await journal.readAsString(), contents);
      expect((await journal.stat()).modified, modified);
      expect(
        await File(
          '${journal.parent.path}${Platform.pathSeparator}'
          'configuration-saga-disable-reset.json',
        ).exists(),
        isFalse,
      );
    },
  );

  for (final evidence in <({String name, String contents})>[
    (
      name: 'non-current',
      contents:
          '{"version":0,"transition":null,"revocation_queue":['
          '"stagedCredential0001"],"delete_only_revocations":[],'
          '"auth_cancellation_queue":[]}\n',
    ),
    (
      name: 'missing-version',
      contents:
          '{"transition":null,"revocation_queue":['
          '"stagedCredential0001"],"delete_only_revocations":[],'
          '"auth_cancellation_queue":[]}\n',
    ),
  ]) {
    test(
      '${evidence.name} saga cannot be salvaged by explicit Disabled',
      () async {
        const activeSlot = 'activeCredential0001';
        const stagedSlot = 'stagedCredential0001';
        final active = _remoteSession(
          baseUri: Uri.parse('https://active.example.com/'),
        );
        final staged = _remoteSession(
          baseUri: Uri.parse('https://staged.example.com/'),
        );
        await repository.save(_persistedRemote(active.baseUri, activeSlot));
        final store = _MemoryRemoteSessionStore()
          ..slots[activeSlot] = active
          ..slots[stagedSlot] = staged;
        final journal = File(
          '${repository.configurationFile.parent.path}'
          '${Platform.pathSeparator}configuration-saga.json',
        );
        await journal.writeAsString(evidence.contents, flush: true);
        final modified = (await journal.stat()).modified;
        final revoker = _RecordingRemoteRevoker();
        final canceler = _RecordingAuthOperationCanceler();
        final guarded = AuthenticatedDataApiConfigurationRepository(
          delegate: repository,
          remoteSessionStore: store,
          remoteSessionRevoker: revoker,
          authOperationCanceler: canceler,
        );

        await expectLater(
          guarded.save(const DataApiConfiguration.disabled()),
          throwsA(isA<DataApiConfigurationSagaUnsupportedVersionException>()),
        );

        expect((await repository.load()).deployment, DataApiDeployment.remote);
        expect(store.slots, <String, DataApiRemoteSession>{
          activeSlot: active,
          stagedSlot: staged,
        });
        expect(revoker.revoked, isEmpty);
        expect(canceler.canceled, isEmpty);
        expect(await journal.readAsString(), evidence.contents);
        expect((await journal.stat()).modified, modified);
      },
    );
  }

  test(
    'non-current configuration nested in current saga cannot be salvaged',
    () async {
      const transaction = 'embeddedTransaction01';
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.parent.create(recursive: true);
      final contents =
          '${jsonEncode(<String, Object?>{
            'version': 1,
            'transition': <String, Object?>{
              'transaction_id': transaction,
              'phase': 'prepared',
              'before': <String, Object?>{'version': 0, 'deployment': 'disabled', 'generation': 0},
              'before_digest': List<String>.filled(64, '0').join(),
              'target': <String, Object?>{'version': 1, 'deployment': 'disabled', 'generation': 1, 'last_transaction_id': transaction},
            },
            'revocation_queue': <String>[],
            'delete_only_revocations': <String>[],
            'auth_cancellation_queue': <Object?>[],
          })}\n';
      await journal.writeAsString(contents, flush: true);
      final modified = (await journal.stat()).modified;
      final store = _MemoryRemoteSessionStore();
      final revoker = _RecordingRemoteRevoker();
      final canceler = _RecordingAuthOperationCanceler();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
        authOperationCanceler: canceler,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiConfigurationUnsupportedVersionException>()),
      );

      expect(await journal.readAsString(), contents);
      expect((await journal.stat()).modified, modified);
      expect(revoker.revoked, isEmpty);
      expect(canceler.canceled, isEmpty);
      expect(store.slots, isEmpty);
    },
  );

  test(
    'explicit Disabled quarantines corrupt saga and cleans recognizable refs',
    () async {
      const activeSlot = 'activeCredential0001';
      const stagedSlot = 'stagedCredential0001';
      final active = _remoteSession(
        baseUri: Uri.parse('https://active.example.com/'),
      );
      final staged = _remoteSession(
        baseUri: Uri.parse('https://staged.example.com/'),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()
        ..slots[activeSlot] = active
        ..slots[stagedSlot] = staged;
      final operationId = List<String>.filled(43, 'C').join();
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.parent.create(recursive: true);
      await journal.writeAsString(
        '${jsonEncode(<String, Object?>{
          'version': 1,
          'invalid_current_shape': true,
          'revocation_queue': <String>[stagedSlot],
          'auth_cancellation_queue': <Object?>[
            <String, Object?>{'base_url': 'https://active.example.com/', 'operation_id': operationId},
          ],
        })}\n',
      );
      final canceler = _RecordingAuthOperationCanceler();
      final revoker = _RecordingRemoteRevoker();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        authOperationCanceler: canceler,
        remoteSessionRevoker: revoker,
      );

      await guarded.save(const DataApiConfiguration.disabled());

      expect((await repository.load()).deployment, DataApiDeployment.disabled);
      expect(canceler.canceled.single.operationId, operationId);
      expect(
        revoker.revoked,
        containsAll(<DataApiRemoteSession>[active, staged]),
      );
      expect(store.slots, isEmpty);
      expect(
        journal.parent.listSync().any(
          (entry) => entry.path.contains('configuration-saga.json.corrupt.'),
        ),
        isTrue,
      );
      expect(
        (jsonDecode(await journal.readAsString())
            as Map<String, Object?>)['version'],
        1,
      );
    },
  );

  test('explicit Disabled quarantines malformed saga evidence', () async {
    const activeSlot = 'malformedCredential01';
    final active = _remoteSession(
      baseUri: Uri.parse('https://active.example.com/'),
    );
    await repository.save(_persistedRemote(active.baseUri, activeSlot));
    final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
    final journal = File(
      '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
      'configuration-saga.json',
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsString('{malformed-json');
    final revoker = _RecordingRemoteRevoker();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteSessionRevoker: revoker,
    );

    await expectLater(
      guarded.recoverForStartup(),
      throwsA(isA<DataApiConfigurationSagaRecoveryRequiredException>()),
    );
    expect(await journal.readAsString(), '{malformed-json');

    await guarded.save(const DataApiConfiguration.disabled());

    final disabled = await repository.load();
    expect(disabled.deployment, DataApiDeployment.disabled);
    expect(disabled.generation, 2);
    expect(disabled.remoteCredentialRef, isNull);
    expect(revoker.revoked, <DataApiRemoteSession>[active]);
    expect(store.slots, isEmpty);
    expect(
      journal.parent.listSync().any(
        (entry) => entry.path.contains('configuration-saga.json.corrupt.'),
      ),
      isTrue,
    );
  });

  test('Disabled recovery reset resumes after config write crash', () async {
    const activeSlot = 'activeCredential0001';
    final active = _remoteSession(
      baseUri: Uri.parse('https://active.example.com/'),
    );
    await repository.save(_persistedRemote(active.baseUri, activeSlot));
    final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
    final journal = File(
      '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
      'configuration-saga.json',
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsString('{"version":1}\n');
    final failing = _FailOnceConfigurationRepository(repository);
    final crashing = AuthenticatedDataApiConfigurationRepository(
      delegate: failing,
      sagaDirectory: repository.configurationFile.parent,
      remoteSessionStore: store,
    );

    await expectLater(
      crashing.save(const DataApiConfiguration.disabled()),
      throwsStateError,
    );
    expect((await repository.load()).deployment, DataApiDeployment.remote);
    final reset = File(
      '${journal.parent.path}${Platform.pathSeparator}'
      'configuration-saga-disable-reset.json',
    );
    expect(await reset.exists(), isTrue);

    final restarted = AuthenticatedDataApiConfigurationRepository(
      delegate: FileDataApiConfigurationRepository.forFile(
        repository.configurationFile,
      ),
      remoteSessionStore: store,
    );
    await restarted.recoverForStartup();

    expect((await repository.load()).deployment, DataApiDeployment.disabled);
    expect(await reset.exists(), isFalse);
  });

  test('Disabled recovery reset resumes after cleanup journal crash', () async {
    const activeSlot = 'activeCredential0001';
    final active = _remoteSession(
      baseUri: Uri.parse('https://active.example.com/'),
    );
    await repository.save(_persistedRemote(active.baseUri, activeSlot));
    final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
    final journal = File(
      '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
      'configuration-saga.json',
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsString('{"version":1}\n');
    final crashing = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      sagaJournalWriter: (file, contents) async {
        throw StateError('injected clean journal crash');
      },
    );

    await expectLater(
      crashing.save(const DataApiConfiguration.disabled()),
      throwsStateError,
    );
    expect((await repository.load()).deployment, DataApiDeployment.disabled);
    final reset = File(
      '${journal.parent.path}${Platform.pathSeparator}'
      'configuration-saga-disable-reset.json',
    );
    expect(await reset.exists(), isTrue);

    final restarted = AuthenticatedDataApiConfigurationRepository(
      delegate: FileDataApiConfigurationRepository.forFile(
        repository.configurationFile,
      ),
      remoteSessionStore: store,
    );
    await restarted.recoverForStartup();

    expect((await repository.load()).deployment, DataApiDeployment.disabled);
    expect(await reset.exists(), isFalse);
  });

  test(
    'Disabled recovery reset is idempotent when reset deletion crashes',
    () async {
      const activeSlot = 'activeCredential0001';
      final active = _remoteSession(
        baseUri: Uri.parse('https://active.example.com/'),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      await journal.parent.create(recursive: true);
      await journal.writeAsString('{"version":1}\n');
      final crashing = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        disableResetDelete: (file) async {
          throw StateError('injected reset deletion crash');
        },
      );

      await expectLater(
        crashing.save(const DataApiConfiguration.disabled()),
        throwsStateError,
      );
      final reset = File(
        '${journal.parent.path}${Platform.pathSeparator}'
        'configuration-saga-disable-reset.json',
      );
      expect(await reset.exists(), isTrue);

      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
      );
      await restarted.recoverForStartup();

      expect((await repository.load()).deployment, DataApiDeployment.disabled);
      expect(await reset.exists(), isFalse);
    },
  );

  test('startup queues orphan secure slots for bounded revocation', () async {
    const activeSlot = 'activeCredential0001';
    const orphanSlot = 'orphanCredential0001';
    final active = _remoteSession(
      baseUri: Uri.parse('https://active.example.com/'),
    );
    final orphan = _remoteSession(
      baseUri: Uri.parse('https://orphan.example.com/'),
    );
    await repository.save(_persistedRemote(active.baseUri, activeSlot));
    final store = _MemoryRemoteSessionStore()
      ..slots[activeSlot] = active
      ..slots[orphanSlot] = orphan;
    final revoker = _RecordingRemoteRevoker();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteSessionRevoker: revoker,
    );

    await guarded.recoverForStartup();
    expect(store.slots[orphanSlot], same(orphan));
    await guarded.retryPendingRevocations();

    expect(revoker.revoked, <DataApiRemoteSession>[orphan]);
    expect(store.slots, <String, DataApiRemoteSession>{activeSlot: active});
  });

  test('disabled startup never opens the remote credential vault', () async {
    final store = _MemoryRemoteSessionStore()
      ..listError = PlatformException(
        code: 'Unexpected security result code',
        message: 'Code: -50, invalid Keychain parameters',
        details: -50,
      );
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
    );

    await guarded.recoverForStartup();

    expect(store.listCount, 0);
    expect(await repository.load(), const DataApiConfiguration.disabled());
  });

  test('local API startup never opens the remote credential vault', () async {
    await repository.save(const DataApiConfiguration.local());
    final store = _MemoryRemoteSessionStore()
      ..listError = PlatformException(
        code: 'Unexpected security result code',
        message: 'Code: -50, invalid Keychain parameters',
        details: -50,
      );
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
    );

    await guarded.recoverForStartup();

    expect(store.listCount, 0);
    expect(await repository.load(), const DataApiConfiguration.local());
  });

  test(
    'saving disabled clears recovery without opening the credential vault',
    () async {
      final store = _MemoryRemoteSessionStore()
        ..listError = PlatformException(
          code: 'Unexpected security result code',
          message: 'Code: -50, invalid Keychain parameters',
          details: -50,
        );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
      );

      await guarded.save(const DataApiConfiguration.disabled());

      expect(store.listCount, 0);
      expect(await repository.load(), const DataApiConfiguration.disabled());
    },
  );

  test(
    'two repositories serialize configuration generations across instances',
    () async {
      final store = _MemoryRemoteSessionStore();
      final revoker = _RecordingRemoteRevoker();
      final firstSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://first.example.com/'),
        accessToken: 'first-access-token',
        encryptionKey: 'first-encryption-key',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final secondSession = DataApiRemoteSession(
        baseUri: Uri.parse('https://second.example.com/'),
        accessToken: 'second-access-token',
        encryptionKey: 'second-encryption-key',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      AuthenticatedDataApiConfigurationRepository build(
        DataApiRemoteSession session,
      ) {
        return AuthenticatedDataApiConfigurationRepository(
          delegate: FileDataApiConfigurationRepository.forFile(
            repository.configurationFile,
          ),
          remoteSessionStore: store,
          remoteAuthenticator: _RecordingRemoteAuthenticator(session: session),
          remoteConnectionValidator: _RecordingRemoteValidator(),
          remoteSessionRevoker: revoker,
        );
      }

      await Future.wait(<Future<void>>[
        build(firstSession).connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: firstSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: firstSession.encryptionKey,
          ),
        ),
        build(secondSession).connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: secondSession.baseUri,
            username: 'alice',
            password: 'password-1234',
            encryptionKey: secondSession.encryptionKey,
          ),
        ),
      ]);

      final finalConfiguration = await repository.load();
      expect(finalConfiguration.generation, 2);
      expect(store.slots, hasLength(1));
      expect(
        store.slots[finalConfiguration.remoteCredentialRef],
        anyOf(same(firstSession), same(secondSession)),
      );
      expect(revoker.revoked, hasLength(1));
    },
  );

  test('digest CAS rejects a same-generation external rewrite', () async {
    await repository.save(const DataApiConfiguration.disabled());
    final store = _MemoryRemoteSessionStore();
    final issued = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
    );
    final authenticator = _BlockingRemoteAuthenticator(issued);
    final canceler = _RecordingAuthOperationCanceler();
    final revoker = _RecordingRemoteRevoker();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteAuthenticator: authenticator,
      remoteConnectionValidator: _RecordingRemoteValidator(),
      authOperationCanceler: canceler,
      remoteSessionRevoker: revoker,
    );
    final connect = guarded.connectAndSaveRemote(
      DataApiRemoteLoginRequest(
        baseUri: issued.baseUri,
        username: 'alice',
        password: 'password-1234',
        encryptionKey: issued.encryptionKey,
      ),
    );
    await authenticator.started.future;
    final external = const DataApiConfiguration.disabled().withPersistenceState(
      generation: 0,
      remoteCredentialRef: null,
      lastTransactionId: 'externalTransaction01',
    );
    await repository.save(external);
    authenticator.release.complete();

    await expectLater(
      connect,
      throwsA(isA<DataApiConfigurationGenerationConflictException>()),
    );

    final persisted = await repository.load();
    expect(persisted.deployment, DataApiDeployment.disabled);
    expect(persisted.lastTransactionId, 'externalTransaction01');
    expect(store.slots, isEmpty);
    expect(canceler.canceled, hasLength(1));
    expect(revoker.revoked, <DataApiRemoteSession>[issued]);
  });

  test(
    'digest-mismatched journal stays locked until explicit Disabled escape',
    () async {
      const activeSlot = 'digestCredential0001';
      final active = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await repository.save(_persistedRemote(active.baseUri, activeSlot));
      final store = _MemoryRemoteSessionStore()..slots[activeSlot] = active;
      var crashed = false;
      final first = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        sagaJournalWriter: (file, contents) async {
          await file.parent.create(recursive: true);
          await file.writeAsString(contents, flush: true);
          final root = jsonDecode(contents) as Map<String, Object?>;
          final transition = root['transition'];
          if (!crashed &&
              transition is Map &&
              transition['phase'] == 'prepared') {
            crashed = true;
            throw StateError('injected prepared journal crash');
          }
        },
      );

      await expectLater(
        first.save(const DataApiConfiguration.local()),
        throwsStateError,
      );
      await repository.save(
        const DataApiConfiguration.local().withPersistenceState(
          generation: 1,
          remoteCredentialRef: null,
          lastTransactionId: 'externalTransaction02',
        ),
      );
      final revoker = _RecordingRemoteRevoker();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );

      await expectLater(
        restarted.recoverForStartup(),
        throwsA(isA<DataApiConfigurationSagaRecoveryRequiredException>()),
      );
      expect(store.slots[activeSlot], same(active));

      await restarted.save(const DataApiConfiguration.disabled());

      final disabled = await repository.load();
      expect(disabled.deployment, DataApiDeployment.disabled);
      expect(disabled.generation, 2);
      expect(revoker.revoked, <DataApiRemoteSession>[active]);
      expect(store.slots, isEmpty);
      expect(
        repository.configurationFile.parent.listSync().any(
          (entry) => entry.path.contains('configuration-saga.json.corrupt.'),
        ),
        isTrue,
      );
    },
  );

  test(
    'failed auth cleanup survives restart without persisting secrets',
    () async {
      await repository.save(const DataApiConfiguration.disabled());
      final issued = DataApiRemoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
        accessToken: 'issued-secret-access-token',
        encryptionKey: 'issued-secret-encryption-key',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final store = _MemoryRemoteSessionStore();
      final first = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: _RecordingRemoteAuthenticator(session: issued),
        remoteConnectionValidator: _RecordingRemoteValidator(
          error: const DataApiRequestException(
            statusCode: HttpStatus.unauthorized,
            code: 'invalid_encryption_key',
            message: 'wrong key',
          ),
        ),
        authOperationCanceler: _RecordingAuthOperationCanceler(
          error: const DataApiTimeoutException(Duration(seconds: 5)),
        ),
        remoteSessionRevoker: _RecordingRemoteRevoker(
          error: const DataApiTimeoutException(Duration(seconds: 5)),
        ),
      );
      await expectLater(
        first.connectAndSaveRemote(
          DataApiRemoteLoginRequest(
            baseUri: issued.baseUri,
            username: 'alice',
            password: 'password-never-persisted',
            encryptionKey: issued.encryptionKey,
          ),
        ),
        throwsA(isA<DataApiRemoteConfigurationRecoveryException>()),
      );
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      final contents = await journal.readAsString();
      expect(contents, contains('auth_cancellation_queue'));
      expect(contents, isNot(contains('password-never-persisted')));
      expect(contents, isNot(contains(issued.accessToken)));
      expect(contents, isNot(contains(issued.encryptionKey)));

      final canceler = _RecordingAuthOperationCanceler();
      final revoker = _RecordingRemoteRevoker();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        authOperationCanceler: canceler,
        remoteSessionRevoker: revoker,
      );
      await restarted.retryPendingRevocations();

      expect(canceler.canceled, hasLength(1));
      expect(revoker.revoked, <DataApiRemoteSession>[issued]);
      expect(store.slots, isEmpty);
      final recoveredJournal = jsonDecode(await journal.readAsString()) as Map;
      expect(recoveredJournal['auth_cancellation_queue'], isEmpty);
      expect(recoveredJournal['revocation_queue'], isEmpty);
    },
  );

  test(
    'corrupt active secure slot locks startup without deleting evidence',
    () async {
      const activeSlot = 'activeCredential0001';
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await repository.save(_persistedRemote(session.baseUri, activeSlot));
      const formatError = DataApiRemoteSessionFormatException(
        slotRef: activeSlot,
        cause: FormatException('injected corrupt secure JSON'),
      );
      final store = _MemoryRemoteSessionStore()
        ..slots[activeSlot] = session
        ..slotReadErrors[activeSlot] = formatError;
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
      );

      await expectLater(
        guarded.recoverForStartup(),
        throwsA(same(formatError)),
      );

      expect(guarded.recoveryRequired, isTrue);
      expect(store.slots[activeSlot], same(session));
    },
  );

  test(
    'explicit disabled escapes a corrupt active slot and retries revocation',
    () async {
      const activeSlot = 'activeCredential0002';
      final session = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await repository.save(_persistedRemote(session.baseUri, activeSlot));
      const formatError = DataApiRemoteSessionFormatException(
        slotRef: activeSlot,
        cause: FormatException('injected corrupt secure JSON'),
      );
      final store = _MemoryRemoteSessionStore()
        ..slots[activeSlot] = session
        ..slotReadErrors[activeSlot] = formatError;
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.slots[activeSlot], same(session));
      final journal = File(
        '${repository.configurationFile.parent.path}${Platform.pathSeparator}'
        'configuration-saga.json',
      );
      expect(await journal.readAsString(), contains(activeSlot));
      expect(
        repository.configurationFile.parent.listSync().any(
          (entry) => entry.path.contains('configuration-saga.json.corrupt'),
        ),
        isFalse,
      );

      store.slotReadErrors.remove(activeSlot);
      final revoker = _RecordingRemoteRevoker();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );
      await restarted.retryPendingRevocations();

      expect(revoker.revoked, <DataApiRemoteSession>[session]);
      expect(store.slots, isEmpty);
    },
  );

  test('saga directory journal and lock use owner-only permissions', () async {
    if (Platform.isWindows) {
      return;
    }
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: _MemoryRemoteSessionStore(),
      remoteAuthenticator: _RecordingRemoteAuthenticator(
        session: _remoteSession(
          baseUri: Uri.parse('https://sync.example.com/'),
        ),
      ),
      remoteConnectionValidator: _RecordingRemoteValidator(),
    );
    await guarded.connectAndSaveRemote(
      DataApiRemoteLoginRequest(
        baseUri: Uri.parse('https://sync.example.com/'),
        username: 'alice',
        password: 'password-1234',
        encryptionKey: 'encryption-key-material',
      ),
    );
    final sagaDirectory = repository.configurationFile.parent;
    final journal = File(
      '${sagaDirectory.path}${Platform.pathSeparator}'
      'configuration-saga.json',
    );
    final lock = File(
      '${sagaDirectory.path}${Platform.pathSeparator}'
      'configuration-saga.lock',
    );

    expect((await sagaDirectory.stat()).mode & 0x1ff, 0x1c0);
    expect((await journal.stat()).mode & 0x1ff, 0x180);
    expect((await lock.stat()).mode & 0x1ff, 0x180);
  });

  test(
    'secure slots preserve unsupported evidence and reject overwrite',
    () async {
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(
        () => FlutterSecureStoragePlatform.instance = previousPlatform,
      );
      const slot = 'credentialSlot000001';
      const key = 'ianvs.data-api.remote-session.slot.v1.$slot';
      values[key] = '{"version":0}';
      final store = FlutterSecureDataApiRemoteSessionStore();

      await expectLater(
        store.readSlot(slot),
        throwsA(isA<DataApiRemoteSessionUnsupportedVersionException>()),
      );
      expect(values[key], '{"version":0}');

      const duplicate =
          '{"version":1,"base_url":"https://sync.example.com/",'
          '"access_token":"first","access_token":"second",'
          '"encryption_key":"encryption-key-material",'
          '"expires_at":"2100-01-01T00:00:00.000Z"}';
      values[key] = duplicate;
      await expectLater(
        store.readSlot(slot),
        throwsA(isA<DataApiJsonDuplicateKeyException>()),
      );
      expect(values[key], duplicate);

      values.remove(key);
      final original = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      await store.writeSlot(slot, original);
      expect(await store.listSlotRefs(), <String>{slot});
      await expectLater(
        store.writeSlot(
          slot,
          _remoteSession(baseUri: Uri.parse('https://other.example.com/')),
        ),
        throwsA(isA<DataApiRemoteSessionSlotExistsException>()),
      );
      expect((await store.readSlot(slot))?.baseUri, original.baseUri);

      await store.deleteSlot(slot);
      expect(await store.listSlotRefs(), isEmpty);
      expect(values.containsKey(key), isFalse);
    },
  );

  test('secure slot listing uses its exact registry key', () async {
    final previousPlatform = FlutterSecureStoragePlatform.instance;
    final values = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      values,
    );
    addTearDown(() => FlutterSecureStoragePlatform.instance = previousPlatform);
    const slot = 'credentialSlot000002';
    final store = FlutterSecureDataApiRemoteSessionStore();

    await store.writeSlot(
      slot,
      _remoteSession(baseUri: Uri.parse('https://sync.example.com/')),
    );

    expect(
      values['ianvs.data-api.remote-session.slot-registry.v1'],
      '{"version":1,"slots":["$slot"]}',
    );
    expect(await store.listSlotRefs(), <String>{slot});
  });

  for (final failure in <Exception>[
    const DataApiRemoteSessionUnsupportedVersionException(version: 0),
    const DataApiJsonDuplicateKeyException(
      documentName: 'Remote Data API session',
      key: 'access_token',
    ),
  ]) {
    test(
      '${failure.runtimeType} blocks explicit Disabled without cleanup',
      () async {
        const slot = 'unsupportedSlot001';
        final session = _remoteSession(
          baseUri: Uri.parse('https://sync.example.com/'),
        );
        await repository.save(_persistedRemote(session.baseUri, slot));
        final store = _MemoryRemoteSessionStore()
          ..slots[slot] = session
          ..slotReadErrors[slot] = failure;
        final revoker = _RecordingRemoteRevoker();
        final guarded = AuthenticatedDataApiConfigurationRepository(
          delegate: repository,
          remoteSessionStore: store,
          remoteSessionRevoker: revoker,
        );

        await expectLater(
          guarded.save(const DataApiConfiguration.disabled()),
          throwsA(same(failure)),
        );

        expect((await repository.load()).deployment, DataApiDeployment.remote);
        expect(store.slots[slot], same(session));
        expect(revoker.revoked, isEmpty);
      },
    );
  }

  test('remote session rejects an oversized access token before storage', () {
    expect(
      () => DataApiRemoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
        accessToken: List<String>.filled(
          DataApiRemoteSession.maximumAccessTokenBytes + 1,
          'x',
        ).join(),
        encryptionKey: 'encryption-key-material',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
      throwsFormatException,
    );
  });

  test('remote login requires HTTPS except for loopback development', () {
    expect(
      () => DataApiRemoteLoginRequest(
        baseUri: Uri.parse('http://sync.example.com/'),
        username: 'alice',
        password: 'password-1234',
        encryptionKey: 'encryption-key-material',
      ),
      throwsFormatException,
    );
    expect(
      DataApiRemoteLoginRequest(
        baseUri: Uri.parse('http://127.0.0.1:8080/'),
        username: 'alice',
        password: 'password-1234',
        encryptionKey: 'encryption-key-material',
      ).baseUri,
      Uri.parse('http://127.0.0.1:8080/'),
    );
  });

  test('non-loopback HTTP secure session is rejected', () {
    expect(
      () => DataApiRemoteSession.fromJson(<String, Object?>{
        'version': DataApiRemoteSession.currentVersion,
        'base_url': 'http://sync.example.com/',
        'access_token': 'remote-access-token',
        'encryption_key': 'encryption-key-material',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      }),
      throwsFormatException,
    );
  });

  test('wrong-key validation revokes the newly issued token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    String? logoutAuthorization;
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/v1/auth/login/begin':
          request.response
            ..statusCode = HttpStatus.ok
            ..write(
              jsonEncode(<String, Object?>{
                'operation_id': List<String>.filled(43, 'A').join(),
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toUtc()
                    .toIso8601String(),
                'kind': 'login',
              }),
            );
        case '/v1/auth/login/complete':
          request.response
            ..statusCode = HttpStatus.ok
            ..write(
              jsonEncode(<String, Object?>{
                'token': 'new-access-token',
                'expires_at': DateTime.now()
                    .add(const Duration(hours: 1))
                    .toUtc()
                    .toIso8601String(),
              }),
            );
        case '/v1/me':
          request.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode(<String, Object?>{'username': 'alice'}));
        case '/v1/auth/verify-key':
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(
              jsonEncode(<String, Object?>{
                'error': <String, String>{
                  'code': 'invalid_encryption_key',
                  'message': 'wrong key',
                },
              }),
            );
        case '/v1/auth/cancel-operation':
          request.response.statusCode = HttpStatus.noContent;
        case '/v1/auth/logout':
          logoutAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    final baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
    final store = _MemoryRemoteSessionStore();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
    );

    await expectLater(
      guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: baseUri,
          username: 'alice',
          password: 'password-1234',
          encryptionKey: 'wrong-encryption-key',
        ),
      ),
      throwsA(
        isA<DataApiRequestException>().having(
          (error) => error.code,
          'code',
          'invalid_encryption_key',
        ),
      ),
    );

    expect(paths, <String>[
      '/v1/auth/login/begin',
      '/v1/auth/login/complete',
      '/v1/me',
      '/v1/auth/verify-key',
      '/v1/auth/cancel-operation',
      '/v1/auth/logout',
    ]);
    expect(logoutAuthorization, 'Bearer new-access-token');
    expect(store.slots, isEmpty);
  });

  test('validation and logout failures are preserved together', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/auth/login/begin') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(
            jsonEncode(<String, Object?>{
              'operation_id': List<String>.filled(43, 'A').join(),
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .toUtc()
                  .toIso8601String(),
              'kind': 'login',
            }),
          );
      } else if (request.uri.path == '/v1/auth/login/complete') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(
            jsonEncode(<String, Object?>{
              'token': 'new-access-token',
              'expires_at': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toUtc()
                  .toIso8601String(),
            }),
          );
      } else if (request.uri.path == '/v1/me') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode(<String, Object?>{'username': 'alice'}));
      } else if (request.uri.path == '/v1/auth/verify-key') {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(
            jsonEncode(<String, Object?>{
              'error': <String, String>{
                'code': 'invalid_encryption_key',
                'message': 'wrong key',
              },
            }),
          );
      } else if (request.uri.path == '/v1/auth/cancel-operation') {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write(
            jsonEncode(<String, Object?>{
              'error': <String, String>{
                'code': 'cancel_unavailable',
                'message': 'try later',
              },
            }),
          );
      } else {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write(
            jsonEncode(<String, Object?>{
              'error': <String, String>{
                'code': 'logout_unavailable',
                'message': 'try later',
              },
            }),
          );
      }
      await request.response.close();
    });

    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: _MemoryRemoteSessionStore(),
    );
    await expectLater(
      guarded.connectAndSaveRemote(
        DataApiRemoteLoginRequest(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          username: 'alice',
          password: 'password-1234',
          encryptionKey: 'wrong-encryption-key',
        ),
      ),
      throwsA(
        isA<DataApiRemoteConfigurationRecoveryException>()
            .having(
              (error) => error.configurationError,
              'configurationError',
              isA<DataApiRequestException>().having(
                (error) => error.code,
                'code',
                'invalid_encryption_key',
              ),
            )
            .having(
              (error) => error.recoveryError,
              'recoveryError',
              isA<DataApiRemoteCleanupErrors>().having(
                (errors) => errors.errors
                    .whereType<DataApiRequestException>()
                    .map((error) => error.code),
                'codes',
                containsAll(<String>[
                  'cancel_unavailable',
                  'logout_unavailable',
                ]),
              ),
            ),
      ),
    );
  });
}

DataApiRemoteSession _remoteSession({
  required Uri baseUri,
  DateTime? expiresAt,
  String encryptionKey = 'encryption-key-material',
}) {
  return DataApiRemoteSession(
    baseUri: baseUri,
    accessToken: 'access-token',
    encryptionKey: encryptionKey,
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
  );
}

final class _MemoryPortableMasterKeyStorage
    implements PortableMasterKeyStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
  }
}

DataApiConfiguration _persistedRemote(Uri baseUri, String credentialRef) {
  return DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
    generation: 1,
    remoteCredentialRef: credentialRef,
    lastTransactionId: 'oldTransactionId0001',
  );
}

Future<DataApiRemoteSession?> _activeSession(
  DataApiConfigurationRepository repository,
  DataApiRemoteSessionSlotStore store,
) async {
  final slotRef = (await repository.load()).remoteCredentialRef;
  return slotRef == null ? null : store.readSlot(slotRef);
}

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionSlotStore {
  Exception? listError;
  Error? readError;
  Error? clearError;
  Error? writeError;
  Error? afterSlotWriteError;
  final Set<int> failingWriteCalls = <int>{};
  int writeCount = 0;
  final Map<String, DataApiRemoteSession> slots =
      <String, DataApiRemoteSession>{};
  final Map<String, Exception> slotReadErrors = <String, Exception>{};
  final Map<String, Set<int>> failingSlotReadCalls = <String, Set<int>>{};
  final Map<String, int> slotReadCounts = <String, int>{};
  int listCount = 0;

  @override
  Future<Set<String>> listSlotRefs() async {
    listCount += 1;
    if (listError case final error?) {
      throw error;
    }
    return slots.keys.toSet();
  }

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async {
    final readCount = (slotReadCounts[slotRef] ?? 0) + 1;
    slotReadCounts[slotRef] = readCount;
    if (failingSlotReadCalls[slotRef]?.contains(readCount) ?? false) {
      throw Exception('injected slot read failure for $slotRef');
    }
    final slotError = slotReadErrors[slotRef];
    if (slotError != null) {
      throw slotError;
    }
    final error = readError;
    if (error != null) {
      throw error;
    }
    return slots[slotRef];
  }

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async {
    writeCount += 1;
    final error = writeError;
    if (error != null || failingWriteCalls.contains(writeCount)) {
      throw error ?? StateError('injected credential vault write failure');
    }
    if (slots.containsKey(slotRef)) {
      throw DataApiRemoteSessionSlotExistsException(slotRef);
    }
    slots[slotRef] = session;
    final postWriteError = afterSlotWriteError;
    if (postWriteError != null) {
      afterSlotWriteError = null;
      throw postWriteError;
    }
  }

  @override
  Future<void> deleteSlot(String slotRef) async {
    final error = clearError;
    if (error != null) {
      throw error;
    }
    slots.remove(slotRef);
  }
}

final class _FailingConfigurationRepository
    implements DataApiConfigurationRepository {
  _FailingConfigurationRepository(this.configuration);

  final DataApiConfiguration configuration;

  @override
  Future<DataApiConfiguration> load() async => configuration;

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    throw StateError('configuration write failed');
  }
}

final class _FailOnceConfigurationRepository
    implements DataApiConfigurationRepository {
  _FailOnceConfigurationRepository(this.delegate);

  final DataApiConfigurationRepository delegate;
  var _shouldFail = true;

  @override
  Future<DataApiConfiguration> load() => delegate.load();

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('injected configuration write crash');
    }
    await delegate.save(configuration);
  }
}

final class _RecordingRemoteValidator
    implements DataApiRemoteConnectionValidator {
  _RecordingRemoteValidator({this.error});

  final Exception? error;
  DataApiRemoteSession? validated;

  @override
  Future<void> validate(DataApiRemoteSession session) async {
    validated = session;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

final class _BlockingRemoteAuthenticator implements DataApiRemoteAuthenticator {
  _BlockingRemoteAuthenticator(this.session);

  final DataApiRemoteSession session;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<DataApiPreparedAuthOperation> begin(
    DataApiRemoteLoginRequest request,
  ) async => _preparedAuthOperation('B');

  @override
  Future<DataApiRemoteSession> complete(
    DataApiRemoteLoginRequest request,
    DataApiPreparedAuthOperation operation,
  ) async {
    started.complete();
    await release.future;
    return session;
  }
}

final class _RecordingRemoteAuthenticator
    implements DataApiRemoteAuthenticator {
  _RecordingRemoteAuthenticator({
    this.session,
    this.error,
    this.beginError,
    this.beforeComplete,
  });

  final DataApiRemoteSession? session;
  final Exception? error;
  final Exception? beginError;
  final Future<void> Function()? beforeComplete;
  DataApiRemoteLoginRequest? received;
  final DataApiPreparedAuthOperation operation = _preparedAuthOperation('A');
  int beginCalls = 0;
  int completeCalls = 0;

  @override
  Future<DataApiPreparedAuthOperation> begin(
    DataApiRemoteLoginRequest request,
  ) async {
    beginCalls += 1;
    received = request;
    final failure = beginError;
    if (failure != null) {
      throw failure;
    }
    return operation;
  }

  @override
  Future<DataApiRemoteSession> complete(
    DataApiRemoteLoginRequest request,
    DataApiPreparedAuthOperation operation,
  ) async {
    completeCalls += 1;
    await beforeComplete?.call();
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return session!;
  }
}

DataApiPreparedAuthOperation _preparedAuthOperation(String character) {
  return DataApiPreparedAuthOperation(
    operationId: List<String>.filled(43, character).join(),
    expiresAt: DateTime.utc(2100),
  );
}

final class _RecordingRemoteRevoker implements DataApiRemoteSessionRevoker {
  _RecordingRemoteRevoker({this.error});

  final Exception? error;
  final List<DataApiRemoteSession> revoked = <DataApiRemoteSession>[];

  @override
  Future<void> revoke(DataApiRemoteSession session) async {
    revoked.add(session);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

final class _RecordingMigrationClient implements DataApiMigrationClient {
  _RecordingMigrationClient({
    this.exportPages = const <DataApiMigrationExportPage>[],
    this.mergeReports = const <DataApiMigrationMergeReport>[],
    this.beforeMerge,
  });

  final List<DataApiMigrationExportPage> exportPages;
  final List<DataApiMigrationMergeReport> mergeReports;
  final Future<void> Function()? beforeMerge;
  int exportCalls = 0;
  int mergeCalls = 0;

  @override
  Future<DataApiMigrationExportPage> exportMigrationPage({
    String? cursor,
  }) async {
    return exportPages[exportCalls++];
  }

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async {
    await beforeMerge?.call();
    return mergeReports[mergeCalls++];
  }
}

final class _RecordingAuthOperationCanceler
    implements DataApiAuthOperationCanceler {
  _RecordingAuthOperationCanceler({this.error});

  final Exception? error;
  final List<({Uri baseUri, String operationId})> canceled =
      <({Uri baseUri, String operationId})>[];

  @override
  Future<void> cancel(Uri baseUri, String operationId) async {
    canceled.add((baseUri: baseUri, operationId: operationId));
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
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
    'expired or different-origin remote sessions cannot change mode',
    () async {
      await repository.save(const DataApiConfiguration.disabled());
      final expired = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final store = _MemoryRemoteSessionStore(expired);
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteConnectionValidator: _RecordingRemoteValidator(),
      );

      await expectLater(
        guarded.save(DataApiConfiguration.remote('https://sync.example.com/')),
        throwsA(isA<DataApiAuthenticationRequiredException>()),
      );
      store.session = _remoteSession(
        baseUri: Uri.parse('https://other.example.com/'),
      );
      await expectLater(
        guarded.save(DataApiConfiguration.remote('https://sync.example.com/')),
        throwsA(isA<DataApiAuthenticationRequiredException>()),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
    },
  );

  test('validated secure session permits remote configuration', () async {
    final session = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/api/'),
    );
    final validator = _RecordingRemoteValidator();
    final remote = DataApiConfiguration.remote('https://sync.example.com/api');
    await repository.save(remote);
    final store = _MemoryRemoteSessionStore(session);
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteConnectionValidator: validator,
    );

    await guarded.load();
    await guarded.save(remote);

    expect(validator.validated, same(session));
    expect(await repository.load(), remote);
    final plainConfiguration = await repository.configurationFile
        .readAsString();
    expect(plainConfiguration, isNot(contains('access-token')));
    expect(plainConfiguration, isNot(contains('encryption-key')));
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
      expect(await guarded.read(), same(session));
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
    await repository.save(const DataApiConfiguration.local());
    final previousSession = _remoteSession(
      baseUri: Uri.parse('https://previous.example.com/'),
    );
    final store = _MemoryRemoteSessionStore(previousSession);
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

    expect(await repository.load(), const DataApiConfiguration.local());
    expect(store.session, same(previousSession));
    expect(canceler.canceled, hasLength(1));
  });

  test('switching to disabled clears the previous remote session', () async {
    final previous = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
    );
    final store = _MemoryRemoteSessionStore(previous);
    final revoker = _RecordingRemoteRevoker();
    final guarded = AuthenticatedDataApiConfigurationRepository(
      delegate: repository,
      remoteSessionStore: store,
      remoteSessionRevoker: revoker,
    );

    await guarded.save(const DataApiConfiguration.disabled());

    expect(store.session, isNull);
    expect(await repository.load(), const DataApiConfiguration.disabled());
    expect(revoker.revoked, <DataApiRemoteSession>[previous]);
  });

  test(
    'revocation failure warns after disabled mode and local escape are saved',
    () async {
      final previous = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final store = _MemoryRemoteSessionStore(previous);
      final revoker = _RecordingRemoteRevoker(
        error: const DataApiTimeoutException(Duration(seconds: 5)),
      );
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.session, isNull);
      expect(revoker.revoked, <DataApiRemoteSession>[previous]);
    },
  );

  test(
    'vault read failure saves disabled but preserves unread legacy credential',
    () async {
      final previous = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final store = _MemoryRemoteSessionStore(previous)
        ..readError = StateError('credential vault read failed');
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.clearCount, 0);
      expect(store.session, same(previous));

      store.readError = null;
      final revoker = _RecordingRemoteRevoker();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );
      await restarted.retryPendingRevocations();

      expect(store.clearCount, 1);
      expect(store.session, isNull);
      expect(revoker.revoked, contains(previous));
    },
  );

  test(
    'vault read and clear failures report saved configuration accurately',
    () async {
      final store = _MemoryRemoteSessionStore()
        ..readError = StateError('credential vault read failed')
        ..clearError = StateError('credential vault clear failed');
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(isA<DataApiRemoteRevocationPendingWarning>()),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.clearCount, 0);
    },
  );

  test(
    'nonremote staged legacy cleanup journal decodes and recovers after crash',
    () async {
      final legacy = _remoteSession(
        baseUri: Uri.parse('https://legacy.example.com/'),
      );
      final store = _MemoryRemoteSessionStore(legacy);
      var crashed = false;
      final crashing = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        sagaJournalWriter: (file, contents) async {
          await file.parent.create(recursive: true);
          await file.writeAsString(contents, flush: true);
          final transition =
              (jsonDecode(contents) as Map<String, Object?>)['transition'];
          if (!crashed &&
              transition is Map &&
              transition['phase'] == 'staged') {
            crashed = true;
            throw StateError('injected staged nonremote crash');
          }
        },
      );

      await expectLater(
        crashing.save(const DataApiConfiguration.disabled()),
        throwsStateError,
      );

      final revoker = _RecordingRemoteRevoker();
      final restarted = AuthenticatedDataApiConfigurationRepository(
        delegate: FileDataApiConfigurationRepository.forFile(
          repository.configurationFile,
        ),
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );
      await restarted.recoverForStartup();
      await restarted.retryPendingRevocations();

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.session, isNull);
      expect(store.slots, isEmpty);
      expect(revoker.revoked, contains(legacy));
    },
  );

  test(
    'legacy migration crash matrix never revokes the token promoted active',
    () async {
      for (final crashPoint in <String>[
        'prepared',
        'slot-written',
        'staged',
        'committed',
      ]) {
        final caseDirectory = Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}$crashPoint',
        );
        final caseRepository = FileDataApiConfigurationRepository(
          appSupportDirectory: caseDirectory,
        );
        final session = _remoteSession(
          baseUri: Uri.parse('https://legacy-$crashPoint.example.com/'),
        );
        await caseRepository.save(
          DataApiConfiguration.remote(
            session.baseUri.toString(),
          ).withPersistenceState(
            generation: 1,
            remoteCredentialRef: null,
            lastTransactionId: 'legacyBefore0001',
          ),
        );
        final store = _MemoryRemoteSessionStore(session);
        if (crashPoint == 'slot-written') {
          store.afterSlotWriteError = StateError(
            'injected post-slot-write crash',
          );
        }
        var crashed = false;
        final crashing = AuthenticatedDataApiConfigurationRepository(
          delegate: caseRepository,
          remoteSessionStore: store,
          sagaJournalWriter: (file, contents) async {
            await file.parent.create(recursive: true);
            await file.writeAsString(contents, flush: true);
            final transition =
                (jsonDecode(contents) as Map<String, Object?>)['transition'];
            if (!crashed &&
                crashPoint != 'slot-written' &&
                transition is Map &&
                transition['phase'] == crashPoint) {
              crashed = true;
              throw StateError('injected $crashPoint legacy migration crash');
            }
          },
        );

        await expectLater(
          crashing.recoverForStartup(),
          throwsA(isA<Object>()),
          reason: crashPoint,
        );

        store.afterSlotWriteError = null;
        final revoker = _RecordingRemoteRevoker();
        final restarted = AuthenticatedDataApiConfigurationRepository(
          delegate: FileDataApiConfigurationRepository.forFile(
            caseRepository.configurationFile,
          ),
          remoteSessionStore: store,
          remoteSessionRevoker: revoker,
        );
        await restarted.recoverForStartup();
        await restarted.retryPendingRevocations();

        final recovered = await caseRepository.load();
        expect(recovered.remoteCredentialRef, isNotNull, reason: crashPoint);
        expect(
          store.slots[recovered.remoteCredentialRef],
          same(session),
          reason: crashPoint,
        );
        expect(await restarted.read(), same(session), reason: crashPoint);
        expect(store.session, isNull, reason: crashPoint);
        expect(store.slots, hasLength(1), reason: crashPoint);
        expect(revoker.revoked, isEmpty, reason: crashPoint);
      }
    },
  );

  test(
    'nonremote precommit crash matrix deletes a legacy duplicate locally',
    () async {
      for (final crashPoint in <String>['prepared', 'slot-written', 'staged']) {
        final caseDirectory = Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}'
          'nonremote-$crashPoint',
        );
        final caseRepository = FileDataApiConfigurationRepository(
          appSupportDirectory: caseDirectory,
        );
        const activeSlot = 'activeCredential0001';
        final active = _remoteSession(
          baseUri: Uri.parse('https://active-$crashPoint.example.com/'),
        );
        await caseRepository.save(_persistedRemote(active.baseUri, activeSlot));
        final store = _MemoryRemoteSessionStore(active)
          ..slots[activeSlot] = active;
        if (crashPoint == 'slot-written') {
          store.afterSlotWriteError = StateError(
            'injected post-slot-write crash',
          );
        }
        var crashed = false;
        final crashing = AuthenticatedDataApiConfigurationRepository(
          delegate: caseRepository,
          remoteSessionStore: store,
          sagaJournalWriter: (file, contents) async {
            await file.parent.create(recursive: true);
            await file.writeAsString(contents, flush: true);
            final transition =
                (jsonDecode(contents) as Map<String, Object?>)['transition'];
            if (!crashed &&
                crashPoint != 'slot-written' &&
                transition is Map &&
                transition['phase'] == crashPoint) {
              crashed = true;
              throw StateError('injected $crashPoint nonremote crash');
            }
          },
        );

        await expectLater(
          crashing.save(const DataApiConfiguration.disabled()),
          throwsA(isA<Object>()),
          reason: crashPoint,
        );

        store.afterSlotWriteError = null;
        final revoker = _RecordingRemoteRevoker();
        final restarted = AuthenticatedDataApiConfigurationRepository(
          delegate: FileDataApiConfigurationRepository.forFile(
            caseRepository.configurationFile,
          ),
          remoteSessionStore: store,
          remoteSessionRevoker: revoker,
        );
        await restarted.recoverForStartup();
        await restarted.retryPendingRevocations();

        final recovered = await caseRepository.load();
        expect(recovered.remoteCredentialRef, activeSlot, reason: crashPoint);
        expect(await restarted.read(), same(active), reason: crashPoint);
        expect(store.session, isNull, reason: crashPoint);
        expect(store.slots, <String, DataApiRemoteSession>{activeSlot: active});
        expect(revoker.revoked, isEmpty, reason: crashPoint);
      }
    },
  );

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
      expect(await crashing.read(), same(active));

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
      expect(await restarted.read(), same(active));
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
    'vault read failure happens before a new remote token is issued',
    () async {
      final newSession = _remoteSession(
        baseUri: Uri.parse('https://new.example.com/'),
      );
      final store = _MemoryRemoteSessionStore()
        ..readError = StateError('credential vault read failed');
      final authenticator = _RecordingRemoteAuthenticator(session: newSession);
      final revoker = _RecordingRemoteRevoker();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteAuthenticator: authenticator,
        remoteSessionRevoker: revoker,
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

      expect(authenticator.received, isNull);
      expect(revoker.revoked, isEmpty);
    },
  );

  test(
    'vault write failure restores old state and revokes new token',
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
      final store = _MemoryRemoteSessionStore(oldSession)
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

      expect(store.session, same(oldSession));
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
    'secure store clear failure is typed and never reported as success',
    () async {
      final previous = _remoteSession(
        baseUri: Uri.parse('https://sync.example.com/'),
      );
      final store = _MemoryRemoteSessionStore(previous)
        ..clearError = StateError('credential vault unavailable');
      final revoker = _RecordingRemoteRevoker();
      final guarded = AuthenticatedDataApiConfigurationRepository(
        delegate: repository,
        remoteSessionStore: store,
        remoteSessionRevoker: revoker,
      );

      await expectLater(
        guarded.save(const DataApiConfiguration.disabled()),
        throwsA(
          isA<DataApiRemoteRevocationPendingWarning>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('configuration was saved'), contains('not active')),
          ),
        ),
      );

      expect(await repository.load(), const DataApiConfiguration.disabled());
      expect(store.session, same(previous));
      expect(revoker.revoked, <DataApiRemoteSession>[previous]);
    },
  );

  test(
    'reconnect replaces an expired session without changing the URL',
    () async {
      final baseUri = Uri.parse('https://sync.example.com/');
      final expired = _remoteSession(
        baseUri: baseUri,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final renewed = _remoteSession(baseUri: baseUri);
      final store = _MemoryRemoteSessionStore(expired);
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

      expect(await guarded.read(), same(renewed));
      expect(store.session, isNull);
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
      expect(await recovered.read(), same(newSession));
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
      expect(await recovered.read(), same(oldSession));
    },
  );

  test('corrupt saga journal is fail-closed and preserved', () async {
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
      throwsA(isA<DataApiConfigurationSagaRecoveryRequiredException>()),
    );

    expect(guarded.recoveryRequired, isTrue);
    expect(await journal.readAsString(), corrupt);
  });

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
          'version': 999,
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
    await journal.writeAsString('{"version":999}\n');
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
    await journal.writeAsString('{"version":999}\n');
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
      await journal.writeAsString('{"version":999}\n');
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
    const orphanSlot = 'orphanCredential0001';
    final orphan = _remoteSession(
      baseUri: Uri.parse('https://orphan.example.com/'),
    );
    final store = _MemoryRemoteSessionStore()..slots[orphanSlot] = orphan;
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
    expect(store.slots, isEmpty);
  });

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
    await repository.save(const DataApiConfiguration.local());
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
      await repository.save(const DataApiConfiguration.local());
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

  test('secure slots preserve corrupt evidence and reject overwrite', () async {
    final previousPlatform = FlutterSecureStoragePlatform.instance;
    final values = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      values,
    );
    addTearDown(() => FlutterSecureStoragePlatform.instance = previousPlatform);
    const slot = 'credentialSlot000001';
    const key = 'ianvs.data-api.remote-session.slot.v1.$slot';
    values[key] = '{"version":999}';
    final store = FlutterSecureDataApiRemoteSessionStore();

    await expectLater(
      store.readSlot(slot),
      throwsA(isA<DataApiRemoteSessionFormatException>()),
    );
    expect(values[key], '{"version":999}');

    values.remove(key);
    final original = _remoteSession(
      baseUri: Uri.parse('https://sync.example.com/'),
    );
    await store.writeSlot(slot, original);
    await expectLater(
      store.writeSlot(
        slot,
        _remoteSession(baseUri: Uri.parse('https://other.example.com/')),
      ),
      throwsA(isA<DataApiRemoteSessionSlotExistsException>()),
    );
    expect((await store.readSlot(slot))?.baseUri, original.baseUri);
  });

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

  test('legacy non-loopback HTTP secure session is rejected', () {
    expect(
      () => DataApiRemoteSession.fromJson(<String, Object?>{
        'version': DataApiRemoteSession.currentVersion,
        'base_url': 'http://sync.example.com/',
        'access_token': 'legacy-access-token',
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
}) {
  return DataApiRemoteSession(
    baseUri: baseUri,
    accessToken: 'access-token',
    encryptionKey: 'encryption-key-material',
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
  );
}

DataApiConfiguration _persistedRemote(Uri baseUri, String credentialRef) {
  return DataApiConfiguration.remote(baseUri.toString()).withPersistenceState(
    generation: 1,
    remoteCredentialRef: credentialRef,
    lastTransactionId: 'oldTransactionId0001',
  );
}

final class _MemoryRemoteSessionStore
    implements DataApiRemoteSessionStore, DataApiRemoteSessionSlotStore {
  _MemoryRemoteSessionStore([this.session]);

  DataApiRemoteSession? session;
  Error? readError;
  Error? clearError;
  Error? writeError;
  Error? afterSlotWriteError;
  final Set<int> failingWriteCalls = <int>{};
  int writeCount = 0;
  int clearCount = 0;
  final Map<String, DataApiRemoteSession> slots =
      <String, DataApiRemoteSession>{};
  final Map<String, Exception> slotReadErrors = <String, Exception>{};
  final Map<String, Set<int>> failingSlotReadCalls = <String, Set<int>>{};
  final Map<String, int> slotReadCounts = <String, int>{};

  @override
  Future<Set<String>> listSlotRefs() async => slots.keys.toSet();

  @override
  Future<void> clear() async {
    clearCount += 1;
    final error = clearError;
    if (error != null) {
      throw error;
    }
    session = null;
  }

  @override
  Future<DataApiRemoteSession?> read() async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return session;
  }

  @override
  Future<void> write(DataApiRemoteSession session) async {
    writeCount += 1;
    final error = writeError;
    if (error != null || failingWriteCalls.contains(writeCount)) {
      throw error ?? StateError('injected credential vault write failure');
    }
    this.session = session;
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

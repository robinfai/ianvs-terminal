import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import '../data_api_json.dart';
import '../services/data_api_auth_contract.dart';
import '../services/data_api_client.dart';
import '../services/data_api_remote_session_store.dart';
import 'data_api_configuration.dart';

abstract interface class DataApiConfigurationRepository {
  Future<DataApiConfiguration> load();

  Future<void> save(DataApiConfiguration configuration);
}

typedef DataApiSagaJournalWriter =
    Future<void> Function(File file, String contents);
typedef DataApiDisableResetDelete = Future<void> Function(File file);

abstract interface class DataApiConfigurationRecoveryStatus {
  bool get recoveryRequired;
}

abstract interface class DataApiConfigurationRecoveryLoader {
  Future<DataApiConfiguration> loadForRecovery();
}

final class DataApiConfigurationRecoveryRequiredException implements Exception {
  const DataApiConfigurationRecoveryRequiredException();

  @override
  String toString() {
    return 'The data service configuration was corrupt and was quarantined. '
        'Persistence remains locked for this launch to prevent a silent switch '
        'to local data. Open data service settings to confirm Disabled (or '
        'choose another mode), then restart.';
  }
}

final class DataApiConfigurationRecoverySentinelException implements Exception {
  const DataApiConfigurationRecoverySentinelException({
    required this.cause,
    required this.configurationSaved,
  });

  final Object cause;
  final bool configurationSaved;

  @override
  String toString() {
    if (configurationSaved) {
      return 'The data service configuration was saved, but its recovery lock '
          'could not be cleared: $cause. Persistence remains locked until the '
          'recovery marker is removed by a later successful save.';
    }
    return 'The data service recovery lock could not be persisted: $cause. '
        'The prior configuration remains authoritative and startup stays '
        'locked.';
  }
}

abstract interface class DataApiRemoteConnectionValidator {
  Future<void> validate(DataApiRemoteSession session);
}

final class DataApiRemoteLoginRequest {
  factory DataApiRemoteLoginRequest({
    required Uri baseUri,
    required String username,
    required String password,
    required String encryptionKey,
  }) {
    final normalizedBaseUri = DataApiConfiguration.remote(
      baseUri.toString(),
    ).remoteBaseUri!;
    if (!isSecureDataApiRemoteOrigin(normalizedBaseUri)) {
      throw const FormatException(
        'Remote authentication requires HTTPS (HTTP is allowed only for a '
        'loopback development endpoint).',
      );
    }
    final normalizedUsername = normalizeDataApiUsername(username);
    final validatedPassword = validateDataApiPassword(password);
    final normalizedEncryptionKey = validateDataApiEncryptionKey(encryptionKey);
    return DataApiRemoteLoginRequest._(
      baseUri: normalizedBaseUri,
      username: normalizedUsername,
      password: validatedPassword,
      encryptionKey: normalizedEncryptionKey,
    );
  }

  const DataApiRemoteLoginRequest._({
    required this.baseUri,
    required this.username,
    required this.password,
    required this.encryptionKey,
  });

  final Uri baseUri;
  final String username;
  final String password;
  final String encryptionKey;
}

abstract interface class DataApiRemoteAuthenticator {
  Future<DataApiPreparedAuthOperation> begin(DataApiRemoteLoginRequest request);

  Future<DataApiRemoteSession> complete(
    DataApiRemoteLoginRequest request,
    DataApiPreparedAuthOperation operation,
  );
}

abstract interface class DataApiRemoteSessionRevoker {
  Future<void> revoke(DataApiRemoteSession session);
}

abstract interface class DataApiAuthOperationCanceler {
  Future<void> cancel(Uri baseUri, String operationId);
}

final class DataApiClientAuthOperationCanceler
    implements DataApiAuthOperationCanceler {
  const DataApiClientAuthOperationCanceler();

  @override
  Future<void> cancel(Uri baseUri, String operationId) {
    return DataApiClient(
      baseUri: baseUri,
      accessToken: null,
      encryptionKey: null,
      connectionTimeout: const Duration(seconds: 3),
      requestTimeout: const Duration(seconds: 5),
    ).cancelAuthOperation(operationId);
  }
}

final class DataApiClientRemoteSessionRevoker
    implements DataApiRemoteSessionRevoker {
  const DataApiClientRemoteSessionRevoker();

  @override
  Future<void> revoke(DataApiRemoteSession session) {
    return DataApiClient(
      baseUri: session.baseUri,
      accessToken: session.accessToken,
      encryptionKey: session.encryptionKey,
      connectionTimeout: const Duration(seconds: 3),
      requestTimeout: const Duration(seconds: 5),
    ).logout();
  }
}

final class DataApiRemoteRevocationPendingWarning implements Exception {
  const DataApiRemoteRevocationPendingWarning(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'The new data service configuration was saved, but remote '
        'authentication cleanup did not finish: $cause. Any cancellation '
        'capability or encrypted retired credential is covered by private '
        'persistent cleanup state and bounded retry; it is not active.';
  }
}

final class DataApiSecureSessionMutationException implements Exception {
  const DataApiSecureSessionMutationException({
    required this.operation,
    required this.cause,
    this.recoveryCause,
    this.configurationSaved = false,
  });

  final String operation;
  final Object cause;
  final Object? recoveryCause;
  final bool configurationSaved;

  @override
  String toString() {
    final recovery = recoveryCause == null
        ? ''
        : ' Additional secure-session recovery detail: $recoveryCause.';
    if (configurationSaved) {
      return 'The data service configuration was saved, but its prior secure '
          'session could not be $operation locally: $cause.$recovery Restarting '
          'will still use the newly selected mode and will not reconnect with '
          'the retained remote credential.';
    }
    return 'The data service configuration was not saved because the secure '
        'session could not be $operation: $cause.$recovery';
  }
}

final class DataApiRemoteConfigurationRecoveryException implements Exception {
  const DataApiRemoteConfigurationRecoveryException({
    required this.configurationError,
    required this.recoveryError,
  });

  final Object configurationError;
  final Object recoveryError;

  @override
  String toString() {
    return 'Remote configuration failed ($configurationError), and restoring '
        'or cleaning up its secure-session changes also failed '
        '($recoveryError). Remote persistence remains unavailable until '
        'settings are repaired.';
  }
}

final class DataApiRemoteCleanupErrors implements Exception {
  DataApiRemoteCleanupErrors(Iterable<Object> errors)
    : errors = List<Object>.unmodifiable(errors);

  final List<Object> errors;

  @override
  String toString() => errors.join('; ');
}

abstract interface class DataApiRemoteConfigurationConnector {
  Future<void> connectAndSaveRemote(DataApiRemoteLoginRequest request);
}

final class DataApiClientRemoteConnectionValidator
    implements DataApiRemoteConnectionValidator {
  const DataApiClientRemoteConnectionValidator();

  @override
  Future<void> validate(DataApiRemoteSession session) {
    return DataApiClient(
      baseUri: session.baseUri,
      accessToken: session.accessToken,
      encryptionKey: session.encryptionKey,
    ).validateSession();
  }
}

final class DataApiClientRemoteAuthenticator
    implements DataApiRemoteAuthenticator {
  const DataApiClientRemoteAuthenticator();

  @override
  Future<DataApiPreparedAuthOperation> begin(
    DataApiRemoteLoginRequest request,
  ) {
    return DataApiClient(
      baseUri: request.baseUri,
      accessToken: null,
      encryptionKey: null,
    ).beginLogin(username: request.username, password: request.password);
  }

  @override
  Future<DataApiRemoteSession> complete(
    DataApiRemoteLoginRequest request,
    DataApiPreparedAuthOperation operation,
  ) async {
    final login = await DataApiClient(
      baseUri: request.baseUri,
      accessToken: null,
      encryptionKey: null,
    ).completeLogin(operation.operationId);
    return DataApiRemoteSession(
      baseUri: request.baseUri,
      accessToken: login.accessToken,
      encryptionKey: request.encryptionKey,
      expiresAt: login.expiresAt,
    );
  }
}

/// Prevents an unauthenticated URL-only remote selection from replacing the
/// last working configuration.
///
/// The secure session must match the selected origin, be unexpired, and pass
/// `/v1/me`. Only then is the non-secret deployment configuration committed.
/// The settings flow already surfaces [save] failures and therefore leaves the
/// previous mode selected when authentication has not been provisioned.
final class AuthenticatedDataApiConfigurationRepository
    implements
        DataApiConfigurationRepository,
        DataApiRemoteConfigurationConnector,
        DataApiConfigurationRecoveryStatus,
        DataApiConfigurationRecoveryLoader {
  AuthenticatedDataApiConfigurationRepository({
    required DataApiConfigurationRepository delegate,
    required DataApiRemoteSessionSlotStore remoteSessionStore,
    Directory? sagaDirectory,
    DataApiRemoteConnectionValidator remoteConnectionValidator =
        const DataApiClientRemoteConnectionValidator(),
    DataApiRemoteAuthenticator remoteAuthenticator =
        const DataApiClientRemoteAuthenticator(),
    DataApiRemoteSessionRevoker remoteSessionRevoker =
        const DataApiClientRemoteSessionRevoker(),
    DataApiAuthOperationCanceler authOperationCanceler =
        const DataApiClientAuthOperationCanceler(),
    DataApiSagaJournalWriter? sagaJournalWriter,
    DataApiDisableResetDelete? disableResetDelete,
  }) : _delegate = delegate,
       _slotStore = remoteSessionStore,
       _sagaDirectory =
           sagaDirectory ??
           switch (delegate) {
             final FileDataApiConfigurationRepository fileRepository =>
               fileRepository.configurationFile.parent,
             _ => null,
           },
       _remoteConnectionValidator = remoteConnectionValidator,
       _remoteAuthenticator = remoteAuthenticator,
       _remoteSessionRevoker = remoteSessionRevoker,
       _authOperationCanceler = authOperationCanceler,
       _sagaJournalWriter = sagaJournalWriter,
       _disableResetDelete = disableResetDelete ?? _deleteFileIfPresent;

  static const int _sagaVersion = 1;
  static const int _maximumSagaBytes = 256 * 1024;
  static final Map<String, Future<void>> _processLockQueues =
      <String, Future<void>>{};

  final DataApiConfigurationRepository _delegate;
  final DataApiRemoteSessionSlotStore _slotStore;
  final Directory? _sagaDirectory;
  final DataApiRemoteConnectionValidator _remoteConnectionValidator;
  final DataApiRemoteAuthenticator _remoteAuthenticator;
  final DataApiRemoteSessionRevoker _remoteSessionRevoker;
  final DataApiAuthOperationCanceler _authOperationCanceler;
  final DataApiSagaJournalWriter? _sagaJournalWriter;
  final DataApiDisableResetDelete _disableResetDelete;
  _DataApiConfigurationSagaJournal _volatileJournal =
      const _DataApiConfigurationSagaJournal();
  bool _sagaRecoveryRequired = false;

  @override
  Future<DataApiConfiguration> load() {
    return _withSagaLock(() async {
      await _recoverLocked();
      return _delegate.load();
    });
  }

  Future<void> recoverForStartup() {
    return _withSagaLock(_recoverLocked);
  }

  @override
  Future<DataApiConfiguration> loadForRecovery() {
    return _withSagaLock(() async {
      await _recoverDisableResetLocked();
      final journal = await _readJournal();
      if (journal.transition != null) {
        await _recoverLocked(allowUnavailableRemote: true);
        return _delegate.load();
      }
      try {
        await _recoverLocked(allowUnavailableRemote: true);
      } on DataApiAuthenticationRequiredException {
        // Settings still needs the non-secret origin to offer reconnect.
      } on DataApiRemoteSessionFormatException {
        // Settings can still expose the non-secret origin for reconnect.
      } on DataApiConfigurationSagaRecoveryRequiredException {
        // With no transition and a readable journal this can only be a
        // dependency failure; the raw configuration remains inspectable.
      }
      return _delegate.load();
    });
  }

  Future<void> retryPendingRevocations() {
    return _withSagaLock(() async {
      await _recoverLocked(allowUnavailableRemote: true);
      final journal = await _readJournal();
      final errors = await _drainRemoteCleanupLocked(journal);
      if (errors.isNotEmpty) {
        throw DataApiRemoteRevocationPendingWarning(_cleanupError(errors)!);
      }
    });
  }

  @override
  bool get recoveryRequired =>
      _sagaRecoveryRequired ||
      switch (_delegate) {
        final DataApiConfigurationRecoveryStatus status =>
          status.recoveryRequired,
        _ => false,
      };

  @override
  Future<void> save(DataApiConfiguration configuration) {
    return _withSagaLock(() async {
      await _preflightCurrentOnlySlotSchemasLocked();
      if (configuration.remoteBaseUri == null) {
        try {
          await _recoverDisableResetLocked();
          final journal = await _readJournal();
          if (journal.transition != null) {
            await _recoverLocked(allowUnavailableRemote: true);
          }
          final current = await _delegate.load();
          await _commitNonRemoteLocked(current, configuration);
          return;
        } on Object catch (error, stackTrace) {
          if (configuration.deployment != DataApiDeployment.disabled ||
              !_isExplicitDisableRecoveryError(error)) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          await _forceDisableAfterSagaFailureLocked();
          return;
        }
      }
      await _recoverLocked(allowUnavailableRemote: true);
      final current = await _delegate.load();
      if (configuration.remoteBaseUri case final remoteBaseUri?) {
        if (current.remoteBaseUri != remoteBaseUri ||
            current.remoteCredentialRef == null) {
          throw const DataApiAuthenticationRequiredException();
        }
        final session = await _readActiveSessionLocked(current);
        if (session == null || !session.isUsableFor(remoteBaseUri)) {
          throw const DataApiAuthenticationRequiredException();
        }
        await _remoteConnectionValidator.validate(session);
        return;
      }
    });
  }

  @override
  Future<void> connectAndSaveRemote(DataApiRemoteLoginRequest request) {
    return _withSagaLock(() async {
      await _recoverLocked(allowUnavailableRemote: true);
      final current = await _delegate.load();
      final newSlot = _newSlotRef();
      final transactionId = _newSlotRef();
      var journal = await _readJournal();
      final target = DataApiConfiguration.remote(request.baseUri.toString())
          .withPersistenceState(
            generation: current.generation + 1,
            remoteCredentialRef: newSlot,
            lastTransactionId: transactionId,
          );
      var transition = _DataApiConfigurationTransition(
        transactionId: transactionId,
        phase: _DataApiConfigurationTransitionPhase.prepared,
        before: current,
        beforeDigest: await _configurationDigest(current),
        target: target,
        oldSlot: current.remoteCredentialRef,
        newSlot: newSlot,
      );
      journal = journal.withTransition(transition);
      await _writeJournal(journal);

      DataApiRemoteSession? issuedSession;
      var slotWritten = false;
      var configurationCommitted = false;
      try {
        final authOperation = await _remoteAuthenticator.begin(request);
        transition = transition.copyWith(
          phase: _DataApiConfigurationTransitionPhase.authPrepared,
          authOperationId: authOperation.operationId,
        );
        journal = journal.withTransition(transition);
        await _writeJournal(journal);
        issuedSession = await _remoteAuthenticator.complete(
          request,
          authOperation,
        );
        await _slotStore.writeSlot(newSlot, issuedSession);
        slotWritten = true;
        transition = transition.copyWith(
          phase: _DataApiConfigurationTransitionPhase.staged,
          sessionHash: await _sessionHash(issuedSession),
        );
        journal = journal.withTransition(transition);
        await _writeJournal(journal);
        if (!issuedSession.isUsableFor(request.baseUri)) {
          throw const DataApiAuthenticationRequiredException();
        }
        await _remoteConnectionValidator.validate(issuedSession);
        transition = transition.copyWith(
          phase: _DataApiConfigurationTransitionPhase.verified,
        );
        journal = journal.withTransition(transition);
        await _writeJournal(journal);
        await _commitConfigurationLocked(
          expectedGeneration: current.generation,
          expectedDigest: transition.beforeDigest,
          target: target,
        );
        configurationCommitted = true;
        transition = transition.copyWith(
          phase: _DataApiConfigurationTransitionPhase.committed,
        );
        journal = journal.withTransition(transition);
        await _writeJournal(journal);
        journal = journal.finishCommittedTransition(transition);
        await _writeJournal(journal);
      } on Object catch (error, stackTrace) {
        try {
          final observed = await _delegate.load();
          if (_samePersistedConfiguration(observed, target)) {
            configurationCommitted = true;
          } else if (observed.remoteCredentialRef == newSlot) {
            _sagaRecoveryRequired = true;
            Error.throwWithStackTrace(
              DataApiConfigurationSagaRecoveryRequiredException(
                'Remote transition failed and configuration no longer '
                'matches the target while still referencing its credential: '
                '$error',
              ),
              stackTrace,
            );
          }
        } on DataApiConfigurationSagaRecoveryRequiredException {
          rethrow;
        } on Object catch (observationError) {
          _sagaRecoveryRequired = true;
          Error.throwWithStackTrace(
            DataApiRemoteConfigurationRecoveryException(
              configurationError: error,
              recoveryError: observationError,
            ),
            stackTrace,
          );
        }
        if (configurationCommitted) {
          _sagaRecoveryRequired = true;
          if (error is DataApiConfigurationRecoverySentinelException &&
              error.configurationSaved) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          Error.throwWithStackTrace(
            DataApiConfigurationSagaRecoveryRequiredException(
              'Remote configuration committed, but durable cleanup did not '
              'finish: $error',
            ),
            stackTrace,
          );
        }
        final cleanupErrors = <Object>[];
        if (transition.authOperationId case final operationId?) {
          journal = journal.enqueueAuthCancellation(
            request.baseUri,
            operationId,
          );
        }
        if (slotWritten) {
          journal = journal.enqueueRevocation(newSlot).withTransition(null);
        } else {
          journal = journal.withTransition(null);
        }
        try {
          await _writeJournal(journal);
        } on Object catch (cleanupError) {
          cleanupErrors.add(cleanupError);
        }
        cleanupErrors.addAll(await _drainRemoteCleanupLocked(journal));
        if (cleanupErrors.isNotEmpty) {
          Error.throwWithStackTrace(
            DataApiRemoteConfigurationRecoveryException(
              configurationError: error,
              recoveryError: _cleanupError(cleanupErrors)!,
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      journal = await _readJournal();
      final cleanupErrors = await _drainRemoteCleanupLocked(journal);
      if (cleanupErrors.isNotEmpty) {
        throw DataApiRemoteRevocationPendingWarning(
          _cleanupError(cleanupErrors)!,
        );
      }
    });
  }

  Future<void> _commitNonRemoteLocked(
    DataApiConfiguration current,
    DataApiConfiguration selected,
  ) async {
    var journal = await _readJournal();
    final transactionId = _newSlotRef();
    final target = selected.withPersistenceState(
      generation: current.generation + 1,
      remoteCredentialRef: null,
      lastTransactionId: transactionId,
    );
    final transition = _DataApiConfigurationTransition(
      transactionId: transactionId,
      phase: _DataApiConfigurationTransitionPhase.prepared,
      before: current,
      beforeDigest: await _configurationDigest(current),
      target: target,
      oldSlot: current.remoteCredentialRef,
    );
    journal = journal.withTransition(transition);
    await _writeJournal(journal);
    await _commitConfigurationLocked(
      expectedGeneration: current.generation,
      expectedDigest: transition.beforeDigest,
      target: target,
    );
    final committed = transition.copyWith(
      phase: _DataApiConfigurationTransitionPhase.committed,
    );
    journal = journal.withTransition(committed);
    await _writeJournal(journal);
    journal = journal.finishCommittedTransition(committed);
    await _writeJournal(journal);
    final cleanupErrors = await _drainRemoteCleanupLocked(journal);
    if (cleanupErrors.isNotEmpty) {
      throw DataApiRemoteRevocationPendingWarning(
        _cleanupError(cleanupErrors)!,
      );
    }
  }

  Future<void> _recoverLocked({bool allowUnavailableRemote = false}) async {
    try {
      await _recoverDisableResetLocked();
      var journal = await _readJournal();
      var configuration = await _delegate.load();
      if (journal.transition case final transition?) {
        if (configuration.generation == transition.before.generation) {
          if (await _configurationDigest(configuration) !=
              transition.beforeDigest) {
            throw const DataApiConfigurationSagaRecoveryRequiredException(
              'The pre-transition configuration digest changed.',
            );
          }
          if (transition.newSlot != null) {
            journal = journal.enqueueRevocation(transition.newSlot!);
          }
          if (transition.authOperationId case final operationId?) {
            final baseUri = transition.target.remoteBaseUri;
            if (baseUri == null) {
              throw const DataApiConfigurationSagaRecoveryRequiredException(
                'Authentication operation has no remote origin.',
              );
            }
            journal = journal.enqueueAuthCancellation(baseUri, operationId);
          }
          journal = journal.withTransition(null);
          await _writeJournal(journal);
        } else if (configuration.generation == transition.target.generation) {
          if (!_samePersistedConfiguration(configuration, transition.target)) {
            throw const DataApiConfigurationSagaRecoveryRequiredException(
              'Committed configuration does not match the durable transition.',
            );
          }
          var targetSlotValid = true;
          if (configuration.remoteCredentialRef case final slot?) {
            try {
              final staged = await _slotStore.readSlot(slot);
              targetSlotValid =
                  staged != null &&
                  (transition.sessionHash == null ||
                      await _sessionHash(staged) == transition.sessionHash);
            } on DataApiRemoteSessionFormatException {
              targetSlotValid = false;
            }
          }
          if (targetSlotValid) {
            journal = journal.finishCommittedTransition(transition);
            await _writeJournal(journal);
          } else {
            if (transition.authOperationId case final operationId?) {
              journal = journal.enqueueAuthCancellation(
                transition.target.remoteBaseUri!,
                operationId,
              );
              await _writeJournal(journal);
            }
            final compensated = await _compensateMissingTargetSlotLocked(
              transition: transition,
              committed: configuration,
              journal: journal,
            );
            journal = compensated.journal;
            configuration = compensated.configuration;
          }
        } else {
          throw DataApiConfigurationGenerationConflictException(
            expected: transition.before.generation,
            actual: configuration.generation,
          );
        }
        configuration = await _delegate.load();
      }
      if (configuration.remoteBaseUri != null) {
        final session = await _readActiveSessionLocked(configuration);
        if (session == null ||
            !session.isUsableFor(configuration.remoteBaseUri!)) {
          if (!allowUnavailableRemote) {
            throw const DataApiAuthenticationRequiredException();
          }
        }
      }
      if (!allowUnavailableRemote) {
        await _reconcileOrphanSlotsLocked(configuration, await _readJournal());
      }
      _sagaRecoveryRequired = false;
    } on DataApiAuthenticationRequiredException {
      _sagaRecoveryRequired = true;
      rethrow;
    } on Object catch (error, stackTrace) {
      _sagaRecoveryRequired = true;
      if (error is DataApiConfigurationSagaRecoveryRequiredException ||
          error is DataApiConfigurationGenerationConflictException ||
          error is DataApiRemoteSessionFormatException ||
          error is DataApiConfigurationSagaUnsupportedVersionException ||
          error is DataApiConfigurationUnsupportedVersionException ||
          error is DataApiRemoteSessionUnsupportedVersionException ||
          error is DataApiJsonDuplicateKeyException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        DataApiConfigurationSagaRecoveryRequiredException(error.toString()),
        stackTrace,
      );
    }
  }

  Future<void> _reconcileOrphanSlotsLocked(
    DataApiConfiguration configuration,
    _DataApiConfigurationSagaJournal initialJournal,
  ) async {
    var journal = initialJournal;
    final protectedSlots = <String>{
      ?configuration.remoteCredentialRef,
      ...journal.revocationQueue,
      ?journal.transition?.oldSlot,
      ?journal.transition?.newSlot,
    };
    var changed = false;
    for (final slot in await _slotStore.listSlotRefs()) {
      if (!protectedSlots.contains(slot)) {
        journal = journal.enqueueRevocation(slot);
        changed = true;
      }
    }
    if (changed) {
      await _writeJournal(journal);
    }
  }

  Future<
    ({
      _DataApiConfigurationSagaJournal journal,
      DataApiConfiguration configuration,
    })
  >
  _compensateMissingTargetSlotLocked({
    required _DataApiConfigurationTransition transition,
    required DataApiConfiguration committed,
    required _DataApiConfigurationSagaJournal journal,
  }) async {
    final prior = transition.before;
    DataApiRemoteSession? priorSession;
    if (prior.remoteBaseUri != null) {
      final priorSlot = prior.remoteCredentialRef;
      if (priorSlot == null) {
        throw const DataApiConfigurationSagaRecoveryRequiredException(
          'The committed credential is unavailable and the prior remote '
          'configuration has no recoverable credential reference.',
        );
      }
      priorSession = await _slotStore.readSlot(priorSlot);
      if (priorSession == null) {
        throw const DataApiConfigurationSagaRecoveryRequiredException(
          'The committed and prior remote credential slots are unavailable.',
        );
      }
    }

    final compensationId = _newSlotRef();
    final restored = prior.withPersistenceState(
      generation: committed.generation + 1,
      remoteCredentialRef: prior.remoteCredentialRef,
      lastTransactionId: compensationId,
    );
    var compensation = _DataApiConfigurationTransition(
      transactionId: compensationId,
      phase: _DataApiConfigurationTransitionPhase.prepared,
      before: committed,
      beforeDigest: await _configurationDigest(committed),
      target: restored,
      oldSlot: committed.remoteCredentialRef,
      newSlot: prior.remoteCredentialRef,
      sessionHash: priorSession == null
          ? null
          : await _sessionHash(priorSession),
    );
    var nextJournal = journal.withTransition(compensation);
    await _writeJournal(nextJournal);
    if (priorSession != null) {
      compensation = compensation.copyWith(
        phase: _DataApiConfigurationTransitionPhase.verified,
      );
      nextJournal = nextJournal.withTransition(compensation);
      await _writeJournal(nextJournal);
    }
    await _commitConfigurationLocked(
      expectedGeneration: committed.generation,
      expectedDigest: compensation.beforeDigest,
      target: restored,
    );
    compensation = compensation.copyWith(
      phase: _DataApiConfigurationTransitionPhase.committed,
    );
    nextJournal = nextJournal.withTransition(compensation);
    await _writeJournal(nextJournal);
    nextJournal = nextJournal.finishCommittedTransition(compensation);
    await _writeJournal(nextJournal);
    return (journal: nextJournal, configuration: restored);
  }

  Future<DataApiRemoteSession?> _readActiveSessionLocked(
    DataApiConfiguration configuration,
  ) {
    final slot = configuration.remoteCredentialRef;
    if (slot == null) {
      return Future<DataApiRemoteSession?>.value();
    }
    return _slotStore.readSlot(slot);
  }

  Future<void> _preflightCurrentOnlySlotSchemasLocked() async {
    final refs = await _slotStore.listSlotRefs();
    for (final slot in refs) {
      try {
        await _slotStore.readSlot(slot);
      } on DataApiRemoteSessionUnsupportedVersionException {
        rethrow;
      } on DataApiJsonDuplicateKeyException {
        rethrow;
      } on Object {
        // Existing current-format recovery semantics handle malformed slots
        // and transient credential-vault failures later in the operation.
      }
    }
  }

  Future<void> _commitConfigurationLocked({
    required int expectedGeneration,
    required String expectedDigest,
    required DataApiConfiguration target,
  }) async {
    final latest = await _delegate.load();
    if (latest.generation != expectedGeneration ||
        await _configurationDigest(latest) != expectedDigest) {
      throw DataApiConfigurationGenerationConflictException(
        expected: expectedGeneration,
        actual: latest.generation,
      );
    }
    await _delegate.save(target);
  }

  Future<List<Object>> _drainRevocationsLocked(
    _DataApiConfigurationSagaJournal initialJournal,
  ) async {
    var journal = initialJournal;
    final errors = <Object>[];
    for (final slot in initialJournal.revocationQueue) {
      try {
        final current = await _delegate.load();
        final activeSlot = current.remoteCredentialRef;
        if (activeSlot == slot) {
          // A stale queue entry must never delete or revoke the credential the
          // current configuration names as authoritative.
          journal = journal.removeRevocation(slot);
          await _writeJournal(journal);
          continue;
        }
        DataApiRemoteSession? active;
        if (current.remoteBaseUri != null) {
          if (activeSlot == null) {
            errors.add(const DataApiAuthenticationRequiredException());
            continue;
          }
          active = await _slotStore.readSlot(activeSlot);
          if (active == null) {
            errors.add(const DataApiAuthenticationRequiredException());
            continue;
          }
        }
        final session = await _slotStore.readSlot(slot);
        if (session == null) {
          journal = journal.removeRevocation(slot);
          await _writeJournal(journal);
          continue;
        }
        if (active != null) {
          if (_sameRevocationCredential(session, active)) {
            // Persist the identity decision before touching the duplicate.
            // A crash after this write can only retry a local delete; it can
            // never turn into a logout of the still-active bearer token.
            journal = journal.markRevocationDeleteOnly(slot);
            await _writeJournal(journal);
            await _slotStore.deleteSlot(slot);
            journal = journal.removeRevocation(slot);
            await _writeJournal(journal);
            continue;
          }
        }
        if (journal.deleteOnlyRevocations.contains(slot)) {
          // The authoritative active credential changed (or was disabled)
          // after an earlier delete-only decision. Persist the renewed network
          // disposition before logout so a crash cannot reuse stale identity
          // evidence.
          journal = journal.markRevocationForNetwork(slot);
          await _writeJournal(journal);
        }
        if (session.expiresAt.isAfter(DateTime.now().toUtc())) {
          final revocationError = await _revoke(session);
          if (revocationError != null) {
            errors.add(revocationError);
            continue;
          }
        }
        await _slotStore.deleteSlot(slot);
        journal = journal.removeRevocation(slot);
        await _writeJournal(journal);
      } on Object catch (error) {
        errors.add(error);
      }
    }
    return errors;
  }

  Future<List<Object>> _drainRemoteCleanupLocked(
    _DataApiConfigurationSagaJournal journal,
  ) async {
    final errors = await _drainAuthCancellationsLocked(journal);
    final latest = await _readJournal();
    errors.addAll(await _drainRevocationsLocked(latest));
    return errors;
  }

  Future<List<Object>> _drainAuthCancellationsLocked(
    _DataApiConfigurationSagaJournal initialJournal,
  ) async {
    var journal = initialJournal;
    final errors = <Object>[];
    for (final cancellation in initialJournal.authCancellationQueue) {
      try {
        await _authOperationCanceler.cancel(
          cancellation.baseUri,
          cancellation.operationId,
        );
        journal = journal.removeAuthCancellation(cancellation.operationId);
        await _writeJournal(journal);
      } on Object catch (error) {
        errors.add(error);
      }
    }
    return errors;
  }

  Future<Object?> _revoke(DataApiRemoteSession session) async {
    if (!session.expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    try {
      await _remoteSessionRevoker.revoke(session);
      return null;
    } on DataApiRequestException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized ||
          error.statusCode == HttpStatus.notFound) {
        return null;
      }
      return error;
    } on Object catch (error) {
      return error;
    }
  }

  Future<T> _withSagaLock<T>(Future<T> Function() operation) {
    final directory = _sagaDirectory;
    if (directory == null) {
      return operation();
    }
    final lockPath =
        '${directory.path}${Platform.pathSeparator}'
        'configuration-saga.lock';
    final previous = _processLockQueues[lockPath] ?? Future<void>.value();
    late final Future<T> queued;
    queued = previous.catchError((Object _) {}).then((_) async {
      await directory.create(recursive: true);
      _setPrivatePosixMode(directory.path, 0x1c0);
      final lock = await File(lockPath).open(mode: FileMode.append);
      _setPrivatePosixMode(lockPath, 0x180);
      await lock.lock(FileLock.exclusive);
      try {
        return await operation();
      } finally {
        await lock.unlock();
        await lock.close();
      }
    });
    final completion = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    late final Future<void> trackedCompletion;
    trackedCompletion = completion.whenComplete(() {
      if (identical(_processLockQueues[lockPath], trackedCompletion)) {
        final removed = _processLockQueues.remove(lockPath);
        assert(
          identical(removed, trackedCompletion),
          'The configuration saga process lock changed before cleanup.',
        );
      }
    });
    _processLockQueues[lockPath] = trackedCompletion;
    return queued;
  }

  File? get _journalFile => switch (_sagaDirectory) {
    final directory? => File(
      '${directory.path}${Platform.pathSeparator}configuration-saga.json',
    ),
    _ => null,
  };

  File? get _disableResetFile => switch (_sagaDirectory) {
    final directory? => File(
      '${directory.path}${Platform.pathSeparator}'
      'configuration-saga-disable-reset.json',
    ),
    _ => null,
  };

  Future<void> _forceDisableAfterSagaFailureLocked() async {
    final current = await _delegate.load();
    final transactionId = _newSlotRef();
    final target = const DataApiConfiguration.disabled().withPersistenceState(
      generation: current.generation + 1,
      remoteCredentialRef: null,
      lastTransactionId: transactionId,
    );
    final cleanup = await _collectRecognizableCleanupLocked(current);
    final reset = _DataApiDisableRecoveryReset(
      before: current,
      beforeDigest: await _configurationDigest(current),
      target: target,
      cleanup: cleanup,
    );
    await _writeDisableReset(reset);
    await _recoverDisableResetLocked();

    final journal = await _readJournal();
    final errors = await _drainRemoteCleanupLocked(journal);
    if (errors.isNotEmpty) {
      throw DataApiRemoteRevocationPendingWarning(_cleanupError(errors)!);
    }
  }

  Future<_DataApiConfigurationSagaJournal> _collectRecognizableCleanupLocked(
    DataApiConfiguration current,
  ) async {
    var cleanup = const _DataApiConfigurationSagaJournal();
    try {
      final priorReset = await _readDisableReset();
      if (priorReset != null) {
        cleanup = _mergeRecognizableCleanup(cleanup, priorReset.cleanup);
      }
    } on DataApiConfigurationSagaUnsupportedVersionException {
      rethrow;
    } on DataApiConfigurationUnsupportedVersionException {
      rethrow;
    } on DataApiJsonDuplicateKeyException {
      rethrow;
    } on Object {
      // A malformed reset is never promoted into executable network cleanup.
      // The explicit Disabled selection will replace it atomically below.
    }
    try {
      cleanup = _mergeRecognizableCleanup(cleanup, await _readJournal());
    } on DataApiConfigurationSagaUnsupportedVersionException {
      rethrow;
    } on DataApiConfigurationUnsupportedVersionException {
      rethrow;
    } on DataApiJsonDuplicateKeyException {
      rethrow;
    } on Object {
      final file = _journalFile;
      if (file != null && await file.exists()) {
        try {
          final raw = decodeDataApiJsonObject(
            await _readUtf8FileBounded(file, _maximumSagaBytes),
            documentName: 'Data API configuration saga evidence',
          );
          if (raw['version'] != _sagaVersion) {
            throw DataApiConfigurationSagaUnsupportedVersionException(
              documentName: 'Data API configuration saga',
              version: raw['version'],
            );
          }
          cleanup = _mergeRawRecognizableCleanup(cleanup, raw);
        } on DataApiConfigurationSagaUnsupportedVersionException {
          rethrow;
        } on DataApiConfigurationUnsupportedVersionException {
          rethrow;
        } on DataApiJsonDuplicateKeyException {
          rethrow;
        } on Object {
          // Malformed evidence remains quarantined verbatim. Only identifiers
          // that pass strict parsing are allowed into executable cleanup.
        }
      }
    }
    if (current.remoteCredentialRef case final activeSlot?) {
      cleanup = cleanup.enqueueRevocation(activeSlot);
    }
    try {
      for (final slot in await _slotStore.listSlotRefs()) {
        cleanup = cleanup.enqueueRevocation(slot);
      }
    } on Object {
      // A corrupt Keychain listing must not block the explicit Disabled escape.
      // Known references remain queued and the original vault evidence stays.
    }
    return cleanup.withTransition(null);
  }

  _DataApiConfigurationSagaJournal _mergeRecognizableCleanup(
    _DataApiConfigurationSagaJournal destination,
    _DataApiConfigurationSagaJournal source,
  ) {
    var result = destination;
    for (final slot in source.revocationQueue) {
      result = result.enqueueRevocation(slot);
      if (source.deleteOnlyRevocations.contains(slot)) {
        result = result.markRevocationDeleteOnly(slot);
      }
    }
    for (final cancellation in source.authCancellationQueue) {
      result = result.enqueueAuthCancellation(
        cancellation.baseUri,
        cancellation.operationId,
      );
    }
    if (source.transition case final transition?) {
      for (final slot in <String?>[transition.oldSlot, transition.newSlot]) {
        if (slot != null) {
          result = result.enqueueRevocation(slot);
        }
      }
      if (transition.authOperationId case final operationId?) {
        final origin = transition.target.remoteBaseUri;
        if (origin != null) {
          result = result.enqueueAuthCancellation(origin, operationId);
        }
      }
    }
    return result;
  }

  _DataApiConfigurationSagaJournal _mergeRawRecognizableCleanup(
    _DataApiConfigurationSagaJournal destination,
    Map<String, Object?> raw,
  ) {
    var result = destination;
    void addSlot(Object? value) {
      if (_validCredentialRef(value)) {
        result = result.enqueueRevocation(value! as String);
      }
    }

    final queue = raw['revocation_queue'];
    if (queue is List) {
      for (final slot in queue) {
        addSlot(slot);
      }
    }
    final deleteOnly = raw['delete_only_revocations'];
    if (deleteOnly is List) {
      for (final slot in deleteOnly) {
        // A corrupt journal cannot be trusted to suppress server revocation.
        // Preserve the recognizable slot, but recompute its disposition from
        // the authoritative configuration and immutable credentials.
        addSlot(slot);
      }
    }
    final transition = raw['transition'];
    if (transition is Map) {
      addSlot(transition['old_slot']);
      addSlot(transition['new_slot']);
      final operationId = transition['auth_operation_id'];
      final target = transition['target'];
      final rawOrigin = target is Map ? target['remote_base_url'] : null;
      _tryAddRecognizableCancellation(
        add: (origin, operation) {
          result = result.enqueueAuthCancellation(origin, operation);
        },
        rawOrigin: rawOrigin,
        rawOperationId: operationId,
      );
    }
    final cancellations = raw['auth_cancellation_queue'];
    if (cancellations is List) {
      for (final entry in cancellations.whereType<Map<Object?, Object?>>()) {
        _tryAddRecognizableCancellation(
          add: (origin, operation) {
            result = result.enqueueAuthCancellation(origin, operation);
          },
          rawOrigin: entry['base_url'],
          rawOperationId: entry['operation_id'],
        );
      }
    }
    return result;
  }

  Future<void> _recoverDisableResetLocked() async {
    final reset = await _readDisableReset();
    if (reset == null) {
      return;
    }
    final observed = await _delegate.load();
    if (!_samePersistedConfiguration(observed, reset.target)) {
      if (!_samePersistedConfiguration(observed, reset.before) ||
          await _configurationDigest(observed) != reset.beforeDigest) {
        throw const DataApiConfigurationSagaRecoveryRequiredException(
          'Disabled recovery reset no longer matches configuration.',
        );
      }
    }
    final journal = _journalFile;
    if (journal != null && await journal.exists()) {
      final evidence = await quarantineCorruptFile(journal);
      _setPrivatePosixMode(evidence.path, 0x180);
    }
    if (!_samePersistedConfiguration(observed, reset.target)) {
      await _delegate.save(reset.target);
    }
    await _writeJournal(reset.cleanup);
    final file = _disableResetFile;
    if (file != null && await file.exists()) {
      await _disableResetDelete(file);
    }
  }

  Future<_DataApiDisableRecoveryReset?> _readDisableReset() async {
    final file = _disableResetFile;
    if (file == null || !await file.exists()) {
      return null;
    }
    try {
      return _DataApiDisableRecoveryReset.fromJson(
        decodeDataApiJsonObject(
          await _readUtf8FileBounded(file, _maximumSagaBytes),
          documentName: 'Data API Disabled recovery reset',
        ),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataApiConfigurationSagaRecoveryRequiredException(error.toString()),
        stackTrace,
      );
    }
  }

  Future<void> _writeDisableReset(_DataApiDisableRecoveryReset reset) async {
    final file = _disableResetFile;
    if (file == null) {
      throw const DataApiConfigurationSagaRecoveryRequiredException(
        'Disabled recovery requires durable saga storage.',
      );
    }
    await _writePrivateStringAtomically(
      file,
      '${jsonEncode(reset.toJson())}\n',
    );
  }

  Future<_DataApiConfigurationSagaJournal> _readJournal() async {
    final file = _journalFile;
    if (file == null) {
      return _volatileJournal;
    }
    if (!await file.exists()) {
      return const _DataApiConfigurationSagaJournal();
    }
    try {
      final stat = await file.stat();
      if (stat.size > _maximumSagaBytes) {
        throw const FormatException('Configuration saga journal is too large.');
      }
      return _DataApiConfigurationSagaJournal.fromJson(
        decodeDataApiJsonObject(
          await _readUtf8FileBounded(file, _maximumSagaBytes),
          documentName: 'Data API configuration saga',
        ),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataApiConfigurationSagaRecoveryRequiredException(error.toString()),
        stackTrace,
      );
    }
  }

  Future<void> _writeJournal(_DataApiConfigurationSagaJournal journal) async {
    final file = _journalFile;
    if (file == null) {
      _volatileJournal = journal;
      return;
    }
    final contents = '${jsonEncode(journal.toJson())}\n';
    final writer = _sagaJournalWriter;
    if (writer != null) {
      await writer(file, contents);
    } else {
      await _writePrivateStringAtomically(file, contents);
    }
  }

  String _newSlotRef() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> _sessionHash(DataApiRemoteSession session) async {
    final sink = Sha256().toSync().newHashSink();
    sink.add(utf8.encode(jsonEncode(session.toJson())));
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<String> _configurationDigest(
    DataApiConfiguration configuration,
  ) async {
    final sink = Sha256().toSync().newHashSink();
    sink.add(utf8.encode(jsonEncode(configuration.toJson())));
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

final class DataApiConfigurationGenerationConflictException
    implements Exception {
  const DataApiConfigurationGenerationConflictException({
    required this.expected,
    required this.actual,
  });

  final int expected;
  final int actual;

  @override
  String toString() {
    return 'Data API configuration generation conflict: expected $expected, '
        'found $actual. Persistence remains locked.';
  }
}

final class DataApiConfigurationSagaRecoveryRequiredException
    implements Exception {
  const DataApiConfigurationSagaRecoveryRequiredException(this.message);

  final String message;

  @override
  String toString() =>
      'Data API configuration transition requires recovery: $message';
}

final class DataApiConfigurationSagaUnsupportedVersionException
    implements Exception {
  const DataApiConfigurationSagaUnsupportedVersionException({
    required this.documentName,
    required this.version,
  });

  final String documentName;
  final Object? version;

  @override
  String toString() {
    return 'Unsupported $documentName version: $version. The original durable '
        'evidence was preserved.';
  }
}

final class _DataApiDisableRecoveryReset {
  const _DataApiDisableRecoveryReset({
    required this.before,
    required this.beforeDigest,
    required this.target,
    required this.cleanup,
  });

  factory _DataApiDisableRecoveryReset.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{
      'version',
      'before',
      'before_digest',
      'target',
      'cleanup',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Data API Disabled recovery reset contains an unsupported field.',
      );
    }
    if (json['version'] != 1) {
      throw DataApiConfigurationSagaUnsupportedVersionException(
        documentName: 'Data API Disabled recovery reset',
        version: json['version'],
      );
    }
    final before = json['before'];
    final target = json['target'];
    final beforeDigest = json['before_digest'];
    final cleanup = json['cleanup'];
    if (before is! Map ||
        target is! Map ||
        beforeDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(beforeDigest) ||
        cleanup is! Map) {
      throw const FormatException('Invalid Data API Disabled recovery reset.');
    }
    final beforeConfiguration = DataApiConfiguration.fromJson(
      before.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    final targetConfiguration = DataApiConfiguration.fromJson(
      target.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    if (targetConfiguration.deployment != DataApiDeployment.disabled ||
        targetConfiguration.generation != beforeConfiguration.generation + 1 ||
        targetConfiguration.remoteCredentialRef != null ||
        targetConfiguration.lastTransactionId == null) {
      throw const FormatException(
        'Invalid Data API Disabled recovery reset transition.',
      );
    }
    final cleanupJournal = _DataApiConfigurationSagaJournal.fromJson(
      cleanup.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    if (cleanupJournal.transition != null) {
      throw const FormatException(
        'Disabled recovery cleanup must not contain a transition.',
      );
    }
    return _DataApiDisableRecoveryReset(
      before: beforeConfiguration,
      beforeDigest: beforeDigest,
      target: targetConfiguration,
      cleanup: cleanupJournal,
    );
  }

  final DataApiConfiguration before;
  final String beforeDigest;
  final DataApiConfiguration target;
  final _DataApiConfigurationSagaJournal cleanup;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'before': before.toJson(),
    'before_digest': beforeDigest,
    'target': target.toJson(),
    'cleanup': cleanup.toJson(),
  };
}

enum _DataApiConfigurationTransitionPhase {
  prepared,
  authPrepared,
  staged,
  verified,
  committed,
}

final class _DataApiConfigurationTransition {
  const _DataApiConfigurationTransition({
    required this.transactionId,
    required this.phase,
    required this.before,
    required this.beforeDigest,
    required this.target,
    this.oldSlot,
    this.newSlot,
    this.sessionHash,
    this.authOperationId,
  });

  factory _DataApiConfigurationTransition.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{
      'transaction_id',
      'phase',
      'before',
      'before_digest',
      'target',
      'old_slot',
      'new_slot',
      'session_hash',
      'auth_operation_id',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Data API configuration saga transition contains an unsupported field.',
      );
    }
    final phaseName = json['phase'];
    final transactionId = json['transaction_id'];
    final before = json['before'];
    final beforeDigest = json['before_digest'];
    final target = json['target'];
    final oldSlot = json['old_slot'];
    final newSlot = json['new_slot'];
    final sessionHash = json['session_hash'];
    final authOperationId = json['auth_operation_id'];
    final phase = _DataApiConfigurationTransitionPhase.values
        .where((value) => value.name == phaseName)
        .firstOrNull;
    if (phase == null ||
        transactionId is! String ||
        !_validCredentialRef(transactionId) ||
        before is! Map ||
        beforeDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(beforeDigest) ||
        target is! Map ||
        (oldSlot != null && !_validCredentialRef(oldSlot)) ||
        (newSlot != null && !_validCredentialRef(newSlot)) ||
        (sessionHash != null &&
            (sessionHash is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(sessionHash))) ||
        (authOperationId != null &&
            (authOperationId is! String ||
                !_isValidAuthOperationId(authOperationId)))) {
      throw const FormatException(
        'Invalid Data API configuration saga transition.',
      );
    }
    final targetConfiguration = DataApiConfiguration.fromJson(
      target.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    final beforeConfiguration = DataApiConfiguration.fromJson(
      before.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
    if (targetConfiguration.generation != beforeConfiguration.generation + 1 ||
        targetConfiguration.remoteCredentialRef != newSlot ||
        targetConfiguration.lastTransactionId != transactionId ||
        beforeConfiguration.remoteCredentialRef != oldSlot) {
      throw const FormatException(
        'Data API configuration saga generations or credential refs differ.',
      );
    }
    return _DataApiConfigurationTransition(
      transactionId: transactionId,
      phase: phase,
      before: beforeConfiguration,
      beforeDigest: beforeDigest,
      target: targetConfiguration,
      oldSlot: oldSlot as String?,
      newSlot: newSlot as String?,
      sessionHash: sessionHash as String?,
      authOperationId: authOperationId as String?,
    );
  }

  final String transactionId;
  final _DataApiConfigurationTransitionPhase phase;
  final DataApiConfiguration before;
  final String beforeDigest;
  final DataApiConfiguration target;
  final String? oldSlot;
  final String? newSlot;
  final String? sessionHash;
  final String? authOperationId;

  _DataApiConfigurationTransition copyWith({
    _DataApiConfigurationTransitionPhase? phase,
    String? sessionHash,
    String? authOperationId,
  }) {
    return _DataApiConfigurationTransition(
      transactionId: transactionId,
      phase: phase ?? this.phase,
      before: before,
      beforeDigest: beforeDigest,
      target: target,
      oldSlot: oldSlot,
      newSlot: newSlot,
      sessionHash: sessionHash ?? this.sessionHash,
      authOperationId: authOperationId ?? this.authOperationId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'transaction_id': transactionId,
    'phase': phase.name,
    'before': before.toJson(),
    'before_digest': beforeDigest,
    'target': target.toJson(),
    if (oldSlot != null) 'old_slot': oldSlot,
    if (newSlot != null) 'new_slot': newSlot,
    if (sessionHash != null) 'session_hash': sessionHash,
    if (authOperationId != null) 'auth_operation_id': authOperationId,
  };
}

final class _DataApiAuthCancellation {
  const _DataApiAuthCancellation({
    required this.baseUri,
    required this.operationId,
  });

  factory _DataApiAuthCancellation.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{'base_url', 'operation_id'};
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Data API authentication cancellation contains an unsupported field.',
      );
    }
    final rawBaseUri = json['base_url'];
    final operationId = json['operation_id'];
    if (rawBaseUri is! String ||
        operationId is! String ||
        !_isValidAuthOperationId(operationId)) {
      throw const FormatException(
        'Invalid Data API authentication cancellation entry.',
      );
    }
    return _DataApiAuthCancellation(
      baseUri: DataApiConfiguration.remote(rawBaseUri).remoteBaseUri!,
      operationId: operationId,
    );
  }

  final Uri baseUri;
  final String operationId;

  Map<String, Object?> toJson() => <String, Object?>{
    'base_url': baseUri.toString(),
    'operation_id': operationId,
  };
}

final class _DataApiConfigurationSagaJournal {
  const _DataApiConfigurationSagaJournal({
    this.transition,
    this.revocationQueue = const <String>[],
    this.deleteOnlyRevocations = const <String>[],
    this.authCancellationQueue = const <_DataApiAuthCancellation>[],
  });

  factory _DataApiConfigurationSagaJournal.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{
      'version',
      'transition',
      'revocation_queue',
      'delete_only_revocations',
      'auth_cancellation_queue',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Data API configuration saga contains an unsupported field.',
      );
    }
    if (json['version'] !=
        AuthenticatedDataApiConfigurationRepository._sagaVersion) {
      throw DataApiConfigurationSagaUnsupportedVersionException(
        documentName: 'Data API configuration saga',
        version: json['version'],
      );
    }
    final rawTransition = json['transition'];
    final rawQueue = json['revocation_queue'];
    final rawDeleteOnly = json['delete_only_revocations'];
    final rawCancellations = json['auth_cancellation_queue'];
    if (rawTransition != null && rawTransition is! Map ||
        rawQueue is! List ||
        rawDeleteOnly is! List ||
        rawCancellations is! List) {
      throw const FormatException('Invalid Data API configuration saga.');
    }
    final queue = <String>[];
    for (final value in rawQueue) {
      if (!_validCredentialRef(value) || !queue.addIfAbsent(value as String)) {
        throw const FormatException(
          'Invalid or duplicate Data API revocation queue entry.',
        );
      }
      if (queue.length > 1024) {
        throw const FormatException('Data API revocation queue is too large.');
      }
    }
    final deleteOnly = <String>[];
    for (final value in rawDeleteOnly) {
      if (!_validCredentialRef(value) ||
          !queue.contains(value) ||
          !deleteOnly.addIfAbsent(value as String)) {
        throw const FormatException(
          'Invalid or duplicate Data API delete-only revocation entry.',
        );
      }
    }
    final cancellations = <_DataApiAuthCancellation>[];
    for (final value in rawCancellations) {
      if (value is! Map) {
        throw const FormatException(
          'Invalid Data API authentication cancellation entry.',
        );
      }
      final cancellation = _DataApiAuthCancellation.fromJson(
        value.map((key, entry) => MapEntry(key.toString(), entry as Object?)),
      );
      if (cancellations.any(
        (existing) => existing.operationId == cancellation.operationId,
      )) {
        throw const FormatException(
          'Duplicate Data API authentication cancellation entry.',
        );
      }
      cancellations.add(cancellation);
      if (cancellations.length > 1024) {
        throw const FormatException(
          'Data API authentication cancellation queue is too large.',
        );
      }
    }
    final transitionMap = rawTransition is Map
        ? rawTransition.cast<Object?, Object?>()
        : null;
    final decodedTransition = rawTransition == null
        ? null
        : _DataApiConfigurationTransition.fromJson(
            transitionMap!.map((key, value) => MapEntry(key.toString(), value)),
          );
    return _DataApiConfigurationSagaJournal(
      transition: decodedTransition,
      revocationQueue: List<String>.unmodifiable(queue),
      deleteOnlyRevocations: List<String>.unmodifiable(deleteOnly),
      authCancellationQueue: List<_DataApiAuthCancellation>.unmodifiable(
        cancellations,
      ),
    );
  }

  final _DataApiConfigurationTransition? transition;
  final List<String> revocationQueue;
  final List<String> deleteOnlyRevocations;
  final List<_DataApiAuthCancellation> authCancellationQueue;

  _DataApiConfigurationSagaJournal withTransition(
    _DataApiConfigurationTransition? next,
  ) {
    return _DataApiConfigurationSagaJournal(
      transition: next,
      revocationQueue: revocationQueue,
      deleteOnlyRevocations: deleteOnlyRevocations,
      authCancellationQueue: authCancellationQueue,
    );
  }

  _DataApiConfigurationSagaJournal enqueueRevocation(String slot) {
    if (revocationQueue.contains(slot)) {
      return this;
    }
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: List<String>.unmodifiable(<String>[
        ...revocationQueue,
        slot,
      ]),
      deleteOnlyRevocations: deleteOnlyRevocations,
      authCancellationQueue: authCancellationQueue,
    );
  }

  _DataApiConfigurationSagaJournal markRevocationDeleteOnly(String slot) {
    if (!revocationQueue.contains(slot)) {
      throw StateError('Delete-only revocation must already be queued.');
    }
    if (deleteOnlyRevocations.contains(slot)) {
      return this;
    }
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: revocationQueue,
      deleteOnlyRevocations: List<String>.unmodifiable(<String>[
        ...deleteOnlyRevocations,
        slot,
      ]),
      authCancellationQueue: authCancellationQueue,
    );
  }

  _DataApiConfigurationSagaJournal markRevocationForNetwork(String slot) {
    if (!deleteOnlyRevocations.contains(slot)) {
      return this;
    }
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: revocationQueue,
      deleteOnlyRevocations: List<String>.unmodifiable(
        deleteOnlyRevocations.where((value) => value != slot),
      ),
      authCancellationQueue: authCancellationQueue,
    );
  }

  _DataApiConfigurationSagaJournal removeRevocation(String slot) {
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: List<String>.unmodifiable(
        revocationQueue.where((value) => value != slot),
      ),
      deleteOnlyRevocations: List<String>.unmodifiable(
        deleteOnlyRevocations.where((value) => value != slot),
      ),
      authCancellationQueue: authCancellationQueue,
    );
  }

  _DataApiConfigurationSagaJournal enqueueAuthCancellation(
    Uri baseUri,
    String operationId,
  ) {
    if (authCancellationQueue.any(
      (entry) => entry.operationId == operationId,
    )) {
      return this;
    }
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: revocationQueue,
      deleteOnlyRevocations: deleteOnlyRevocations,
      authCancellationQueue: List<_DataApiAuthCancellation>.unmodifiable(
        <_DataApiAuthCancellation>[
          ...authCancellationQueue,
          _DataApiAuthCancellation(baseUri: baseUri, operationId: operationId),
        ],
      ),
    );
  }

  _DataApiConfigurationSagaJournal removeAuthCancellation(String operationId) {
    return _DataApiConfigurationSagaJournal(
      transition: transition,
      revocationQueue: revocationQueue,
      deleteOnlyRevocations: deleteOnlyRevocations,
      authCancellationQueue: List<_DataApiAuthCancellation>.unmodifiable(
        authCancellationQueue.where(
          (entry) => entry.operationId != operationId,
        ),
      ),
    );
  }

  _DataApiConfigurationSagaJournal finishCommittedTransition(
    _DataApiConfigurationTransition committed,
  ) {
    var next = withTransition(null);
    final oldSlot = committed.oldSlot;
    if (oldSlot != null && oldSlot != committed.newSlot) {
      next = next.enqueueRevocation(oldSlot);
    }
    if (committed.target.remoteBaseUri == null && committed.newSlot != null) {
      next = next.enqueueRevocation(committed.newSlot!);
    }
    return next;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': AuthenticatedDataApiConfigurationRepository._sagaVersion,
    if (transition != null) 'transition': transition!.toJson(),
    'revocation_queue': revocationQueue,
    'delete_only_revocations': deleteOnlyRevocations,
    'auth_cancellation_queue': authCancellationQueue
        .map((entry) => entry.toJson())
        .toList(growable: false),
  };
}

bool _validCredentialRef(Object? value) {
  return value is String && RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
}

bool _isValidAuthOperationId(Object? value) {
  return value is String && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);
}

bool _isExplicitDisableRecoveryError(Object error) {
  return error is DataApiConfigurationSagaRecoveryRequiredException ||
      error is DataApiConfigurationGenerationConflictException ||
      error is DataApiRemoteSessionFormatException;
}

void _tryAddRecognizableCancellation({
  required void Function(Uri origin, String operationId) add,
  required Object? rawOrigin,
  required Object? rawOperationId,
}) {
  if (rawOrigin is! String || !_isValidAuthOperationId(rawOperationId)) {
    return;
  }
  try {
    add(
      DataApiConfiguration.remote(rawOrigin).remoteBaseUri!,
      rawOperationId! as String,
    );
  } on FormatException {
    // The evidence remains quarantined, but an unsafe or malformed origin is
    // never promoted into an executable network cleanup request.
  }
}

bool _samePersistedConfiguration(
  DataApiConfiguration left,
  DataApiConfiguration right,
) {
  return left.deployment == right.deployment &&
      left.remoteBaseUri == right.remoteBaseUri &&
      left.generation == right.generation &&
      left.remoteCredentialRef == right.remoteCredentialRef &&
      left.lastTransactionId == right.lastTransactionId;
}

bool _sameRevocationCredential(
  DataApiRemoteSession left,
  DataApiRemoteSession right,
) {
  // Logout invalidates the bearer token, irrespective of which immutable
  // local slot contains it or whether its encryption-key/expiry metadata was
  // re-encoded. Origin plus bearer token is therefore the cleanup identity.
  return left.baseUri == right.baseUri && left.accessToken == right.accessToken;
}

extension on List<String> {
  bool addIfAbsent(String value) {
    if (contains(value)) {
      return false;
    }
    add(value);
    return true;
  }
}

Object? _cleanupError(List<Object> errors) {
  return switch (errors) {
    [] => null,
    [final single] => single,
    _ => DataApiRemoteCleanupErrors(errors),
  };
}

int Function(ffi.Pointer<Utf8> path, int mode)? _chmod;

void _setPrivatePosixMode(String path, int mode) {
  if (Platform.isWindows) {
    return;
  }
  final chmod = _chmod ??= ffi.DynamicLibrary.process()
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8> path, ffi.Uint32 mode),
        int Function(ffi.Pointer<Utf8> path, int mode)
      >('chmod');
  final nativePath = path.toNativeUtf8();
  try {
    if (chmod(nativePath, mode) != 0) {
      throw FileSystemException(
        'Could not restrict Data API saga permissions.',
        path,
      );
    }
  } finally {
    malloc.free(nativePath);
  }
}

Future<String> _readUtf8FileBounded(File file, int maximumBytes) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in file.openRead()) {
    length += chunk.length;
    if (length > maximumBytes) {
      throw FormatException(
        '${file.path} exceeds the $maximumBytes-byte limit.',
      );
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

Future<void> _writePrivateStringAtomically(File file, String contents) async {
  await file.parent.create(recursive: true);
  _setPrivatePosixMode(file.parent.path, 0x1c0);
  final nonce =
      '${pid}_${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32)}';
  final temporaryFile = File('${file.path}.tmp.$nonce');
  RandomAccessFile? writer;
  try {
    writer = await temporaryFile.open(mode: FileMode.write);
    _setPrivatePosixMode(temporaryFile.path, 0x180);
    await writer.writeFrom(utf8.encode(contents));
    await writer.flush();
    await writer.close();
    writer = null;
    await temporaryFile.rename(file.path);
  } finally {
    await writer?.close();
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
  }
}

Future<void> _deleteFileIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

typedef DataApiRecoverySentinelDelete = Future<void> Function(File file);

final class FileDataApiConfigurationRepository
    implements
        DataApiConfigurationRepository,
        DataApiConfigurationRecoveryStatus {
  FileDataApiConfigurationRepository({
    required Directory appSupportDirectory,
    DataApiRecoverySentinelDelete? deleteRecoverySentinel,
  }) : _deleteRecoverySentinel =
           deleteRecoverySentinel ?? _deleteRecoverySentinelFile,
       configurationFile = File(
         '${appSupportDirectory.path}${Platform.pathSeparator}'
         'data-api${Platform.pathSeparator}configuration.json',
       ),
       recoverySentinelFile = File(
         '${appSupportDirectory.path}${Platform.pathSeparator}'
         'data-api${Platform.pathSeparator}'
         'configuration-recovery-required.json',
       );

  FileDataApiConfigurationRepository.forFile(
    this.configurationFile, {
    DataApiRecoverySentinelDelete? deleteRecoverySentinel,
  }) : _deleteRecoverySentinel =
           deleteRecoverySentinel ?? _deleteRecoverySentinelFile,
       recoverySentinelFile = File(
         '${configurationFile.parent.path}${Platform.pathSeparator}'
         'configuration-recovery-required.json',
       );

  final File configurationFile;
  final File recoverySentinelFile;
  final DataApiRecoverySentinelDelete _deleteRecoverySentinel;
  static const int _maximumConfigurationBytes = 64 * 1024;
  var _recoveryRequired = false;
  var _recoveryExceptionDelivered = false;

  @override
  bool get recoveryRequired => _recoveryRequired;

  @override
  Future<DataApiConfiguration> load() async {
    if (await recoverySentinelFile.exists()) {
      _recoveryRequired = true;
      if (!_recoveryExceptionDelivered) {
        _recoveryExceptionDelivered = true;
        throw const DataApiConfigurationRecoveryRequiredException();
      }
    }
    if (!await configurationFile.exists()) {
      return const DataApiConfiguration.disabled();
    }
    try {
      final json = decodeDataApiJsonObject(
        await _readUtf8FileBounded(
          configurationFile,
          _maximumConfigurationBytes,
        ),
        documentName: 'Data API configuration',
      );
      final recoveryRequired = json.remove('recovery_required');
      if (recoveryRequired != null && recoveryRequired != true) {
        throw const FormatException(
          'Data API configuration recovery state is invalid.',
        );
      }
      final configuration = DataApiConfiguration.fromJson(json);
      if (recoveryRequired == true) {
        _recoveryRequired = true;
        if (!_recoveryExceptionDelivered) {
          _recoveryExceptionDelivered = true;
          throw const DataApiConfigurationRecoveryRequiredException();
        }
      }
      return configuration;
    } on FormatException {
      try {
        await _writeRecoverySentinel();
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          DataApiConfigurationRecoverySentinelException(
            cause: error,
            configurationSaved: false,
          ),
          stackTrace,
        );
      }
      await quarantineCorruptFile(configurationFile);
      const repaired = DataApiConfiguration.disabled();
      await _write(repaired, recoveryRequired: true);
      _recoveryRequired = true;
      _recoveryExceptionDelivered = true;
      throw const DataApiConfigurationRecoveryRequiredException();
    }
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    await _write(configuration, recoveryRequired: false);
    try {
      if (await recoverySentinelFile.exists()) {
        await _deleteRecoverySentinel(recoverySentinelFile);
      }
    } on Object catch (error, stackTrace) {
      _recoveryRequired = true;
      Error.throwWithStackTrace(
        DataApiConfigurationRecoverySentinelException(
          cause: error,
          configurationSaved: true,
        ),
        stackTrace,
      );
    }
    _recoveryRequired = false;
    _recoveryExceptionDelivered = false;
  }

  Future<void> _write(
    DataApiConfiguration configuration, {
    required bool recoveryRequired,
  }) {
    return writeStringAtomically(
      configurationFile,
      '${jsonEncode(<String, Object?>{...configuration.toJson(), if (recoveryRequired) 'recovery_required': true})}\n',
    );
  }

  Future<void> _writeRecoverySentinel() {
    return writeStringAtomically(
      recoverySentinelFile,
      '${jsonEncode(<String, Object?>{'version': 1, 'reason': 'configuration_corrupt'})}\n',
    );
  }
}

Future<void> _deleteRecoverySentinelFile(File file) => file.delete();

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../configuration/data_api_configuration.dart';
import '../configuration/data_api_configuration_repository.dart';
import 'data_api_client.dart';
import 'data_api_local_credentials.dart';
import 'data_api_remote_session_store.dart';
import 'data_api_runtime.dart';
import 'local_data_api_sidecar.dart';
import 'portable_master_key.dart';

typedef LocalDataApiRuntimeStarter =
    Future<DataApiRuntime> Function(Directory appSupportDirectory);

enum DataApiStartupDependency { configuration, remoteSession }

final class DataApiStartupDependencyException implements Exception {
  const DataApiStartupDependencyException({
    required this.dependency,
    required this.cause,
  });

  final DataApiStartupDependency dependency;
  final Object cause;

  @override
  String toString() {
    final label = switch (dependency) {
      DataApiStartupDependency.configuration => 'data service configuration',
      DataApiStartupDependency.remoteSession => 'remote secure session',
    };
    return 'The $label could not be read: $cause. Persistence remains locked '
        'to prevent a silent switch to local data. Open data service settings '
        'to explicitly save a mode, then restart.';
  }
}

Future<DataApiConfiguration> loadDataApiConfigurationForStartup(
  DataApiConfigurationRepository repository,
) async {
  try {
    return await repository.load();
  } on DataApiConfigurationRecoveryRequiredException {
    rethrow;
  } on DataApiStartupDependencyException {
    rethrow;
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      DataApiStartupDependencyException(
        dependency: DataApiStartupDependency.configuration,
        cause: error,
      ),
      stackTrace,
    );
  }
}

final class DataApiLocalInitializationTimeoutException
    extends TimeoutException {
  DataApiLocalInitializationTimeoutException({
    required this.stage,
    required Duration timeout,
  }) : super('Local data API $stage exceeded its deadline.', timeout);

  final String stage;
}

/// Initializes the bundled sidecar with per-I/O and whole-operation bounds.
///
/// The whole timeout is deliberately independent of the health-loop deadline:
/// a peer that accepts a connection but never sends headers or finishes its
/// response must not keep application startup from reaching the recovery UI.
abstract interface class DataApiLocalApiInitialization {
  Future<void> initialize({
    required Uri baseUri,
    required String localAccessToken,
    required String encryptionKey,
  });
}

final class DataApiLocalApiInitializer
    implements DataApiLocalApiInitialization {
  DataApiLocalApiInitializer({
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 2),
    this.healthTimeout = const Duration(seconds: 5),
    this.initializationTimeout = const Duration(seconds: 8),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;
  final Duration healthTimeout;
  final Duration initializationTimeout;

  @override
  Future<void> initialize({
    required Uri baseUri,
    required String localAccessToken,
    required String encryptionKey,
  }) async {
    final client = _httpClientFactory()..connectionTimeout = requestTimeout;
    try {
      await _initialize(
        client: client,
        baseUri: baseUri,
        localAccessToken: localAccessToken,
        encryptionKey: encryptionKey,
      ).timeout(
        initializationTimeout,
        onTimeout: () => throw DataApiLocalInitializationTimeoutException(
          stage: 'initialization',
          timeout: initializationTimeout,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _initialize({
    required HttpClient client,
    required Uri baseUri,
    required String localAccessToken,
    required String encryptionKey,
  }) async {
    await _waitForHealth(client, baseUri, localAccessToken);
    final request = await _withRequestDeadline(
      'setup request',
      client.postUrl(baseUri.resolve('/v1/auth/setup')),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $localAccessToken');
    request.write(
      jsonEncode(<String, String>{'encryption_key': encryptionKey}),
    );
    final response = await _withRequestDeadline(
      'setup response',
      request.close(),
    );
    await _withRequestDeadline('setup response body', response.drain<void>());
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.created) {
      throw HttpException(
        'Local data API setup failed with HTTP ${response.statusCode}.',
        uri: baseUri.resolve('/v1/auth/setup'),
      );
    }
  }

  Future<void> _waitForHealth(
    HttpClient client,
    Uri baseUri,
    String localAccessToken,
  ) async {
    final deadline = DateTime.now().add(healthTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await _withRequestDeadline(
          'health request',
          client.getUrl(baseUri.resolve('/healthz')),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $localAccessToken',
        );
        final response = await _withRequestDeadline(
          'health response',
          request.close(),
        );
        await _withRequestDeadline(
          'health response body',
          response.drain<void>(),
        );
        if (response.statusCode == HttpStatus.ok) {
          return;
        }
        lastError = HttpException(
          'Health check returned HTTP ${response.statusCode}.',
          uri: baseUri.resolve('/healthz'),
        );
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (lastError case final DataApiLocalInitializationTimeoutException error) {
      throw error;
    }
    throw StateError('Local data API did not become healthy: $lastError');
  }

  Future<T> _withRequestDeadline<T>(String stage, Future<T> future) {
    return future.timeout(
      requestTimeout,
      onTimeout: () => throw DataApiLocalInitializationTimeoutException(
        stage: stage,
        timeout: requestTimeout,
      ),
    );
  }
}

class DataApiBootstrap {
  DataApiBootstrap({
    DataApiConfigurationRepository? configurationRepository,
    DataApiLocalCredentialsProvider? localCredentialsProvider,
    DataApiRemoteSessionSlotStore? remoteSessionStore,
    LocalDataApiRuntimeStarter? localRuntimeStarter,
    LocalDataApiSidecarLauncher? localSidecarLauncher,
    DataApiLocalApiInitialization? localApiInitializer,
    PortableMasterKeyRepository? masterKeyRepository,
    Duration sidecarCloseTimeout = const Duration(seconds: 12),
    bool? isMacOS,
  }) : _configurationRepository = configurationRepository,
       _localCredentialsProvider =
           localCredentialsProvider ??
           KeychainDataApiLocalCredentialsProvider(
             dataEncryptionKeyStore:
                 PortableMasterDataApiLocalDataEncryptionKeyStore(
                   masterKeyRepository: masterKeyRepository,
                 ),
           ),
       _remoteSessionStore = remoteSessionStore,
       _localRuntimeStarter = localRuntimeStarter,
       _localSidecarLauncher =
           localSidecarLauncher ?? LocalDataApiSidecar.start,
       _localApiInitializer =
           localApiInitializer ?? DataApiLocalApiInitializer(),
       _sidecarCloseTimeout = sidecarCloseTimeout,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final DataApiConfigurationRepository? _configurationRepository;
  final DataApiLocalCredentialsProvider _localCredentialsProvider;
  final DataApiRemoteSessionSlotStore? _remoteSessionStore;
  final LocalDataApiRuntimeStarter? _localRuntimeStarter;
  final LocalDataApiSidecarLauncher _localSidecarLauncher;
  final DataApiLocalApiInitialization _localApiInitializer;
  final Duration _sidecarCloseTimeout;
  final bool _isMacOS;

  Future<DataApiRuntime?> start({
    required Directory appSupportDirectory,
    DataApiConfiguration? configuration,
  }) async {
    final effectiveConfiguration =
        configuration ??
        await loadDataApiConfigurationForStartup(
          _configurationRepository ??
              FileDataApiConfigurationRepository(
                appSupportDirectory: appSupportDirectory,
              ),
        );
    if (effectiveConfiguration.deployment == DataApiDeployment.disabled) {
      return null;
    }
    final remoteBaseUri = effectiveConfiguration.remoteBaseUri;
    if (remoteBaseUri != null) {
      final credentialRef = effectiveConfiguration.remoteCredentialRef;
      if (credentialRef == null) {
        throw const DataApiAuthenticationRequiredException();
      }
      late DataApiRemoteSession? session;
      try {
        session =
            await (_remoteSessionStore ??
                    FlutterSecureDataApiRemoteSessionStore())
                .readSlot(credentialRef);
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          DataApiStartupDependencyException(
            dependency: DataApiStartupDependency.remoteSession,
            cause: error,
          ),
          stackTrace,
        );
      }
      if (session == null || !session.isUsableFor(remoteBaseUri)) {
        throw const DataApiAuthenticationRequiredException();
      }
      return DataApiRuntime.remote(
        baseUri: remoteBaseUri,
        remoteAccessToken: session.accessToken,
        encryptionKey: session.encryptionKey,
      );
    }
    if (!_isMacOS) {
      throw UnsupportedError(
        'The bundled local data API is only available on macOS.',
      );
    }
    return (_localRuntimeStarter ?? _startLocalRuntime)(appSupportDirectory);
  }

  Future<DataApiRuntime> _startLocalRuntime(
    Directory appSupportDirectory,
  ) async {
    final credentials = await _localCredentialsProvider.createForStart(
      appSupportDirectory,
    );
    final localAccessToken = credentials.bearerToken;
    final encryptionKey = credentials.dataEncryptionKey;
    final sidecar = await _localSidecarLauncher(
      binary: _resolveLocalApiBinary(),
      database: File(
        '${appSupportDirectory.path}${Platform.pathSeparator}'
        'data-api${Platform.pathSeparator}ianvs.db',
      ),
      localAccessToken: localAccessToken,
    );
    try {
      await _localApiInitializer.initialize(
        baseUri: sidecar.baseUri,
        localAccessToken: localAccessToken,
        encryptionKey: encryptionKey,
      );
    } on Object catch (initializationError, initializationStackTrace) {
      try {
        await sidecar.close().timeout(_sidecarCloseTimeout);
      } on Object catch (cleanupError) {
        Error.throwWithStackTrace(
          DataApiLocalInitializationCleanupException(
            initializationError: initializationError,
            cleanupError: cleanupError,
          ),
          initializationStackTrace,
        );
      }
      Error.throwWithStackTrace(initializationError, initializationStackTrace);
    }
    return DataApiRuntime.local(
      baseUri: sidecar.baseUri,
      localAccessToken: localAccessToken,
      encryptionKey: encryptionKey,
      closeLocalSidecar: sidecar.close,
    );
  }

  File _resolveLocalApiBinary() {
    final executable = File(Platform.resolvedExecutable);
    final contentsDirectory = executable.parent.parent;
    return File(
      '${contentsDirectory.path}${Platform.pathSeparator}Resources${Platform.pathSeparator}ianvs-api',
    );
  }
}

final class DataApiLocalInitializationCleanupException
    implements DataApiRuntimeTerminationFailureCarrier {
  const DataApiLocalInitializationCleanupException({
    required this.initializationError,
    required this.cleanupError,
  });

  final Object initializationError;
  final Object cleanupError;

  @override
  DataApiRuntimeTerminationUnknownFailure? get terminationFailure {
    return dataApiRuntimeTerminationFailureOf(cleanupError);
  }

  @override
  String toString() {
    return 'Local data API initialization failed ($initializationError), and '
        'bounded sidecar cleanup also failed ($cleanupError).';
  }
}

import 'dart:async';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_bootstrap.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_local_credentials.dart';
import 'package:app/data/services/data_api_remote_fallback.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/local_data_api_sidecar.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final unusedDirectory = Directory('/unused/application-support');

  test(
    'an unconfigured non-macOS app starts with the data API disabled',
    () async {
      var localStartCount = 0;
      final bootstrap = DataApiBootstrap(
        configurationRepository: _MemoryConfigurationRepository(
          const DataApiConfiguration.disabled(),
        ),
        isMacOS: false,
        localRuntimeStarter: (_) async {
          localStartCount += 1;
          return _localRuntime();
        },
      );

      final runtime = await bootstrap.start(
        appSupportDirectory: unusedDirectory,
      );

      expect(runtime, isNull);
      expect(localStartCount, 0);
    },
  );

  test('macOS local terminal mode never starts the bundled sidecar', () async {
    var localStartCount = 0;
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        const DataApiConfiguration.disabled(),
      ),
      isMacOS: true,
      localRuntimeStarter: (_) async {
        localStartCount += 1;
        return _localRuntime();
      },
    );

    final runtime = await bootstrap.start(appSupportDirectory: unusedDirectory);

    expect(runtime, isNull);
    expect(localStartCount, 0);
  });

  test(
    'an explicit startup snapshot is not re-read from the repository',
    () async {
      final repository = _MemoryConfigurationRepository(
        const DataApiConfiguration.local(),
      );
      final bootstrap = DataApiBootstrap(
        configurationRepository: repository,
        isMacOS: false,
        localRuntimeStarter: (_) =>
            throw StateError('must not start local API'),
      );

      final runtime = await bootstrap.start(
        appSupportDirectory: unusedDirectory,
        configuration: const DataApiConfiguration.disabled(),
      );

      expect(runtime, isNull);
      expect(repository.loadCount, 0);
    },
  );

  test('remote configuration creates a runtime without a sidecar', () async {
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        _remoteConfiguration('https://sync.example.com/api'),
      ),
      remoteSessionStore: _MemoryRemoteSessionStore(
        DataApiRemoteSession(
          baseUri: Uri.parse('https://sync.example.com/api/'),
          accessToken: 'remote-access-token',
          encryptionKey: 'remote-encryption-key',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      isMacOS: false,
      localRuntimeStarter: (_) => throw StateError('must not start local API'),
    );

    final runtime = await bootstrap.start(appSupportDirectory: unusedDirectory);

    expect(runtime?.deployment, DataApiDeployment.remote);
    expect(runtime?.baseUri, Uri.parse('https://sync.example.com/api/'));
    expect(runtime?.resourceAccessToken, 'remote-access-token');
    expect(runtime?.encryptionKey, 'remote-encryption-key');
  });

  test('remote configuration without a secure session fails closed', () async {
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        _remoteConfiguration('https://sync.example.com/api'),
      ),
      remoteSessionStore: _MemoryRemoteSessionStore(null),
      isMacOS: false,
      localRuntimeStarter: (_) => throw StateError('must not start local API'),
    );

    await expectLater(
      bootstrap.start(appSupportDirectory: unusedDirectory),
      throwsA(isA<DataApiAuthenticationRequiredException>()),
    );
  });

  test('local configuration delegates sidecar startup on macOS', () async {
    Directory? receivedDirectory;
    final expectedRuntime = _localRuntime();
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        const DataApiConfiguration.local(),
      ),
      isMacOS: true,
      localRuntimeStarter: (directory) async {
        receivedDirectory = directory;
        return expectedRuntime;
      },
    );

    final runtime = await bootstrap.start(appSupportDirectory: unusedDirectory);

    expect(runtime, same(expectedRuntime));
    expect(receivedDirectory, same(unusedDirectory));
  });

  test(
    'production local startup forwards one ephemeral bearer and stable data key',
    () async {
      final appSupportDirectory = await Directory.systemTemp.createTemp(
        'ianvs-bootstrap-local-credentials-',
      );
      final credentialsProvider = _LocalCredentialsProvider();
      final sidecar = _LocalSidecarHandle();
      final initializer = _CapturingLocalInitializer();
      String? launchedBearerToken;
      final bootstrap = DataApiBootstrap(
        configurationRepository: _MemoryConfigurationRepository(
          const DataApiConfiguration.local(),
        ),
        localCredentialsProvider: credentialsProvider,
        localSidecarLauncher:
            ({
              required binary,
              required database,
              required localAccessToken,
            }) async {
              launchedBearerToken = localAccessToken;
              expect(database.path, endsWith('data-api/ianvs.db'));
              return sidecar;
            },
        localApiInitializer: initializer,
        isMacOS: true,
      );

      try {
        final runtime = await bootstrap.start(
          appSupportDirectory: appSupportDirectory,
        );

        expect(credentialsProvider.calls, 1);
        expect(
          credentialsProvider.receivedDirectory,
          same(appSupportDirectory),
        );
        expect(launchedBearerToken, _LocalCredentialsProvider.bearerToken);
        expect(initializer.localAccessToken, launchedBearerToken);
        expect(runtime?.localAccessToken, launchedBearerToken);
        expect(
          runtime?.encryptionKey,
          _LocalCredentialsProvider.dataEncryptionKey,
        );

        await runtime?.close();
        expect(sidecar.closeCalls, 1);
      } finally {
        await appSupportDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'active remote fallback starts the isolated mirror with the portable master key',
    () async {
      final appSupportDirectory = await Directory.systemTemp.createTemp(
        'ianvs-bootstrap-remote-fallback-',
      );
      final dataApiDirectory = Directory(
        '${appSupportDirectory.path}${Platform.pathSeparator}data-api',
      );
      await dataApiDirectory.create(recursive: true);
      await FileDataApiRemoteFallbackLocalMirror.activeMarkerFor(
        appSupportDirectory,
      ).writeAsString('version=1\n');
      final mirrorDatabase = FileDataApiRemoteFallbackLocalMirror.databaseFor(
        appSupportDirectory,
      );
      await mirrorDatabase.writeAsString('remote-mirror');
      final masterKey = PortableMasterKey.fromSecret(
        _LocalCredentialsProvider.dataEncryptionKey,
      );
      final sidecar = _LocalSidecarHandle();
      File? launchedDatabase;
      final bootstrap = DataApiBootstrap(
        configurationRepository: _MemoryConfigurationRepository(
          const DataApiConfiguration.local(),
        ),
        masterKeyRepository: PortableMasterKeyRepository(
          storage: _MemoryPortableMasterKeyStorage(masterKey.portableValue),
        ),
        localCredentialsProvider: _ThrowingLocalCredentialsProvider(),
        localSidecarLauncher:
            ({
              required binary,
              required database,
              required localAccessToken,
            }) async {
              launchedDatabase = database;
              return sidecar;
            },
        localApiInitializer: _CapturingLocalInitializer(),
        isMacOS: true,
      );

      try {
        final runtime = await bootstrap.start(
          appSupportDirectory: appSupportDirectory,
        );

        expect(launchedDatabase?.path, mirrorDatabase.path);
        expect(runtime?.encryptionKey, masterKey.secret);
        await runtime?.close();
      } finally {
        await appSupportDirectory.delete(recursive: true);
      }
    },
  );

  test('local configuration is rejected outside macOS', () async {
    var localStartCount = 0;
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        const DataApiConfiguration.local(),
      ),
      isMacOS: false,
      localRuntimeStarter: (_) async {
        localStartCount += 1;
        return _localRuntime();
      },
    );

    expect(
      bootstrap.start(appSupportDirectory: unusedDirectory),
      throwsUnsupportedError,
    );
    expect(localStartCount, 0);
  });

  test('configuration read failure is typed and never selects local', () async {
    var localStartCount = 0;
    final bootstrap = DataApiBootstrap(
      configurationRepository: _ThrowingConfigurationRepository(
        const FileSystemException('configuration read failed'),
      ),
      isMacOS: true,
      localRuntimeStarter: (_) async {
        localStartCount += 1;
        return _localRuntime();
      },
    );

    await expectLater(
      bootstrap.start(appSupportDirectory: unusedDirectory),
      throwsA(
        isA<DataApiStartupDependencyException>()
            .having(
              (error) => error.dependency,
              'dependency',
              DataApiStartupDependency.configuration,
            )
            .having(
              (error) => error.toString(),
              'message',
              contains('Persistence remains locked'),
            ),
      ),
    );
    expect(localStartCount, 0);
  });

  test('secure-session read failure is typed and fails closed', () async {
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        _remoteConfiguration('https://sync.example.com/api'),
      ),
      remoteSessionStore: _ThrowingRemoteSessionStore(
        const FileSystemException('credential vault unavailable'),
      ),
      isMacOS: false,
      localRuntimeStarter: (_) => throw StateError('must not start local API'),
    );

    await expectLater(
      bootstrap.start(appSupportDirectory: unusedDirectory),
      throwsA(
        isA<DataApiStartupDependencyException>().having(
          (error) => error.dependency,
          'dependency',
          DataApiStartupDependency.remoteSession,
        ),
      ),
    );
  });

  test('local initialization cleanup exposes a nested termination marker', () {
    final terminationFailure = _TerminationUnknownFailure();
    final failure = DataApiLocalInitializationCleanupException(
      initializationError: StateError('initialization failed'),
      cleanupError: _TerminationFailureCarrier(terminationFailure),
    );

    expect(failure.terminationFailure, same(terminationFailure));
  });

  test('local health response that never starts has a deadline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestSeen = Completer<void>();
    server.listen((request) {
      if (!requestSeen.isCompleted) {
        requestSeen.complete();
      }
      // Deliberately leave the response open without sending headers.
    });
    final initializer = DataApiLocalApiInitializer(
      requestTimeout: const Duration(milliseconds: 30),
      healthTimeout: const Duration(milliseconds: 50),
      initializationTimeout: const Duration(milliseconds: 250),
    );

    try {
      await expectLater(
        initializer.initialize(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          localAccessToken: 'access-token',
        ),
        throwsA(
          isA<DataApiLocalInitializationTimeoutException>().having(
            (error) => error.stage,
            'stage',
            'health response',
          ),
        ),
      );
      await requestSeen.future;
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'local initialization only performs an authenticated health check',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer access-token',
        );
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      final initializer = DataApiLocalApiInitializer(
        requestTimeout: const Duration(milliseconds: 40),
        healthTimeout: const Duration(milliseconds: 150),
        initializationTimeout: const Duration(milliseconds: 300),
      );

      try {
        await initializer.initialize(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          localAccessToken: 'access-token',
        );
        expect(paths, <String>['/healthz']);
      } finally {
        await server.close(force: true);
      }
    },
  );
}

DataApiRuntime _localRuntime() => DataApiRuntime.local(
  baseUri: Uri.parse('http://127.0.0.1:49152'),
  localAccessToken: 'access-token',
  encryptionKey: 'encryption-key',
  closeLocalSidecar: () async {},
);

final class _MemoryConfigurationRepository
    implements DataApiConfigurationRepository {
  _MemoryConfigurationRepository(this.configuration);

  DataApiConfiguration configuration;
  int loadCount = 0;

  @override
  Future<DataApiConfiguration> load() async {
    loadCount += 1;
    return configuration;
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    this.configuration = configuration;
  }
}

final class _ThrowingConfigurationRepository
    implements DataApiConfigurationRepository {
  _ThrowingConfigurationRepository(this.error);

  final Object error;

  @override
  Future<DataApiConfiguration> load() => Future.error(error);

  @override
  Future<void> save(DataApiConfiguration configuration) async {}
}

DataApiConfiguration _remoteConfiguration(String url) {
  return DataApiConfiguration.remote(url).withPersistenceState(
    generation: 1,
    remoteCredentialRef: 'remoteSlot0000001',
    lastTransactionId: 'remoteTransaction01',
  );
}

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionSlotStore {
  _MemoryRemoteSessionStore(this.session);

  DataApiRemoteSession? session;

  @override
  Future<Set<String>> listSlotRefs() async => const <String>{
    'remoteSlot0000001',
  };

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async => session;

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async =>
      this.session = session;

  @override
  Future<void> deleteSlot(String slotRef) async => session = null;
}

final class _ThrowingRemoteSessionStore
    implements DataApiRemoteSessionSlotStore {
  _ThrowingRemoteSessionStore(this.error);

  final Object error;

  @override
  Future<Set<String>> listSlotRefs() => Future.error(error);

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) => Future.error(error);

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) =>
      Future.error(error);

  @override
  Future<void> deleteSlot(String slotRef) => Future.error(error);
}

final class _LocalCredentialsProvider
    implements DataApiLocalCredentialsProvider {
  static const bearerToken = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY';
  static const dataEncryptionKey =
      'YWJjZGVmMDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmM';

  int calls = 0;
  Directory? receivedDirectory;

  @override
  Future<DataApiLocalCredentials> createForStart(
    Directory appSupportDirectory,
  ) async {
    calls += 1;
    receivedDirectory = appSupportDirectory;
    return const DataApiLocalCredentials(
      bearerToken: bearerToken,
      dataEncryptionKey: dataEncryptionKey,
    );
  }
}

final class _ThrowingLocalCredentialsProvider
    implements DataApiLocalCredentialsProvider {
  @override
  Future<DataApiLocalCredentials> createForStart(
    Directory appSupportDirectory,
  ) {
    throw StateError('the legacy local credential must not be read');
  }
}

final class _MemoryPortableMasterKeyStorage
    implements PortableMasterKeyStorage {
  _MemoryPortableMasterKeyStorage(this.value);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
  }
}

final class _LocalSidecarHandle implements LocalDataApiSidecarHandle {
  @override
  final baseUri = Uri.parse('http://127.0.0.1:54321/');

  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class _CapturingLocalInitializer
    implements DataApiLocalApiInitialization {
  String? localAccessToken;

  @override
  Future<void> initialize({
    required Uri baseUri,
    required String localAccessToken,
  }) async {
    expect(baseUri, Uri.parse('http://127.0.0.1:54321/'));
    this.localAccessToken = localAccessToken;
  }
}

final class _TerminationUnknownFailure
    implements DataApiRuntimeTerminationUnknownFailure {}

final class _TerminationFailureCarrier
    implements DataApiRuntimeTerminationFailureCarrier {
  const _TerminationFailureCarrier(this.terminationFailure);

  @override
  final DataApiRuntimeTerminationUnknownFailure terminationFailure;
}

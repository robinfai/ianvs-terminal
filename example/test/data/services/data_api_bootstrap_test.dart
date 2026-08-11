import 'dart:async';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_bootstrap.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
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
        DataApiConfiguration.remote('https://sync.example.com/api'),
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
        DataApiConfiguration.remote('https://sync.example.com/api'),
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
        DataApiConfiguration.remote('https://sync.example.com/api'),
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
          encryptionKey: 'encryption-key',
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

  test('local setup response body that never drains has a deadline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final setupSeen = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/healthz') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      if (!setupSeen.isCompleted) {
        setupSeen.complete();
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..write('partial');
      await request.response.flush();
      // Deliberately leave the chunked response body open.
    });
    final initializer = DataApiLocalApiInitializer(
      requestTimeout: const Duration(milliseconds: 40),
      healthTimeout: const Duration(milliseconds: 150),
      initializationTimeout: const Duration(milliseconds: 300),
    );

    try {
      await expectLater(
        initializer.initialize(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          localAccessToken: 'access-token',
          encryptionKey: 'encryption-key',
        ),
        throwsA(
          isA<DataApiLocalInitializationTimeoutException>().having(
            (error) => error.stage,
            'stage',
            'setup response body',
          ),
        ),
      );
      await setupSeen.future;
    } finally {
      await server.close(force: true);
    }
  });
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

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionStore {
  _MemoryRemoteSessionStore(this.session);

  DataApiRemoteSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<DataApiRemoteSession?> read() async => session;

  @override
  Future<void> write(DataApiRemoteSession session) async {
    this.session = session;
  }
}

final class _ThrowingRemoteSessionStore implements DataApiRemoteSessionStore {
  _ThrowingRemoteSessionStore(this.error);

  final Object error;

  @override
  Future<void> clear() async {}

  @override
  Future<DataApiRemoteSession?> read() => Future.error(error);

  @override
  Future<void> write(DataApiRemoteSession session) async {}
}

final class _TerminationUnknownFailure
    implements DataApiRuntimeTerminationUnknownFailure {}

final class _TerminationFailureCarrier
    implements DataApiRuntimeTerminationFailureCarrier {
  const _TerminationFailureCarrier(this.terminationFailure);

  @override
  final DataApiRuntimeTerminationUnknownFailure terminationFailure;
}

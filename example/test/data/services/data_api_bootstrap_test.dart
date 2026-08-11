import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_bootstrap.dart';
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

  test('remote configuration creates a runtime without a sidecar', () async {
    final bootstrap = DataApiBootstrap(
      configurationRepository: _MemoryConfigurationRepository(
        DataApiConfiguration.remote('https://sync.example.com/api'),
      ),
      isMacOS: false,
      localRuntimeStarter: (_) => throw StateError('must not start local API'),
    );

    final runtime = await bootstrap.start(appSupportDirectory: unusedDirectory);

    expect(runtime?.deployment, DataApiDeployment.remote);
    expect(runtime?.baseUri, Uri.parse('https://sync.example.com/api/'));
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

  @override
  Future<DataApiConfiguration> load() async => configuration;

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    this.configuration = configuration;
  }
}

import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
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
    'quarantines invalid configuration and repairs it as disabled',
    () async {
      await repository.configurationFile.parent.create(recursive: true);
      await repository.configurationFile.writeAsString('{"version":1}');

      final loaded = await repository.load();

      expect(loaded, const DataApiConfiguration.disabled());
      expect(await repository.configurationFile.exists(), isTrue);
      expect(
        repository.configurationFile.parent.listSync().any(
          (entry) => entry.path.contains('configuration.json.corrupt'),
        ),
        isTrue,
      );
    },
  );
}

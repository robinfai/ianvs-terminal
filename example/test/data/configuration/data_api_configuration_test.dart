import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled and local configurations do not contain a remote URL', () {
    const disabled = DataApiConfiguration.disabled();
    const local = DataApiConfiguration.local();

    expect(disabled.deployment, DataApiDeployment.disabled);
    expect(disabled.remoteBaseUri, isNull);
    expect(local.deployment, DataApiDeployment.local);
    expect(local.remoteBaseUri, isNull);
  });

  test('remote configuration validates and normalizes its base URL', () {
    final configuration = DataApiConfiguration.remote(
      ' https://sync.example.com/api ',
    );

    expect(configuration.deployment, DataApiDeployment.remote);
    expect(
      configuration.remoteBaseUri,
      Uri.parse('https://sync.example.com/api/'),
    );
  });

  test('configuration JSON round-trips all deployment modes', () {
    final configurations = <DataApiConfiguration>[
      const DataApiConfiguration.disabled(),
      const DataApiConfiguration.local(),
      DataApiConfiguration.remote('https://sync.example.com/base'),
    ];

    for (final configuration in configurations) {
      final decoded = DataApiConfiguration.fromJson(configuration.toJson());

      expect(decoded.deployment, configuration.deployment);
      expect(decoded.remoteBaseUri, configuration.remoteBaseUri);
    }
  });

  test('rejects unsafe or non-http remote addresses', () {
    for (final value in <String>[
      'ssh://example.com/service',
      'https://user:secret@example.com/service',
      'https://example.com/service?token=secret',
      'https://example.com/service#fragment',
      '/relative/service',
    ]) {
      expect(
        () => DataApiConfiguration.remote(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('rejects unknown versions and incomplete remote configuration', () {
    expect(
      () => DataApiConfiguration.fromJson(<String, Object?>{
        'version': 2,
        'deployment': 'disabled',
      }),
      throwsFormatException,
    );
    expect(
      () => DataApiConfiguration.fromJson(<String, Object?>{
        'version': DataApiConfiguration.currentVersion,
        'deployment': 'remote',
      }),
      throwsFormatException,
    );
  });
}

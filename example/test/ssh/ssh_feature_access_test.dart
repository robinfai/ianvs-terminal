import 'package:app/data/configuration/data_api_configuration_providers.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom SSH is disabled without a Data API runtime', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(customSshProfileConfigurationEnabledProvider),
      isFalse,
    );
    expect(
      container.read(crossDeviceConfigurationSyncEnabledProvider),
      isFalse,
    );
  });

  test('bundled local API enables persistent custom SSH profiles', () {
    final container = ProviderContainer(
      overrides: [
        dataApiRuntimeProvider.overrideWithValue(
          DataApiRuntime.local(
            baseUri: Uri.parse('http://127.0.0.1:42100/'),
            localAccessToken: 'local-access-token',
            encryptionKey: 'local-encryption-key',
            closeLocalSidecar: () async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(customSshProfileConfigurationEnabledProvider),
      isTrue,
    );
    expect(
      container.read(crossDeviceConfigurationSyncEnabledProvider),
      isFalse,
    );
  });

  test('authenticated remote API enables persistent custom SSH profiles', () {
    final container = ProviderContainer(
      overrides: [
        dataApiRuntimeProvider.overrideWithValue(
          DataApiRuntime.remote(
            baseUri: Uri.parse('https://sync.example.com/'),
            remoteAccessToken: 'remote-access-token',
            encryptionKey: 'remote-encryption-key',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(customSshProfileConfigurationEnabledProvider),
      isTrue,
    );
    expect(container.read(crossDeviceConfigurationSyncEnabledProvider), isTrue);
  });
}

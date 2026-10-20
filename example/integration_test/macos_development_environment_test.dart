import 'dart:io';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/startup/app_environment.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('development starts and restarts without accessing Keychain', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs-development-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    var keychainCalls = 0;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async {
      keychainCalls++;
      throw PlatformException(code: 'unexpected_keychain_access');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    String? token;
    String? key;
    for (var attempt = 0; attempt < 2; attempt++) {
      final coordinator = createProductionAppStartupCoordinator(
        environment: AppEnvironment.development,
        appSupportDirectoryResolver: () async => root,
      );
      try {
        await coordinator.start();
        expect(coordinator.state, isA<AppStartupReady>());
        final runtime =
            (coordinator.state as AppStartupReady).graph.dataApiRuntime!;
        expect(runtime.isLocal, isTrue);
        expect(runtime.baseUri.host, '127.0.0.1');
        final aiStore = createAiConfigurationStore(
          appSupportDirectoryResolver: () async => root,
        );
        final client = DataApiClient.fromRuntime(runtime);
        if (attempt == 0) {
          await aiStore.write(const AiConfiguration.mock());
          token = runtime.localAccessToken;
          key = runtime.encryptionKey;
          await client.putResource(
            kind: 'profiles',
            id: 'dev-test',
            data: {'name': 'Development test'},
            sensitive: {'password': 'test-only'},
          );
        } else {
          expect((await aiStore.read())?.model, 'trail-mock');
          // Compare without printing actual key material on failure.
          expect(runtime.localAccessToken != token, isTrue);
          expect(runtime.encryptionKey == key, isTrue);
          final resource = await client.getResource(
            kind: 'profiles',
            id: 'dev-test',
            includeSensitive: true,
          );
          expect(resource?.sensitive, {'password': 'test-only'});
          expect(
            await client.deleteResource(kind: 'profiles', id: 'dev-test'),
            isTrue,
          );
        }
      } finally {
        await coordinator.close();
        coordinator.dispose();
      }
    }
    expect(keychainCalls, 0);
  });
}

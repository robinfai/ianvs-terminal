import 'dart:io';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/startup/app_environment.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('development Keychain and bundled backend survive restart', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs-development-test-',
    );
    addTearDown(() => root.delete(recursive: true));
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
        final client = DataApiClient.fromRuntime(runtime);
        if (attempt == 0) {
          token = runtime.localAccessToken;
          key = runtime.encryptionKey;
          await client.putResource(
            kind: 'profiles',
            id: 'dev-test',
            data: {'name': 'Development test'},
            sensitive: {'password': 'test-only'},
          );
        } else {
          // Compare without printing actual Keychain material on failure.
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
  });
}

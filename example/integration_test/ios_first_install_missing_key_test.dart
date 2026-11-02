import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS first install without a synchronized key still renders the home',
    (tester) async {
      expect(Platform.isIOS, isTrue);

      final support = Directory.systemTemp.createTempSync(
        'ianvs-ios-local-first-support-',
      );
      final documents = Directory.systemTemp.createTempSync(
        'ianvs-ios-local-first-documents-',
      );
      final coordinator = createProductionAppStartupCoordinator(
        platform: TargetPlatform.iOS,
        masterKeyRepository: PortableMasterKeyRepository(
          storage: const _FixedPortableMasterKeyStorage(null),
          allowCreation: false,
          allowLegacyMigration: false,
        ),
        appSupportDirectoryResolver: () async => support,
        appDocumentsDirectoryResolver: () async => documents,
        secureRecovery: (_) async => null,
      );
      addTearDown(() async {
        await coordinator.close();
        await tester.pumpWidget(const SizedBox.shrink());
        for (final directory in <Directory>[support, documents]) {
          if (directory.existsSync()) {
            directory.deleteSync(recursive: true);
          }
        }
      });

      await tester.pumpWidget(
        AppStartupHost(
          coordinator: coordinator,
          disposeCoordinator: false,
          startAutomatically: false,
          enableSessionPolling: false,
          enableShellAnimations: false,
        ),
      );
      await coordinator.start();
      await tester.pumpAndSettle();

      expect(coordinator.state, isA<AppStartupDataSetupRequired>());
      expect(
        (coordinator.state as AppStartupDataSetupRequired).canSkip,
        isTrue,
      );
      expect(
        find.byKey(const Key('app-startup-mobile-welcome')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byKey(const Key('app-startup-skip-data-api')));
      await tester.pumpAndSettle();

      expect(coordinator.state, isA<AppStartupReady>());
      expect(find.byKey(const Key('app-startup-mobile-welcome')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('ios-ssh-profile-empty-state')),
        findsOneWidget,
      );
      await binding.takeScreenshot('first-launch-local-home');
      final graph = (coordinator.state as AppStartupReady).graph;
      expect(graph.dataApiRuntime, isNull);
      expect(graph.persistenceRepositories.usesDataApi, isFalse);
    },
  );
}

final class _FixedPortableMasterKeyStorage implements PortableMasterKeyStorage {
  const _FixedPortableMasterKeyStorage(this.value);

  final String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) {
    throw StateError('The acceptance test master key is read-only.');
  }
}

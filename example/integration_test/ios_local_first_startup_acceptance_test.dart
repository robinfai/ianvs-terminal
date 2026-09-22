import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS starts locally without an API and persists encrypted SSH profiles',
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
          storage: _FixedPortableMasterKeyStorage(
            PortableMasterKey.fromSecret(
              'ios-local-first-acceptance-key-material',
            ).portableValue,
          ),
          allowCreation: false,
          allowLegacyMigration: false,
        ),
        appSupportDirectoryResolver: () async => support,
        appDocumentsDirectoryResolver: () async => documents,
        secureRecovery: (_) async => null,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coordinator.close();
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
      final graph = (coordinator.state as AppStartupReady).graph;
      expect(graph.dataApiRuntime, isNull);
      expect(graph.persistenceRepositories.usesDataApi, isFalse);

      final profile = defaultTerminalProfile().copyWith(
        id: 'local-first-acceptance',
        name: 'Local SSH acceptance',
        connection: const TerminalConnectionConfig.ssh(
          host: 'offline.example.test',
          user: 'acceptance-user',
          password: 'local-first-ssh-secret',
        ),
      );
      await graph.persistenceRepositories.profiles.save(
        TerminalProfilesDocument(profiles: [profile]),
      );
      final reloaded = await graph.persistenceRepositories.profiles.load();
      expect(reloaded.profiles.single.id, profile.id);
      expect(
        reloaded.profiles.single.connection.password,
        'local-first-ssh-secret',
      );
      final persisted = await File(
        '${support.path}/ianvs_profiles.json',
      ).readAsString();
      expect(persisted, isNot(contains('local-first-ssh-secret')));
    },
  );
}

final class _FixedPortableMasterKeyStorage implements PortableMasterKeyStorage {
  const _FixedPortableMasterKeyStorage(this.value);

  final String value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) {
    throw StateError('The acceptance test master key is read-only.');
  }
}

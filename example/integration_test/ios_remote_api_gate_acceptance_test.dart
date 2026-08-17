import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS cannot enter the terminal without a remote HTTPS API', (
    tester,
  ) async {
    expect(Platform.isIOS, isTrue);

    final support = Directory.systemTemp.createTempSync(
      'ianvs-ios-data-gate-support-',
    );
    final documents = Directory.systemTemp.createTempSync(
      'ianvs-ios-data-gate-documents-',
    );
    final coordinator = createProductionAppStartupCoordinator(
      platform: TargetPlatform.iOS,
      masterKeyRepository: PortableMasterKeyRepository(
        storage: _FixedPortableMasterKeyStorage(
          PortableMasterKey.fromSecret(
            'ios-remote-api-gate-acceptance-key-material',
          ).portableValue,
        ),
        allowCreation: false,
      ),
      appSupportDirectoryResolver: () async => support,
      appDocumentsDirectoryResolver: () async => documents,
      secureRecovery: (_) async => null,
      nativePtyLoader: () async => throw StateError(
        'The PTY must not load before required remote setup succeeds.',
      ),
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
      AppStartupHost(coordinator: coordinator, disposeCoordinator: false),
    );
    await coordinator.start();
    await tester.pumpAndSettle();

    expect(coordinator.state, isA<AppStartupDataSetupRequired>());
    expect(find.byKey(const Key('app-startup-data-api-setup')), findsOneWidget);
    expect(find.byKey(const Key('app-startup-skip-data-api')), findsNothing);
    expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);

    final connect = find.byKey(const Key('app-startup-connect-data-api'));
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);

    await _enterAcceptanceCredentials(tester, url: '');
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);

    await _enterAcceptanceCredentials(tester, url: 'http://sync.example.com/');
    expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('app-startup-initial-data-api-error')),
      findsOneWidget,
    );
    expect(find.textContaining('requires HTTPS'), findsOneWidget);
    expect(coordinator.state, isA<AppStartupDataSetupRequired>());
  });
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

Future<void> _enterAcceptanceCredentials(
  WidgetTester tester, {
  required String url,
}) async {
  await tester.enterText(
    find.byKey(const Key('app-startup-initial-data-api-url')),
    url,
  );
  await tester.enterText(
    find.byKey(const Key('app-startup-initial-data-api-username')),
    'acceptance-user',
  );
  await tester.enterText(
    find.byKey(const Key('app-startup-initial-data-api-password')),
    'acceptance-password',
  );
  expect(
    find.byKey(const Key('app-startup-apple-keychain-status')),
    findsOneWidget,
  );
  expect(find.byKey(const Key('app-startup-initial-master-key')), findsNothing);
  await tester.pump();
}

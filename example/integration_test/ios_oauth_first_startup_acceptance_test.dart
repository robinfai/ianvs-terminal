import 'dart:convert';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/configuration/oauth_sign_in_panel.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS first OAuth login enters the real home without restarting', (
    tester,
  ) async {
    expect(Platform.isIOS, isTrue);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      final body = switch (request.uri.path) {
        '/v1/auth/login/complete' => <String, Object>{
          'token': 'integration-session-only',
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
          'user': {
            'id': '00000000-0000-4000-8000-000000000001',
            'username': 'integration',
          },
        },
        '/v1/me' => <String, Object>{
          'user': {
            'id': '00000000-0000-4000-8000-000000000001',
            'username': 'integration',
          },
        },
        '/v1/resources' => <String, Object>{
          'resources': <Object>[],
          'next_cursor': '',
        },
        '/healthz' => <String, Object>{'status': 'ok', 'mode': 'remote'},
        _ => <String, Object>{},
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });

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
    expect((coordinator.state as AppStartupDataSetupRequired).canSkip, isTrue);
    expect(find.byKey(const Key('app-startup-mobile-welcome')), findsOneWidget);
    expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('app-startup-configure-llm')), findsNothing);
    await binding.takeScreenshot('first-launch-sign-in');

    final panel = tester.widget<OAuthSignInPanel>(
      find.byType(OAuthSignInPanel),
    );
    final login = panel.onAuthenticated!(
      DataApiRemoteLoginRequest.oauth(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        operation: DataApiPreparedAuthOperation(
          operationId: base64Url
              .encode(List<int>.filled(32, 1))
              .replaceAll('=', ''),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await login;
    await tester.pumpAndSettle();
    expect(coordinator.state, isA<AppStartupReady>());
    await _waitForSshHome(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('ios-ssh-profile-empty-state')),
      findsOneWidget,
    );
    await binding.takeScreenshot('first-oauth-login-home');
    final graph = (coordinator.state as AppStartupReady).graph;
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
  });
}

Future<void> _waitForSshHome(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
    listen: false,
  );
  final home = find.byKey(const Key('ios-ssh-profile-empty-state'));
  final elapsed = Stopwatch()..start();

  // AppStartupReady mounts the shell, whose session bootstrap still awaits
  // filesystem I/O. pumpAndSettle only waits for frames, not that I/O.
  while (elapsed.elapsed < const Duration(seconds: 30)) {
    final session = container.read(sessionControllerProvider);
    if (session.isReady && home.evaluate().isNotEmpty) {
      return;
    }
    if (!session.isReady && session.lastError != null) {
      fail('First-login shell bootstrap failed: ${session.lastError}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  final session = container.read(sessionControllerProvider);
  fail(
    'First-login SSH home did not appear within 30 seconds: '
    'isReady=${session.isReady}, lastError=${session.lastError}, '
    'homeCount=${home.evaluate().length}',
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

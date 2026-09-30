import 'dart:convert';
import 'dart:io';

import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux production startup opens a real local PTY without an API',
    (tester) async {
      ensureDesktopIntegrationTestFramesEnabled(tester.binding);
      final root = await Directory.systemTemp.createTemp(
        'ianvs-linux-production-',
      );
      final coordinator = createProductionAppStartupCoordinator(
        platform: TargetPlatform.linux,
        appSupportDirectoryResolver: () async => root,
        appDocumentsDirectoryResolver: () async => root,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coordinator.close();
        coordinator.dispose();
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(
        AppStartupHost(
          coordinator: coordinator,
          disposeCoordinator: false,
          startAutomatically: false,
          enableShellAnimations: false,
        ),
      );
      await coordinator.start();
      await tester.pumpAndSettle();
      expect(coordinator.state, isA<AppStartupDataSetupRequired>());
      expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);
      await tester.tap(find.byKey(const Key('app-startup-skip-data-api')));
      await _waitFor(tester, () => coordinator.state is AppStartupReady);
      final graph = (coordinator.state as AppStartupReady).graph;
      expect(graph.ptySessionBackend, isA<NativePtyBackend>());
      expect(graph.dataApiRuntime, isNull);
      expect(graph.persistenceRepositories.usesDataApi, isFalse);
      await _waitFor(
        tester,
        () => find.byType(ShellScreen).evaluate().isNotEmpty,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      await _waitFor(
        tester,
        () => container.read(sessionControllerProvider).activeSessionId != null,
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      // Split the marker in the command so echoed input alone cannot pass.
      container
          .read(terminalRuntimeControllerProvider)
          .sendInput(
            sessionId,
            Uint8List.fromList(
              utf8.encode("printf 'LINUX_%s_OK\\n' 'PRODUCTION'\n"),
            ),
          );
      await _waitFor(tester, () {
        final frame = container
            .read(sessionControllerProvider.notifier)
            .viewportFor(sessionId)
            .frame;
        return frame.rows.any(
          (row) => row.text.contains('LINUX_PRODUCTION_OK'),
        );
      });
      expect((await coordinator.close()).safeToTerminate, isTrue);
    },
    skip: !Platform.isLinux,
  );

  testWidgets(
    'Linux secure vault preserves encrypted SSH profiles across repository recreation',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-linux-secrets-',
      );
      final storage = _IsolatedLinuxMasterKeyStorage(
        'ianvs.integration.$pid.${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        await storage.delete();
        await root.delete(recursive: true);
      });
      ProfileRepository openRepository() {
        final masterKey = PortableMasterKeyRepository(
          storage: storage,
          allowLegacyMigration: false,
        );
        return ProfileRepository(
          directoryResolver: () async => root,
          secretCipher: ProfileSecretCipher(
            keyStore: PortableMasterProfileSecretKeyStore(
              masterKeyRepository: masterKey,
            ),
          ),
        );
      }

      const secret = 'synthetic-linux-ssh-secret';
      final profile = defaultTerminalProfile().copyWith(
        id: 'linux-vault-fixture',
        connection: const TerminalConnectionConfig.ssh(
          host: 'offline.example.test',
          user: 'fixture',
          password: secret,
        ),
      );
      await openRepository().save(
        TerminalProfilesDocument(profiles: [profile]),
      );
      final encoded = await File(
        '${root.path}/ianvs_profiles.json',
      ).readAsString();
      expect(encoded.contains(secret), isFalse);
      expect((await storage.read())?.startsWith('ianvs-key-v1.'), isTrue);
      final reopened = await openRepository().load();
      expect(reopened.profiles.single.connection.password == secret, isTrue);
      expect(reopened.loadWarnings, isEmpty);
      await storage.delete();
      expect(await storage.read(), isNull);
    },
    skip: !Platform.isLinux,
  );
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Linux desktop acceptance condition timed out');
}

final class _IsolatedLinuxMasterKeyStorage implements PortableMasterKeyStorage {
  _IsolatedLinuxMasterKeyStorage(this.key);
  final String key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String portableValue) =>
      _storage.write(key: key, value: portableValue);
  Future<void> delete() => _storage.delete(key: key);
}

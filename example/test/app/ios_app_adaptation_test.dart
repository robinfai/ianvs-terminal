import 'dart:io';

import 'package:app/app.dart';
import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/pty/pty.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

void main() {
  test('production iOS startup publishes the sandbox shell backend', () async {
    final support = Directory.systemTemp.createTempSync('ianvs-ios-startup-');
    final documents = Directory.systemTemp.createTempSync('ianvs-ios-docs-');
    addTearDown(() {
      for (final directory in <Directory>[support, documents]) {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      }
    });
    final repository = _DisabledConfigurationRepository();
    final remoteSessionStore = _EmptyRemoteSessionStore();
    final coordinator = createProductionAppStartupCoordinator(
      platform: TargetPlatform.iOS,
      appSupportDirectoryResolver: () async => support,
      appDocumentsDirectoryResolver: () async => documents,
      configurationAccessFactory: (paths) async {
        return AppStartupConfigurationAccess(
          repository: repository,
          remoteSessionStore: remoteSessionStore,
          settings: _DisabledStartupSettings(),
        );
      },
      secureRecovery: (access) async => null,
      nativePtyLoader: () async => NativePtyBackend.load(),
    );

    await coordinator.start();

    final graph = (coordinator.state as AppStartupReady).graph;
    expect(graph.ptySessionBackend, isA<IosSandboxShellBackend>());
    expect(
      (graph.ptySessionBackend as IosSandboxShellBackend).rootDirectory.path,
      Directory('${documents.path}/IanvsShell').absolute.path,
    );
    await coordinator.close();
  });

  testWidgets(
    'iPhone shell accepts keyboard input and exposes responsive terminal keys',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('ianvs-ios-widget-');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(
              IosSandboxShellBackend(
                rootDirectory: root,
                terminalBackend: NativePtyBackend.load(),
              ),
            ),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
              ),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              noIoLocalSessionRecordingRepository(),
            ),
            sessionPollingEnabledProvider.overrideWithValue(false),
            sessionDemoFixtureProvider.overrideWithValue(null),
          ],
          child: const IanvsTerminalApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
      expect(find.byKey(const Key('ios-sandbox-shell-notice')), findsOneWidget);
      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      expect(
        tester.getSize(find.byKey(const Key('shell-chrome-bar'))).height,
        96,
      );
      expect(
        tester.getSize(find.byKey(const Key('ios-terminal-key-Escape'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const Key('ios-terminal-key-Escape'))).width,
        greaterThanOrEqualTo(44),
      );

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'echo hello-ios',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump(const Duration(milliseconds: 80));

      var viewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(
        viewport.controller.frame.rows.map((row) => row.text).join('\n'),
        contains('hello-ios'),
      );

      final dollarKey = find.byKey(const Key('ios-terminal-key-Dollar sign'));
      await tester.scrollUntilVisible(
        dollarKey,
        240,
        scrollable: find.descendant(
          of: find.byKey(const Key('ios-terminal-character-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(dollarKey);
      await tester.pump(const Duration(milliseconds: 40));
      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(
        viewport.controller.frame.rows.any(
          (row) => row.text.trimRight().endsWith(r'$'),
        ),
        isTrue,
      );

      final initialFontSize = viewport.font.size;
      final center = tester.getCenter(find.byType(TerminalViewport));
      final first = await tester.startGesture(
        center - const Offset(18, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(18, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(70, 0));
      await second.moveTo(center + const Offset(70, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(viewport.font.size, greaterThan(initialFontSize));

      await tester.tap(find.byKey(const Key('ios-terminal-font-reset')));
      await tester.pump();
      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(viewport.font.size, closeTo(initialFontSize, 0.01));

      tester.view.physicalSize = const Size(375, 667);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);

      tester.view.physicalSize = const Size(667, 375);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TerminalViewport)).height,
        greaterThan(80),
      );

      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    },
  );
}

final class _DisabledConfigurationRepository
    implements DataApiConfigurationRepository {
  @override
  Future<DataApiConfiguration> load() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {}
}

final class _EmptyRemoteSessionStore implements DataApiRemoteSessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<DataApiRemoteSession?> read() async => null;

  @override
  Future<void> write(DataApiRemoteSession session) async {}
}

final class _DisabledStartupSettings
    implements AppStartupDataSettingsCapability {
  @override
  bool get localDataApiAvailable => false;

  @override
  Future<DataApiConfiguration> loadForRecovery() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> reconnect(DataApiRemoteLoginRequest request) async {}

  @override
  Future<void> saveDisabled() async {}
}

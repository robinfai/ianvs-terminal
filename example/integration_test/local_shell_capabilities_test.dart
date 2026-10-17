import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/shell_capabilities_dialog.dart';
import 'package:app/features/sessions/shell_integration_capabilities.dart';
import 'package:app/features/shell/shell_screen.dart'
    show pasteHistoryRepositoryProvider;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_test.dart' show MemoryAiStore;
import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native local capability UI waits for actual output and variables',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final home = await Directory.systemTemp.createTemp('trail-capabilities-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='caps> '\nRPROMPT=''\n");
      final profile = TerminalProfile(
        id: 'caps',
        name: 'Local capability acceptance',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'LANG': 'en_US.UTF-8',
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        },
      );
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration(endpoint: '', apiKey: '', model: ''),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          aiSettingsProvider.overrideWithValue(settings),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(defaultProfileId: 'caps'),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            noIoLocalTerminalLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            noIoLocalSessionRecordingRepository(),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final sessions = container.read(sessionControllerProvider.notifier);
        final ids = container
            .read(sessionControllerProvider)
            .tabs
            .expand((tab) => tab.effectivePanes)
            .map((pane) => pane.sessionId)
            .toList();
        for (final id in ids) {
          await sessions.closeSession(id);
        }
        container.dispose();
        settings.dispose();
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() condition, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              '$label: ${container.read(sessionControllerProvider).tabs.firstOrNull?.activePane.shellCapabilities.toJson()}',
            );
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
      }

      Future<void> show(Brightness brightness) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('zh'),
              themeAnimationDuration: Duration.zero,
              theme: buildIanvsTerminalTheme(
                brightness,
                platform: TargetPlatform.macOS,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: RepaintBoundary(
                  key: const Key('capabilities-capture'),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final pane = ref
                          .watch(sessionControllerProvider)
                          .tabs
                          .firstOrNull
                          ?.activePane;
                      if (pane == null) return const SizedBox.shrink();
                      return ShellCapabilitiesDialog(
                        sessionTitle: pane.title,
                        capabilities: pane.shellCapabilities,
                        bootstrapPhase: pane.shellIntegration.bootstrapPhase,
                        bootstrapSource: pane.shellIntegration.bootstrapSource,
                        registrationChecks:
                            pane.shellIntegration.registrationChecks,
                        onClose: () {},
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        const directory = String.fromEnvironment('LOCAL_CAPS_EVIDENCE_DIR');
        if (directory.isEmpty) return;
        await Directory(directory).create(recursive: true);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capabilities-capture')),
        );
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      await show(Brightness.light);
      await waitFor(
        () =>
            container
                .read(sessionControllerProvider)
                .tabs
                .firstOrNull
                ?.activePane
                .shellCapabilities[ShellIntegrationCapability
                    .integrationVersion]
                .isActive ==
            true,
        'initial native metadata',
      );
      final pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(
        pane.shellCapabilities.entries.values.where((e) => e.isActive),
        hasLength(11),
      );
      expect(pane.shellIntegration.integrationVersion, '2');
      expect(pane.shellIntegration.promptMarks, isNotEmpty);
      for (final cap in [
        ShellIntegrationCapability.commandOutputRanges,
        ShellIntegrationCapability.userVariables,
      ]) {
        expect(
          pane.shellCapabilities[cap].reason,
          ShellCapabilityReason.awaitingEvent,
        );
      }
      final runtime = container.read(terminalRuntimeControllerProvider);
      final id = pane.sessionId;
      expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
      await capture('native-startup-light');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shell-capability-user_variables')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('等待实际事件'), findsNWidgets(2));
      await capture('native-waiting-light');
      runtime.sendInput(
        id,
        Uint8List.fromList(
          utf8.encode("printf 'capability-output\\n'; false\n"),
        ),
      );
      await waitFor(
        () => container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .shellCapabilities[ShellIntegrationCapability.commandOutputRanges]
            .isActive,
        'actual output range',
      );
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .shellCapabilities
            .entries
            .values
            .where((e) => e.isActive),
        hasLength(12),
      );
      runtime.sendInput(
        id,
        Uint8List.fromList(
          utf8.encode("ianvs_set_user_var IANVS_PROJECT 'project 中文'\n"),
        ),
      );
      await waitFor(
        () => container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .shellCapabilities[ShellIntegrationCapability.userVariables]
            .isActive,
        'explicit variable',
      );
      final complete = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(
        complete.shellCapabilities.entries.values.where((e) => e.isActive),
        hasLength(13),
      );
      expect(
        complete.shellIntegration.userVariables['IANVS_PROJECT'],
        'project 中文',
      );
      await show(Brightness.dark);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shell-capability-user_variables')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('等待实际事件'), findsNothing);
      await capture('native-observed-dark');
      expect(tester.takeException(), isNull);
    },
  );
}

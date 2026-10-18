import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
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
    'Block workspace resumes cloud after real second-hop SSH failure',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final fixture =
          jsonDecode(
                await File(
                  const String.fromEnvironment('SSH_ROLLBACK_FIXTURE'),
                ).readAsString(),
              )
              as Map;
      final home = await Directory.systemTemp.createTemp('trail-ssh-block-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='fixture> '\nRPROMPT=''\n");
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration(endpoint: '', apiKey: '', model: ''),
        ),
      );
      final profile = TerminalProfile(
        id: 'ssh-block',
        name: 'SSH Block rollback',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
          'LANG': 'en_US.UTF-8',
        },
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
              const LocalTerminalConfigDocument(
                defaultProfileId: 'ssh-block',
                appearance: TerminalAppAppearance(
                  preferredTerminalMode: TerminalViewMode.blocks,
                ),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            noIoLocalTerminalLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            noIoLocalSessionRecordingRepository(),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      final sessions = container.read(sessionControllerProvider.notifier);
      final runtime = container.read(terminalRuntimeControllerProvider);
      String? id;
      Map<String, Object?>? shell() => id == null
          ? null
          : runtime.composerRequest(id, 'composer.state', const {});
      TerminalModeState? mode() => container
          .read(sessionControllerProvider)
          .tabs
          .firstOrNull
          ?.activePane
          .terminalMode;
      String screen() => id == null
          ? ''
          : sessions.viewportFor(id).frame.rows.map((r) => r.text).join('\n');
      String? lastState;
      Map<String, Object?> snapshot() {
        final s = shell();
        return {
          'mode': mode()?.mode.name,
          'reason': mode()?.unavailableReason?.name,
          'contextId': s?['contextId'],
          'state': s?['state'],
          'lease': s?['lease'],
          'transport': s?['transport'],
          'running': container
              .read(sessionControllerProvider)
              .tabs
              .firstOrNull
              ?.activePane
              .shellIntegration
              .runningCommand,
        };
      }

      Future<void> waitFor(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready()) {
          final current = snapshot().toString();
          if (current != lastState) {
            debugPrint('$label: $current');
            lastState = current;
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('$label; state=${snapshot()}; screen=${screen()}');
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (id != null) await sessions.closeSession(id);
        container.dispose();
        settings.dispose();
        await home.delete(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildIanvsTerminalTheme(
              Brightness.light,
              platform: TargetPlatform.macOS,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ShellScreen()),
          ),
        ),
      );
      await waitFor(
        () => container.read(sessionControllerProvider).activeSessionId != null,
        'local session',
      );
      id = container.read(sessionControllerProvider).activeSessionId;
      await waitFor(
        () =>
            mode()?.mode == TerminalViewMode.blocks &&
            shell()?['state'] == 'ready',
        'local Block ready',
      );
      Future<void> run(String command) async {
        await waitFor(
          () =>
              mode()?.mode == TerminalViewMode.blocks &&
              shell()?['state'] == 'ready' &&
              find.byKey(const Key('ai-prompt')).evaluate().isNotEmpty &&
              tester
                  .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
                  .controller
                  .canRunUserCommand,
          'Block ready for $command',
        );
        final prompt = find.byKey(const Key('ai-prompt'));
        await tester.tap(prompt);
        await tester.enterText(prompt, command);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(const Key('ai-send')));
        await tester.pump(const Duration(milliseconds: 100));
      }

      await run("ssh -F '${fixture['local_config']}' cloud");
      await waitFor(
        () =>
            shell()?['contextId'] != 'root' &&
            shell()?['state'] == 'ready' &&
            mode()?.mode == TerminalViewMode.blocks,
        'cloud Block ready',
      );
      final cloud = shell()!['contextId'];
      // Entering another host keeps the existing task's target guard. Choose
      // a new task on cloud explicitly; a failed second hop must not require
      // another task or manual mode selection.
      await tester.tap(find.byKey(const Key('ai-new-task')));
      await tester.pump(const Duration(milliseconds: 200));
      await waitFor(
        () => tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller
            .canRunUserCommand,
        'new cloud task ready',
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final lease = shell()!['lease'];
        await run('ssh sg');
        await waitFor(
          () =>
              shell()?['contextId'] == cloud &&
              shell()?['state'] == 'ready' &&
              shell()?['lease'] != lease &&
              mode()?.mode == TerminalViewMode.blocks,
          'failed sg returns to cloud Block',
        );
        final blocks = runtime.commandBlocks(id!)!['blocks']! as List;
        final failed = blocks
            .whereType<Map<Object?, Object?>>()
            .where((b) => b['command'] == 'ssh sg')
            .toList();
        expect(failed.length, attempt + 1);
        expect(failed.last['exitCode'], 255);
        expect(find.byType(TerminalAiWorkspace), findsOneWidget);
        expect(screen(), isNot(contains(RegExp(r'\[1\] \d+'))));
      }
      await run(r"printf 'cloud-after-sg\n'");
      await waitFor(
        () =>
            shell()?['state'] == 'ready' &&
            mode()?.mode == TerminalViewMode.blocks &&
            screen().contains('cloud-after-sg'),
        'cloud command after failure',
      );
      expect(shell()!['contextId'], cloud);
    },
  );
}

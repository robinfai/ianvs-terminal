import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_panel.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

class _ProxyStore implements AiConfigurationStore {
  _ProxyStore(this.value);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async =>
      value = configuration;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const keyPath = String.fromEnvironment('TRAIL_PROXY_KEY_FILE');
  const evidencePath = String.fromEnvironment('TRAIL_PROXY_EVIDENCE');
  const persist = bool.fromEnvironment('TRAIL_PROXY_PERSIST');
  testWidgets(
    'OAuth Luna drives real Command Block and vim through Trail UI',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final configuration = AiConfiguration(
        endpoint: 'http://127.0.0.1:8317/v1',
        apiKey: (await File(keyPath).readAsString()).trim(),
        model: 'gpt-6-luna',
      );
      final settings = AiSettingsController(_ProxyStore(configuration));
      final home = await Directory.systemTemp.createTemp('trail-proxy-ui-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='trail-proxy> '\nRPROMPT=''\n");
      final profile = TerminalProfile(
        id: 'proxy-ui',
        name: 'Luna proxy acceptance',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'XDG_CONFIG_HOME': home.path,
          'XDG_DATA_HOME': home.path,
          'LANG': 'en_US.UTF-8',
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
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
            MemoryAppPreferencesRepository(
              const TerminalAppPreferencesDocument(
                appearance: TerminalAppAppearance(
                  preferredTerminalMode: TerminalViewMode.blocks,
                ),
              ),
            ),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(null),
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
      final captureKey = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final tab in container.read(sessionControllerProvider).tabs) {
          for (final pane in tab.effectivePanes) {
            await container
                .read(sessionControllerProvider.notifier)
                .closeSession(pane.sessionId);
          }
        }
        container.dispose();
        settings.dispose();
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> click(Key key) async {
        await waitFor(
          () => find.byKey(key).evaluate().isNotEmpty,
          'UI control $key',
        );
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 150));
      }

      Future<void> capture(String name) async {
        if (evidencePath.isEmpty) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidencePath).create(recursive: true);
        await File(
          '$evidencePath/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: const IanvsTerminalApp(),
          ),
        ),
      );
      await waitFor(
        () => container.read(sessionControllerProvider).activeSessionId != null,
        'local session',
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      Map<String, Object?>? shell() =>
          runtime.composerRequest(id, 'composer.state', const {});
      await waitFor(() => shell()?['state'] == 'ready', 'negotiated shell');
      await waitFor(
        () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
        'visible Command Block view',
      );
      TerminalAiController ai() => tester
          .widget<TerminalAiPanel>(find.byType(TerminalAiPanel))
          .controller;
      Future<void> ask(String prompt) async {
        await click(const Key('ai-prompt'));
        await tester.enterText(find.byKey(const Key('ai-prompt')), prompt);
        await tester.pump();
        await click(const Key('ai-send'));
        await waitFor(() => !ai().busy, 'model proposal');
        expect(ai().error, isNull);
      }

      await click(Key('terminal-ai-open-$id'));
      await waitFor(() => ai().context != null, 'AI context');
      await ask(r"运行且仅运行这条命令：printf 'trail-luna-ui-ok\n'");
      expect(ai().pending?.kind, AiActionKind.runCommand);
      expect(ai().pending!.command!.trim(), r"printf 'trail-luna-ui-ok\n'");
      await capture('luna-command-approval');
      await click(const Key('ai-approve'));
      await waitFor(() => !ai().busy, 'command completion');
      expect(ai().error, isNull);
      expect(ai().context!.lastBlock!.exitCode, 0);
      expect(ai().context!.lastBlock!.output, contains('trail-luna-ui-ok'));
      expect(find.byType(TerminalCommandBlocksView), findsOneWidget);
      await capture('luna-command-completed');
      await click(const Key('ai-close'));
      final proof = File('${home.path}/vim-proof.txt');
      await proof.writeAsString('original\n');
      await waitFor(
        () => shell()?['state'] == 'ready',
        'shell ready before vim',
      );
      runtime.composerRequest(id, 'composer.submit', {
        'lease': shell()!['lease'],
        'submissionId': 'proxy-ui-vim',
        'text': '/usr/bin/vim -u NONE -N ${proof.path}',
      });
      await waitFor(
        () => runtime.liveScreen(id)?['alternateScreen'] == true,
        'vim alternate screen',
      );
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      final viewportSize = tester.getSize(find.byType(TerminalViewport));
      await click(Key('terminal-ai-open-$id'));
      expect(tester.getSize(find.byType(TerminalViewport)), viewportSize);
      await ask(
        '在当前 vim 的第一行之前插入一行 Trail Luna verified，保存并退出 vim。只修改当前这个临时验证文件。',
      );
      expect(await proof.readAsString(), 'original\n');
      var approvals = 0;
      while (ai().canApprove) {
        expect(++approvals, lessThanOrEqualTo(8));
        expect(ai().pending!.kind, AiActionKind.sendKeys);
        await capture('luna-vim-approval-$approvals');
        await click(const Key('ai-approve'));
        await waitFor(() => !ai().busy, 'vim action $approvals');
        expect(ai().error, isNull);
      }
      await waitFor(() => shell()?['state'] == 'ready', 'return from vim');
      expect(runtime.liveScreen(id)?['alternateScreen'], false);
      await waitFor(
        () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
        'return to visible Command Block view',
      );
      expect(await proof.readAsString(), 'Trail Luna verified\noriginal\n');
      await capture('luna-vim-completed');
      if (persist) {
        final store = SecureAiConfigurationStore();
        await store.write(configuration);
        final saved = await store.read();
        expect(saved?.endpoint, configuration.endpoint);
        expect(saved?.model, configuration.model);
        expect(saved?.apiKey == configuration.apiKey, isTrue);
      }
      if (evidencePath.isNotEmpty) {
        await File('$evidencePath/result.json').writeAsString(
          jsonEncode({
            'model': configuration.model,
            'endpoint': configuration.endpoint,
            'command_block_exit_code': 0,
            'command_block_view_verified': true,
            'full_screen_vim_view_verified': true,
            'vim_saved_and_exited': true,
            'vim_approvals': approvals,
            'configuration_persisted': persist,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
    },
    skip: keyPath.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

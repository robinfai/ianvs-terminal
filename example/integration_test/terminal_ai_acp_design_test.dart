import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/acp/codex_acp_backend.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
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
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

class _Store implements AiConfigurationStore {
  _Store(this.value);
  final AiConfiguration value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidencePath = String.fromEnvironment('TRAIL_ACP_DESIGN_EVIDENCE');
  testWidgets(
    'real ACP conversation proposes, executes and returns from evidence',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final installation = await CodexAcpBackend.discoverInstallation();
      final configuration = AiConfiguration.acp(
        agentCommand: installation.command,
        agentArguments: installation.arguments,
        model: 'gpt-5.6-sol',
      );
      final settings = AiSettingsController(_Store(configuration));
      final home = await Directory.systemTemp.createTemp('trail-acp-design-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='trail-proxy> '\nRPROMPT=''\n");
      final profile = TerminalProfile(
        id: 'proxy-ui',
        name: '本地演示项目',
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
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                defaultProfileId: 'proxy-ui',
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
      final statusFile = File('${home.path}/status.txt');
      const initialStatus = 'service=demo\nenabled=false\nhealth=not_checked\n';
      await statusFile.writeAsString(initialStatus);
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

      TerminalAiController? ai;
      final result = <String, Object?>{
        'model': configuration.model,
        'backend': 'acp',
        'passed': false,
      };
      addTearDown(() async {
        if (evidencePath.isEmpty) return;
        await Directory(evidencePath).create(recursive: true);
        result['transcript'] = [
          for (final entry in ai?.transcript ?? <AiTranscriptEntry>[])
            {
              'role': entry.role,
              'text': entry.text,
              if (entry.action != null) 'command': entry.action!.preview,
            },
        ];
        await File(
          '$evidencePath/result.json',
        ).writeAsString(jsonEncode(result));
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!ready()) {
          if (ai?.error != null) fail('${ai!.error}: $label');
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> click(Key key) async {
        await waitFor(() => find.byKey(key).evaluate().isNotEmpty, '$key');
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<void> capture(String name) async {
        if (evidencePath.isEmpty) return;
        if (find.byKey(const Key('block-reader')).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 350));
        }
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
        'session',
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      await waitFor(
        () =>
            runtime.composerRequest(id, 'composer.state', const {})?['state'] ==
            'ready',
        'shell ready',
      );
      await click(Key('terminal-ai-open-$id'));
      ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        '请用 cat status.txt 查看当前演示项目的状态文件，先给我命令提案，等我确认。读取后解释文件能证明什么、还不能证明什么，并引用原输出。不要修改文件，也不要查询其他目录。',
      );
      await tester.pump();
      await click(const Key('ai-send'));
      await waitFor(() => ai!.canApprove, 'real proposal');
      // Only this pre-reviewed read of a disposable fixture is permitted by the
      // harness. A different model command fails the test without execution.
      expect(ai.pending!.command?.trim(), 'cat status.txt');
      expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
      await capture('real-proposal-light');
      await container
          .read(sessionControllerProvider.notifier)
          .setThemeMode(TerminalThemeMode.dark);
      await tester.pumpAndSettle();
      await capture('real-proposal-dark');
      await click(const Key('ai-approve'));
      await waitFor(
        () =>
            ai!.phase == AiPhase.idle &&
            ai.transcript.any((e) => e.state == AiEntryState.accepted),
        'real result',
      );
      final blocks = (runtime.commandBlocks(id)!['blocks']! as List)
          .map(CommandBlock.fromJson)
          .whereType<CommandBlock>()
          .toList();
      expect(blocks, hasLength(1));
      expect(blocks.single.exitCode, 0);
      expect(await statusFile.readAsString(), initialStatus);
      await capture('real-result-dark');
      await container
          .read(sessionControllerProvider.notifier)
          .setThemeMode(TerminalThemeMode.light);
      await tester.pumpAndSettle();
      await capture('real-result-light');
      final citations = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('ai-evidence-'),
      );
      expect(citations, findsWidgets);
      final citationSize = tester.getSize(citations.first);
      result['citationHitTarget'] = {
        'width': citationSize.width,
        'height': citationSize.height,
      };
      expect(citationSize.height, greaterThanOrEqualTo(28));
      await tester.ensureVisible(citations.first);
      await tester.tap(citations.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-reader')), findsOneWidget);
      final readerTokens = ComposerTheme.of(
        tester.element(find.byKey(const Key('block-reader-range'))),
      );
      final luminances = [
        readerTokens.muted.computeLuminance(),
        readerTokens.surface.computeLuminance(),
      ]..sort();
      final contrast = (luminances.last + .05) / (luminances.first + .05);
      result['readerMetadataContrast'] = contrast;
      expect(contrast, greaterThanOrEqualTo(4.5));
      await capture('real-evidence-light');
      await click(const Key('block-reader-close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-reader')), findsNothing);
      expect(runtime.commandBlocks(id)!['blocks'], hasLength(1));
      await capture('real-returned-light');
      result.addAll({
        'passed': true,
        'nativeCommands': 1,
        'fileUnchanged': true,
        'evidenceReturned': true,
      });
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

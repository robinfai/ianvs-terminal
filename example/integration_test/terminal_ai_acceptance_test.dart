import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_panel.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/gestures.dart';
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
import 'composer_acceptance_test.dart' show until;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Configured mock drives shell correction, vi, vim and real k9s', (
    tester,
  ) async {
    ensureMacosIntegrationTestFramesEnabled(tester.binding);
    final home = await Directory.systemTemp.createTemp('trail-ai-pty-');
    await File(
      '${home.path}/.zshrc',
    ).writeAsString("PROMPT='trail-ai> '\nRPROMPT=''\n");
    await File(
      '${home.path}/ai-visible-file.txt',
    ).writeAsString('terminal evidence');
    final profile = TerminalProfile(
      id: 'ai-acceptance',
      name: 'AI acceptance',
      shell: '/bin/zsh',
      cwd: home.path,
      env: {
        'HOME': home.path,
        'ZDOTDIR': home.path,
        'XDG_CONFIG_HOME': home.path,
        'XDG_DATA_HOME': home.path,
        'LANG': 'en_US.UTF-8',
        'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
      },
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
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
      const keepConfiguration = bool.fromEnvironment(
        'AI_PERSIST_CONFIGURATION',
      );
      final settings = container.read(aiSettingsProvider);
      if (!keepConfiguration &&
          settings.configuration?.apiKey == 'trail-local-mock') {
        await settings.save(null);
      }
      container.dispose();
      await home.delete(recursive: true);
    });
    Future<void> capture(String name) async {
      const directory = String.fromEnvironment('AI_EVIDENCE_DIR');
      if (directory.isEmpty) return;
      await tester.pump();
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
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
    await until(
      tester,
      () => container.read(sessionControllerProvider).activeSessionId != null,
    );
    final id = container.read(sessionControllerProvider).activeSessionId!;
    final runtime = container.read(terminalRuntimeControllerProvider);
    String screen() => runtime.liveScreen(id)?['text'] as String? ?? '';
    Map<String, Object?>? shell() =>
        runtime.composerRequest(id, 'composer.state', const {});
    await until(
      tester,
      () => shell()?['state'] == 'ready',
      diagnostics: () => '${shell()}',
    );

    Future<void> click(Key key) async {
      await tester.pump();
      final finder = find.byKey(key);
      await until(
        tester,
        () => finder.evaluate().isNotEmpty,
        diagnostics: () => 'Missing $key; ${screen()}',
      );
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 100));
    }

    TerminalAiController ai() =>
        tester.widget<TerminalAiPanel>(find.byType(TerminalAiPanel)).controller;
    Future<void> openAi() async {
      await click(Key('terminal-ai-open-$id'));
      await until(
        tester,
        () =>
            find.byType(TerminalAiPanel).evaluate().isNotEmpty &&
            ai().context != null,
      );
    }

    Future<void> waitProposal() => until(
      tester,
      () => ai().pending != null || ai().error != null,
      diagnostics: () =>
          'AI ${ai().phase} ${ai().error}, takeover=${ai().takenOver}; ${screen()}',
    );
    Future<void> ask(String prompt) async {
      await click(const Key('ai-prompt'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(find.byKey(const Key('ai-prompt')), prompt);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-prompt')))
            .controller!
            .text,
        prompt,
      );
      await click(const Key('ai-send'));
      await waitProposal();
      expect(ai().error, isNull);
    }

    Future<void> approve({bool nextProposal = false}) async {
      await click(const Key('ai-approve'));
      await until(
        tester,
        () => !ai().busy,
        diagnostics: () => '${ai().phase} ${ai().error} ${screen()}',
      );
      expect(ai().error, isNull);
      expect(ai().pending != null, nextProposal);
    }

    Future<void> start(String command) async {
      await until(tester, () => shell()?['state'] == 'ready');
      final response = runtime.composerRequest(id, 'composer.submit', {
        'lease': shell()!['lease'],
        'submissionId': 'setup-${DateTime.now().microsecondsSinceEpoch}',
        'text': command,
      });
      expect(response?['outcome'], anyOf('accepted', 'pending'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Exercise persisted endpoint/key/model configuration through the actual UI.
    await openAi();
    await click(const Key('ai-open-settings'));
    await until(
      tester,
      () => find.byKey(const Key('ai-use-mock')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await until(
      tester,
      () =>
          tester
              .widget<TextButton>(find.byKey(const Key('ai-use-mock')))
              .onPressed !=
          null,
      diagnostics: () => 'Secure configuration has not finished loading',
    );
    await click(const Key('ai-use-mock'));
    await click(const Key('ai-test-connection'));
    await capture('00-connection-diagnostic');
    await until(
      tester,
      () => find.byKey(const Key('ai-connection-ok')).evaluate().isNotEmpty,
      diagnostics: () => find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .join('\n'),
    );
    await capture('01-configured-connection');
    await click(const Key('ai-save-settings'));
    await tester.pumpAndSettle();
    final restored = await SecureAiConfigurationStore().read();
    expect(restored?.endpoint, 'http://127.0.0.1:8787/v1');
    expect(restored?.apiKey, 'trail-local-mock');
    expect(restored?.model, 'trail-mock');
    await click(const Key('ai-close'));

    // Natural-language input shares Composer but never reaches the shell as prose.
    await tester.tap(
      find.byKey(Key('shell-tab-$id')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await click(Key('terminal-mode-blocks-$id'));
    await until(
      tester,
      () => find.byType(TerminalComposerView).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('composer-editor')),
      '请列出当前目录文件',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await click(const Key('composer-primary-action'));
    await until(
      tester,
      () => find.byType(TerminalAiPanel).evaluate().isNotEmpty,
    );
    await waitProposal();
    expect(ai().pending!.command, 'ls -la');
    expect(runtime.commandBlocks(id)?['blocks'], isEmpty);
    await capture('02-natural-language-approval');
    await approve();
    expect(screen(), contains('ai-visible-file.txt'));
    await capture('03-natural-language-result');
    await click(const Key('ai-close'));

    // Error correction uses a real failing command and its native block output.
    await start('ls --not-a-real-option');
    await until(tester, () => shell()?['state'] == 'ready');
    await openAi();
    expect(ai().context!.lastBlock!.exitCode, isNonZero);
    await click(const Key('ai-correct-command'));
    await waitProposal();
    expect(ai().pending!.command, 'ls');
    await capture('04-error-correction');
    await approve();
    expect(ai().context!.lastBlock!.exitCode, 0);
    await click(const Key('ai-close'));

    for (final editor in ['vi', 'vim']) {
      final file = File('${home.path}/$editor-proof.txt');
      await file.writeAsString('original\n');
      await start('/usr/bin/$editor -u NONE -N ${file.path}');
      await until(
        tester,
        () => runtime.liveScreen(id)?['alternateScreen'] == true,
      );
      final size = tester.getSize(find.byType(TerminalViewport));
      await openAi();
      expect(
        tester.getSize(find.byType(TerminalViewport)),
        size,
        reason: 'Full terminal use must not resize the running editor.',
      );
      await ask('在 $editor 第一行插入 "Trail $editor verified" 并保存');
      expect(await file.readAsString(), 'original\n');
      await approve(nextProposal: true);
      expect(screen(), contains('Trail $editor verified'));
      await approve();
      expect(await file.readAsString(), 'Trail $editor verified\noriginal\n');
      await capture('05-$editor-saved');
      await ask('保存并退出 $editor');
      await approve();
      await until(
        tester,
        () =>
            shell()?['state'] == 'ready' &&
            runtime.liveScreen(id)?['alternateScreen'] == false,
      );
      await click(const Key('ai-close'));
    }

    // The real k9s binary talks only to an isolated read-only loopback fixture.
    // Exercise the dark app surface as well; k9s's default skin assumes a dark
    // terminal background. Preferences are isolated in this test's memory store.
    await container
        .read(sessionControllerProvider.notifier)
        .setThemeMode(TerminalThemeMode.dark);
    await tester.pumpAndSettle();
    const kubeconfig = String.fromEnvironment(
      'AI_KUBECONFIG',
      defaultValue: '/private/tmp/trail-ai-acceptance/kubeconfig.json',
    );
    expect(await File(kubeconfig).exists(), isTrue);
    await start(
      '/opt/homebrew/bin/k9s --readonly --splashless --logoless --kubeconfig $kubeconfig --logFile ${home.path}/k9s.log --command namespaces',
    );
    await until(
      tester,
      () =>
          runtime.liveScreen(id)?['alternateScreen'] == true &&
          screen().toLowerCase().contains('namespaces(all)'),
      diagnostics: screen,
    );
    await openAi();
    await ask('在 k9s 中查看 pods');
    await capture('06-k9s-approval');
    await approve();
    await until(
      tester,
      () => screen().contains('trail-ai-pod'),
      diagnostics: screen,
    );
    await capture('07-k9s-pods');
    await ask('在 k9s 中查看命名空间');
    final before = screen();
    await click(const Key('ai-take-over'));
    expect(ai().pending, isNull);
    expect(ai().takenOver, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(screen(), contains('trail-ai-pod'));
    expect(before, contains('trail-ai-pod'));
    expect(tester.takeException(), isNull);
  });
}

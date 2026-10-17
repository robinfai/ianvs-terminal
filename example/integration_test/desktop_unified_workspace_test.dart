import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
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
  testWidgets('desktop native Block and AI share input, history and draft', (
    tester,
  ) async {
    ensureMacosIntegrationTestFramesEnabled(tester.binding);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      await request.drain<void>();
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'The terminal printed desktop-unified-marker.',
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    final settings = AiSettingsController(
      MemoryAiStore(
        AiConfiguration(
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'fixture',
          model: 'fixture',
        ),
      ),
    );
    final home = await Directory.systemTemp.createTemp(
      'trail-desktop-unified-',
    );
    await File(
      '${home.path}/.zshrc',
    ).writeAsString("PROMPT='unified> '\nRPROMPT=''\n");
    await Directory('${home.path}/alpha').create();
    await Directory('${home.path}/beta').create();
    final profile = TerminalProfile(
      id: 'unified',
      name: 'Desktop Block + AI',
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
          MemoryAppPreferencesRepository(null),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              defaultProfileId: 'unified',
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
      await server.close(force: true);
      await home.delete(recursive: true);
    });
    Future<void> waitFor(bool Function() ready, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          final workspaces = tester.widgetList<TerminalAiWorkspace>(
            find.byType(TerminalAiWorkspace),
          );
          final task = workspaces.firstOrNull?.controller;
          fail(
            'Timed out: $label; requests=$requests phase=${task?.phase} error=${task?.error} terminal=${task?.terminalError} draft=${task?.draft} transcript=${task?.transcript.map((e) => '${e.role}/${e.state}:${e.text}').toList()}',
          );
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    Future<void> enterDraft(String value) async {
      final prompt = find.byKey(const Key('ai-prompt'));
      await tester.ensureVisible(prompt);
      await tester.tap(prompt);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(prompt, value);
      await tester.pump(const Duration(milliseconds: 150));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: const Key('desktop-native-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildIanvsTerminalTheme(
              Brightness.dark,
              platform: TargetPlatform.macOS,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ShellScreen()),
          ),
        ),
      ),
    );
    await waitFor(
      () => find.byType(TerminalAiWorkspace).evaluate().isNotEmpty,
      'unified workspace',
    );
    final workspace = tester.widget<TerminalAiWorkspace>(
      find.byType(TerminalAiWorkspace),
    );
    final ai = workspace.controller;
    final id = container.read(sessionControllerProvider).activeSessionId!;
    final runtime = container.read(terminalRuntimeControllerProvider);
    await waitFor(() => ai.context?.canRunCommand == true, 'negotiated shell');
    expect(
      find.byKey(const Key('composer-editor')).hitTestable(),
      findsNothing,
    );
    expect(requests, 0);
    await enterDraft('ls ./');
    expect(ai.inputIntentDecision().intent, InputIntent.command);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await waitFor(
      () => find
          .byKey(const Key('composer-completion-list'))
          .evaluate()
          .isNotEmpty,
      'native path completions',
    );
    expect(ai.draft, 'ls ./');
    expect(requests, 0);
    const completionEvidence = String.fromEnvironment(
      'DESKTOP_UNIFIED_EVIDENCE_DIR',
    );
    if (completionEvidence.isNotEmpty) {
      await Directory(completionEvidence).create(recursive: true);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('desktop-native-capture')),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$completionEvidence/native-path-completions.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai.draft, isNot('ls ./'));
    expect(
      ai.transcript,
      isEmpty,
      reason: 'Candidate acceptance cannot execute',
    );
    await enterDraft(r"printf 'desktop-unified-marker\n'");
    await tester.pump();
    expect(ai.inputIntentDecision().intent, InputIntent.command);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ai-send')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('ai-send')), warnIfMissed: true);
    await waitFor(
      () =>
          !ai.busy &&
          ai.transcript.any((e) => e.state == AiEntryState.accepted),
      'command receipt',
    );
    expect(ai.error, isNull);
    final blocks = runtime.commandBlocks(id)!['blocks']! as List;
    expect(
      blocks.any(
        (b) =>
            (b as Map)['command'].toString().contains('desktop-unified-marker'),
      ),
      isTrue,
    );
    final count = blocks.length;
    expect(requests, 0);
    ai.chooseInputIntent(InputIntentChoice.ai);
    expect(ai.inputIntentChoice, InputIntentChoice.ai);
    await enterDraft('Explain the output without running another command.');
    await tester.pump();
    expect(ai.draft, 'Explain the output without running another command.');
    expect(ai.inputIntentDecision().intent, InputIntent.ai);
    expect(ai.settings.configuration?.model, 'fixture');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ai-send')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('ai-send')), warnIfMissed: true);
    await waitFor(
      () => !ai.busy && ai.transcript.any((e) => e.role == 'assistant'),
      'AI reply',
    );
    expect(requests, 1);
    expect(ai.error, isNull);
    await enterDraft('shared draft\nsecond line');
    await tester.pump();
    const evidence = String.fromEnvironment('DESKTOP_UNIFIED_EVIDENCE_DIR');
    if (evidence.isNotEmpty) {
      await Directory(evidence).create(recursive: true);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('desktop-native-capture')),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$evidence/native-unified-dark.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }
    workspace.onTakeOver!();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TerminalAiWorkspace), findsNothing);
    await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
    await waitFor(
      () => find.byType(TerminalAiWorkspace).evaluate().isNotEmpty,
      'return to workspace',
    );
    final reopened = tester.widget<TerminalAiWorkspace>(
      find.byType(TerminalAiWorkspace),
    );
    expect(reopened.controller, same(ai));
    expect(ai.draft, 'shared draft\nsecond line');
    expect(runtime.commandBlocks(id)!['blocks'], hasLength(count));
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
}

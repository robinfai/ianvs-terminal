import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_approval_notice.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_panel.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;

void main() {
  testWidgets(
    'historical approval notice does not request another submission',
    (tester) async {
      for (final source in ['manual', 'unavailable']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiApprovalNotice(
                review: AiApprovalReview(
                  automatic: false,
                  reason: 'Recorded review',
                  source: source,
                ),
                confirmed: true,
                pending: false,
              ),
            ),
          ),
        );
        expect(find.textContaining('Confirmed by you'), findsOneWidget);
        expect(
          find.textContaining('Your confirmation is needed'),
          findsNothing,
        );
        expect(find.textContaining('No command was sent'), findsNothing);
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiApprovalNotice(
              review: AiApprovalReview(
                automatic: false,
                reason: 'Scope unclear.',
              ),
              pending: false,
            ),
          ),
        ),
      );
      expect(find.textContaining('Review record'), findsOneWidget);
      expect(find.textContaining('Your confirmation is needed'), findsNothing);
    },
  );
  testWidgets('composer intent override changes Enter without changing views', (
    tester,
  ) async {
    final prompts = <String>[];
    final commands = <String>[];
    final composer = TerminalComposerController(
      targetId: 'local',
      provider: (q, _) async => CompletionBatch(q, const []),
      submit: (submission) async {
        commands.add(submission.query.value.text);
        return ComposerSubmissionOutcome.accepted;
      },
    );
    addTearDown(composer.dispose);
    composer.updateIntentContext(
      const InputIntentContext(commandNames: {'pwd', 'git'}),
    );
    composer.updateShell(
      contextKey: 'local',
      cwd: '/tmp',
      ownership: ComposerOwnership.ready,
      lease: 'one',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposerView(
            controller: composer,
            targetLabel: 'Local',
            onAskAi: prompts.add,
          ),
        ),
      ),
    );
    final input = find.byKey(const Key('composer-editor'));
    await tester.enterText(input, '帮我找出最大的文件');
    await tester.pump();
    expect(find.text('Ask AI · Auto'), findsOneWidget);
    expect(commands, isEmpty);
    await tester.tap(find.byKey(const Key('composer-input-intent')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'command',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(input, 'echo "中文"');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(commands, ['echo "中文"']);
    expect(prompts, isEmpty);
    composer.updateShell(
      contextKey: 'local-2',
      cwd: '/tmp',
      ownership: ComposerOwnership.ready,
      lease: 'two',
    );
    await tester.pump();
    await tester.enterText(input, '为什么失败');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(prompts, ['为什么失败']);
    expect(commands, hasLength(1));
    composer.chooseInputIntent(InputIntentChoice.ai);
    await tester.enterText(input, 'git status');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pump();
    expect(prompts, ['为什么失败', 'git status']);
    expect(composer.inputIntent.choice, InputIntentChoice.automatic);
    await tester.enterText(input, 'pwd');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('connection types keep separate model choices', (tester) async {
    final settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiSettingsDialog(
            settings: settings,
            discoverAcp: () async =>
                throw const AiFailure('acp_adapter_missing'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final original = tester
        .widget<TextField>(find.byKey(const Key('ai-model')))
        .controller!
        .text;
    await tester.tap(find.byKey(const Key('ai-backend')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex ACP').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai-model')))
          .controller!
          .text,
      'gpt-5.6-sol',
    );
    await tester.tap(find.byKey(const Key('ai-backend')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model API').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai-model')))
          .controller!
          .text,
      original,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ACP settings round trip without an API key or starting an agent',
    (tester) async {
      const value = AiConfiguration.acp(
        agentCommand: '/usr/bin/env',
        agentArguments: ['node', '/tmp/codex-acp.js'],
      );
      final restored = AiConfiguration.fromJson(value.toJson());
      expect(restored.backend, AiBackendKind.acp);
      expect(restored.apiKey, isEmpty);
      final store = MemoryAiStore(restored);
      final settings = AiSettingsController(store);
      await settings.loaded;
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AiSettingsDialog(settings: settings)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-agent-command')), findsOneWidget);
      expect(find.byKey(const Key('ai-api-key')), findsNothing);
      expect(find.text('gpt-5.6-sol'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('ai-model')), 'gpt-5.6-sol');
      await tester.tap(find.byKey(const Key('ai-save-settings')));
      await tester.pumpAndSettle();
      expect(store.value!.backend, AiBackendKind.acp);
      expect(store.value!.agentArguments, ['node', '/tmp/codex-acp.js']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('task status and resume remain reachable while reading history', (
    tester,
  ) async {
    final settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    final terminal = FakeTerminal();
    final api = FakeApi()
      ..respond = (step) async =>
          AiReply(text: 'Reply $step\n${'Output\n' * 12}');
    final controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    addTearDown(() {
      controller.dispose();
      settings.dispose();
    });
    for (var i = 0; i < 5; i++) {
      await controller.ask('Read $i');
    }
    api.respond = (_) async => throw const AiFailure('timeout');
    await controller.ask('Keep working');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 420,
              child: TerminalAiPanel(controller: controller, onClose: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    scroll.jumpTo(0);
    await tester.pump();
    final status = find.byKey(const Key('ai-task-status'));
    expect(status.hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('ai-resume')).hitTestable(), findsOneWidget);
    api.respond = (_) async =>
        const AiReply(text: 'Continuing with fresh context');
    await tester.tap(find.byKey(const Key('ai-resume')));
    await tester.pumpAndSettle();
    expect(terminal.writes, isEmpty);
    expect(find.byKey(const Key('ai-resume')), findsNothing);
    expect(scroll.offset, 0);
    await tester.tap(find.byKey(const Key('ai-show-latest')));
    await tester.pump();
    expect(scroll.position.extentAfter, lessThan(1));
    expect(
      find.text('Continuing with fresh context').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Composer Enter routes natural language to AI without shell execution',
    (tester) async {
      final shellWrites = <String>[];
      final prompts = <String>[];
      final controller = TerminalComposerController(
        targetId: 's',
        provider: (query, _) async => CompletionBatch(query, const []),
        submit: (submission) async {
          shellWrites.add(submission.query.value.text);
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(controller.dispose);
      controller.updateShell(
        contextKey: 'root',
        cwd: '/tmp',
        ownership: ComposerOwnership.ready,
        lease: 'lease',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalComposerView(
              controller: controller,
              targetLabel: 'Local',
              onAskAi: prompts.add,
              isNaturalLanguage: looksLikeNaturalLanguage,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        '请列出当前目录文件',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Ask AI'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(prompts, ['请列出当前目录文件']);
      expect(shellWrites, isEmpty);
      await tester.tap(find.byKey(const Key('composer-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('Submit this draft as a command'),
              matching: find.byWidgetPredicate(
                (widget) => widget is CheckedPopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'ls -la',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(shellWrites, ['ls -la']);
      expect(controller.ownership, ComposerOwnership.running);
      controller.editor.clear();
      controller.updateShell(
        contextKey: 'root',
        cwd: '/tmp',
        ownership: ComposerOwnership.ready,
        lease: 'next-lease',
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('composer-editor')), '解释下一步');
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.editor.text, '解释下一步');
      expect(
        find.text('Ask AI'),
        findsOneWidget,
        reason: 'Explicit command intent applies only to the previous draft',
      );
      expect(shellWrites, ['ls -la']);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'AI panel ${platform.name} ${brightness.name} at narrow width and large text',
        (tester) async {
          final settings = AiSettingsController(MemoryAiStore());
          await settings.loaded;
          final controller = TerminalAiController(
            settings: settings,
            terminal: FakeTerminal(),
            api: FakeApi(),
          );
          addTearDown(() {
            controller.dispose();
            settings.dispose();
          });
          await controller.ask('列出当前目录文件');
          await tester.pumpWidget(
            MaterialApp(
              theme: buildIanvsTerminalTheme(brightness, platform: platform),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Center(
                    child: SizedBox(
                      width: 320,
                      height: 260,
                      child: TerminalAiPanel(
                        controller: controller,
                        onClose: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('ai-task-status')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('ai-show-latest')).hitTestable(),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byKey(const Key('ai-approve')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('ai-reject')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('ai-reject')));
          await tester.pump();
          expect(controller.pending, isNull);
        },
      );
    }
  }

  testWidgets(
    'reopened conversation shows latest reply and preserves reading position',
    (tester) async {
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final api = FakeApi()
        ..respond = (step) async =>
            AiReply(text: 'Reply $step\n${'Output line\n' * 6}');
      final controller = TerminalAiController(
        settings: settings,
        terminal: FakeTerminal(),
        api: api,
      );
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });
      for (var i = 0; i < 8; i++) {
        await controller.ask('Explain result $i');
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                height: 360,
                child: TerminalAiPanel(controller: controller, onClose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final transcript = find
          .descendant(
            of: find.byType(TerminalAiPanel),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final scroll = tester
          .widget<SingleChildScrollView>(transcript)
          .controller!;
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.drag(transcript, const Offset(0, 180));
      await tester.pumpAndSettle();
      final readingOffset = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(80));
      await controller.refreshContext();
      await tester.pumpAndSettle();
      expect(scroll.offset, readingOffset);
    },
  );

  testWidgets(
    'settings saves mock endpoint, key and model through the real UI',
    (tester) async {
      final store = MemoryAiStore(null);
      final settings = AiSettingsController(store);
      await settings.loaded;
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAiSettings(context, settings),
                child: const Text('Configure'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-use-mock')));
      await tester.tap(find.byKey(const Key('ai-use-mock')));
      await tester.tap(find.byKey(const Key('ai-save-settings')));
      await tester.pumpAndSettle();
      expect(store.value!.endpoint, 'http://127.0.0.1:8787/v1');
      expect(store.value!.apiKey, 'trail-local-mock');
      expect(store.value!.model, 'trail-mock');
      final restored = AiSettingsController(store);
      await restored.loaded;
      expect(
        restored.configuration!.completionsUri.path,
        '/v1/chat/completions',
      );
      restored.dispose();
    },
  );
}

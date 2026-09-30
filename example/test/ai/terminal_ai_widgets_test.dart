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
              of: find.text('Always submit as a command'),
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

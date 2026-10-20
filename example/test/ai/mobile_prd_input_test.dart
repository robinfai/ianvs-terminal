import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class _Api extends FakeApi {}

class _Terminal extends FakeTerminal implements AiSubmissionInspector {
  bool unavailable = false;
  bool unknown = false;

  @override
  Future<AiTerminalContext> readContext() async {
    if (unavailable) throw const AiFailure('session_unavailable');
    return super.readContext();
  }

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    if (!unknown) return super.execute(action, expected, cancellation);
    cancellation.check();
    writes.add(action);
    throw const AiFailure('submission_unknown');
  }

  @override
  String? submissionFor(String actionId) => unknown ? 'original-receipt' : null;
  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async => {
    'status': 'unknown',
    'submission_id': id,
  };
}

class _Store extends MemoryAiStore {}

const _source = AiBlockContext(
  id: 'failed-source',
  command: 'cat /srv/应用/config.yaml',
  output: 'Permission denied',
  cwd: '/srv/应用',
  exitCode: 1,
  sourceSessionId: 'one',
  sourceContextId: 'root',
);

void main() {
  group('$TerminalAiWorkspace mobile PRD input', () {
    late AiSettingsController settings;
    late _Terminal terminal;
    late _Api api;
    late TerminalAiController controller;
    late int observations;
    late int takeovers;

    setUp(() async {
      settings = AiSettingsController(_Store());
      await settings.loaded;
      terminal = _Terminal();
      api = _Api()..respond = (_) async => const AiReply(text: 'Reviewed.');
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
      await controller.refreshContext();
      observations = 0;
      takeovers = 0;
    });
    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    Future<void> mount(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      Brightness brightness = Brightness.light,
      Locale locale = const Locale('en'),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        TerminalAiWorkspace(
          controller: controller,
          targetLabel: 'ops@staging.example.test',
          onClose: () => takeovers++,
          onObserveTerminal: () => observations++,
        ),
        platform: TargetPlatform.iOS,
        brightness: brightness,
        locale: locale,
      );
      await tester.pumpAndSettle();
    }

    TextEditingController input(WidgetTester tester, {bool expanded = false}) =>
        tester
            .widget<TextField>(
              find.byKey(Key(expanded ? 'composer-draft-editor' : 'ai-prompt')),
            )
            .controller!;

    testWidgets(
      'software Return and composing hardware Enter do not submit a task',
      (tester) async {
        controller.setDraft('解释这个输出');
        await mount(tester);
        try {
          await tester.showKeyboard(find.byKey(const Key('ai-prompt')));
          await tester.testTextInput.receiveAction(TextInputAction.newline);
          await tester.pump();
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
          input(tester).value = const TextEditingValue(
            text: '解释这个输出拼音',
            selection: TextSelection.collapsed(offset: 8),
            composing: TextRange(start: 6, end: 8),
          );
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
          expect(takeovers, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'Done saves exact text and selection while attachments remain unsent',
      (tester) async {
        controller.setDraft('保留原稿\n原始路径 🧭');
        controller.attachContext(_source);
        await mount(tester);
        try {
          input(tester).selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 6,
          );
          final original = input(tester).value;
          await tester.tap(find.byKey(const Key('ai-expand-draft')));
          await tester.pumpAndSettle();
          expect(input(tester, expanded: true).selection, original.selection);
          const edited = TextEditingValue(
            text: '新的要求\n保留换行\\与路径 /srv/应用\n🧭',
            selection: TextSelection(baseOffset: 4, extentOffset: 9),
          );
          input(tester, expanded: true).value = edited;
          await tester.pump();
          expect(controller.draft, original.text);
          await tester.tap(find.byKey(const Key('composer-draft-done')));
          await tester.pumpAndSettle();
          expect(input(tester).value, edited);
          expect(controller.draft, edited.text);
          expect(controller.attachments, [_source]);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'Cancel and Escape discard local edits without crossing into takeover',
      (tester) async {
        controller.setDraft('Original\n草稿');
        await mount(tester);
        try {
          input(tester).selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          final original = input(tester).value;
          for (final escape in [false, true]) {
            await tester.tap(find.byKey(const Key('ai-expand-draft')));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('composer-draft-editor')),
              'discard temporary edit',
            );
            if (escape) {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            } else {
              await tester.tap(find.byKey(const Key('composer-draft-cancel')));
            }
            await tester.pumpAndSettle();
            expect(input(tester).value, original);
          }
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
          expect(observations, 0);
          expect(takeovers, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final stale in ['ABA edit', 'task switch']) {
      testWidgets('does not apply a full-screen result after $stale', (
        tester,
      ) async {
        controller.setDraft('Original');
        await mount(tester);
        try {
          await tester.tap(find.byKey(const Key('ai-expand-draft')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('composer-draft-editor')),
            'stale edit',
          );
          if (stale == 'ABA edit') {
            controller.setDraft('Changed');
            controller.setDraft('Original');
          } else {
            controller.newTask();
            controller.setDraft('New task draft');
          }
          final expected = controller.draft;
          await tester.pump();
          await tester.tap(find.byKey(const Key('composer-draft-done')));
          await tester.pump();
          expect(find.byKey(const Key('composer-draft-page')), findsOneWidget);
          expect(controller.draft, expected);
          await tester.tap(find.byKey(const Key('composer-draft-cancel')));
          await tester.pumpAndSettle();
          expect(input(tester).text, expected);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    testWidgets(
      'source details insert a diagnosis at the caret without replacing or sending the existing draft',
      (tester) async {
        controller.setDraft('Keep this suffix');
        controller.attachContext(_source);
        await mount(tester);
        try {
          input(tester).selection = const TextSelection.collapsed(offset: 4);
          await tester.tap(find.byKey(const Key('ai-pending-contexts')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('ai-insert-diagnosis-failed-source')),
          );
          await tester.pumpAndSettle();
          expect(
            controller.draft,
            startsWith('Keep\nExplain why this command failed'),
          );
          expect(controller.draft, endsWith(' this suffix'));
          expect(controller.draft, contains(_source.command));
          expect(controller.attachments, [_source]);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'shows Add requirement during a turn and keeps attached Command unavailable',
      (tester) async {
        late Completer<AiReply> gate;
        late Future<void> turn;
        await tester.runAsync(() async {
          gate = Completer<AiReply>();
          api.respond = (_) => gate.future;
          turn = controller.ask('Inspect this terminal');
          await Future<void>.delayed(Duration.zero);
        });
        await mount(tester);
        try {
          controller.attachContext(_source);
          controller.setDraft('Keep the original files');
          await tester.pump();
          expect(find.text('Add requirement'), findsOneWidget);
          expect(find.text('Auto · AI'), findsOneWidget);
          await tester.tap(find.byKey(const Key('ai-input-intent')));
          await tester.pumpAndSettle();
          final command = find.widgetWithText(
            CheckedPopupMenuItem<InputIntentChoice>,
            'Command · remove sources first',
          );
          await tester.tap(command);
          await tester.pump();
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          expect(terminal.writes, isEmpty);
        } finally {
          await tester.runAsync(() async {
            gate.complete(const AiReply(text: 'Finished.'));
            await turn;
          });
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'a 320-wide source row keeps a separate 44-point deletion target without opening inspection',
      (tester) async {
        controller.attachContext(_source);
        controller.setDraft('Explain this failure');
        await mount(tester, size: const Size(320, 600));
        try {
          for (final corner in const [
            Offset(-20, -20),
            Offset(20, -20),
            Offset(-20, 20),
            Offset(20, 20),
          ]) {
            if (controller.attachments.isEmpty) {
              controller.attachContext(_source);
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final chip = find.byType(InputChip);
            expect(chip, findsOneWidget);
            expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
            final icon = find.byKey(
              const ValueKey('ai-context-delete-failed-source'),
            );
            await tester.tapAt(tester.getCenter(icon) + corner);
            await tester.pumpAndSettle();
            expect(controller.attachments, isEmpty);
            expect(find.byType(AlertDialog), findsNothing);
            expect(controller.draft, 'Explain this failure');
          }
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final height in [95.0, 40.0]) {
      testWidgets(
        'keeps full controls and source direction reachable at height $height',
        (tester) async {
          controller.attachContext(_source);
          controller.setDraft('Keep this draft');
          await mount(tester, size: Size(320, height));
          try {
            expect(tester.takeException(), isNull);
            final hide = find.byKey(const Key('ai-dismiss-keyboard'));
            expect(tester.getSize(hide).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(hide).height, greaterThanOrEqualTo(44));
            await tester.tap(hide);
            await tester.pump();
            final sources = find.byKey(const Key('ai-pending-contexts'));
            await tester.ensureVisible(sources);
            await tester.pumpAndSettle();
            expect(find.text('Auto · AI'), findsOneWidget);
            expect(tester.getSize(sources).height, greaterThanOrEqualTo(44));
            final observe = find.byKey(const Key('ai-observe-terminal'));
            await tester.ensureVisible(observe);
            await tester.pumpAndSettle();
            await tester.tap(observe);
            await tester.pump();
            expect(observations, 1);
            expect(takeovers, 0);
            expect(controller.draft, 'Keep this draft');
            expect(controller.attachments, [_source]);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }

    testWidgets('target change supersedes the withdrawn proposal status', (
      tester,
    ) async {
      api.respond = (_) async => commandReply('pwd');
      await tester.runAsync(() => controller.ask('Inspect the original host'));
      await mount(tester);
      try {
        expect(controller.canApprove, isTrue);
        terminal.context = const AiTerminalContext(
          sessionId: 'two',
          contextId: 'other',
          guard: 'two:root',
          screen: 'remote> ',
          cwd: '/srv/new-target',
          canRunCommand: true,
        );
        await tester.runAsync(controller.refreshContext);
        await tester.pump();
        expect(controller.targetChanged, isTrue);
        expect(
          tester.widget<Text>(find.byKey(const Key('ai-task-status'))).data,
          'Target changed · choose where to continue',
        );
        expect(controller.canApprove, isFalse);
        expect(terminal.writes, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'an unknown receipt remains the headline when its connection also fails',
      (tester) async {
        api.respond = (_) async => commandReply('pwd');
        terminal.unknown = true;
        await tester.runAsync(() async {
          await controller.ask('Inspect once');
          await controller.approve();
          terminal.unavailable = true;
          await controller.refreshContext();
        });
        await mount(tester);
        try {
          expect(controller.hasUnresolvedSubmission, isTrue);
          expect(controller.terminalError, 'session_unavailable');
          expect(
            tester.widget<Text>(find.byKey(const Key('ai-task-status'))).data,
            'Submission unknown · check original receipt',
          );
          expect(find.byKey(const Key('ai-check-terminal')), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('ai-send')))
                .onPressed,
            isNull,
          );
          expect(terminal.writes, hasLength(1));
          expect(controller.canApprove, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final size in [
      const Size(320, 600),
      const Size(390, 844),
      const Size(844, 145),
      const Size(844, 95),
      const Size(320, 145),
    ]) {
      for (final brightness in Brightness.values) {
        for (final locale in [const Locale('en'), const Locale('zh')]) {
          testWidgets(
            'preserves multiline input and reaches expanded editing at $size $brightness $locale',
            (tester) async {
              controller.setDraft(
                'Explain the failure\n保留原始日志\nRead /srv/应用/config.yaml\nOnly inspect\nDo not execute',
              );
              controller.attachContext(_source);
              final draft = controller.draft;
              await mount(
                tester,
                size: size,
                brightness: brightness,
                locale: locale,
              );
              try {
                expect(controller.draft, draft);
                expect(tester.takeException(), isNull);
                final expand = find.byKey(const Key('ai-expand-draft'));
                expect(tester.getSize(expand).height, greaterThanOrEqualTo(44));
                await tester.tap(expand);
                await tester.pumpAndSettle();
                expect(input(tester, expanded: true).text, draft);
                expect(tester.takeException(), isNull);
                await tester.tap(
                  find.byKey(const Key('composer-draft-cancel')),
                );
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const Key('composer-draft-page')),
                  findsNothing,
                );
                expect(controller.draft, draft);
                expect(controller.attachments, [_source]);
                expect(api.requests, isEmpty);
                expect(terminal.writes, isEmpty);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
              }
            },
          );
        }
      }
    }
  });
}

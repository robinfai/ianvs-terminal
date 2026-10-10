import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/previews/mobile_prd_component_previews.dart';
import 'package:app/ui/previews/terminal_ai_workspace_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final phone in [false, true]) {
    testWidgets('workspace preview collapse retains the task (phone=$phone)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = phone
          ? const Size(390, 844)
          : const Size(1000, 760);
      addTearDown(tester.view.reset);
      try {
        await tester.runAsync(() async {
          await tester.pumpWidget(AiWorkspacePreview(phone: phone));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        final task = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller;
        expect(task.canApprove, isTrue);
        final taskId = task.taskId;
        final pending = task.pending;
        final transcript = task.transcript.toList();
        await tester.enterText(
          find.byKey(const Key('ai-prompt')),
          '保留这段尚未发送的补充要求',
        );
        await tester.tap(find.byKey(const Key('ai-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-preview-observation')), findsOneWidget);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(task.takenOver, isFalse);
        expect(task.pending, same(pending));
        expect(task.transcript, transcript);
        expect(task.draft, '保留这段尚未发送的补充要求');

        await tester.tap(find.byKey(const Key('ai-preview-return')));
        await tester.pumpAndSettle();
        final reopened = tester.widget<TerminalAiWorkspace>(
          find.byType(TerminalAiWorkspace),
        );
        expect(reopened.controller, same(task));
        expect(task.taskId, taskId);
        expect(task.pending, same(pending));
        expect(task.canApprove, isTrue);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ai-prompt')))
              .controller!
              .text,
          '保留这段尚未发送的补充要求',
        );
        if (!phone) {
          await tester.tap(find.byKey(const Key('ai-close')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('command-block-preview-failure')),
              matching: find.text('ls --bad'),
            ),
          );
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(TerminalAiWorkspace), findsOneWidget);
          expect(task.draft, 'ls --bad');
          expect(task.pending, same(pending));
          expect(task.transcript, transcript);
          expect(task.takenOver, isFalse);
          expect(task.canApprove, isTrue);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('component preview collapse preserves a pending proposal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 640);
    addTearDown(tester.view.reset);
    try {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MobilePrdComponentPreview(
            component: MobilePrdPreviewComponent.taskHeader,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      final task = tester
          .widget<TerminalAiComponentPreview>(
            find.byType(TerminalAiComponentPreview),
          )
          .controller;
      await tester.runAsync(() => task.ask('Inspect without modifying files.'));
      await tester.pumpAndSettle();
      expect(task.canApprove, isTrue);
      final pending = task.pending;
      final transcript = task.transcript.toList();
      await tester.tap(find.byKey(const Key('ai-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-preview-observation')), findsOneWidget);
      expect(task.pending, same(pending));
      expect(task.transcript, transcript);
      expect(task.takenOver, isFalse);
      await tester.tap(find.byKey(const Key('ai-preview-return')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TerminalAiComponentPreview>(
              find.byType(TerminalAiComponentPreview),
            )
            .controller,
        same(task),
      );
      expect(task.canApprove, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

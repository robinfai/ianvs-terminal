import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  for (final chinese in [false, true]) {
    testWidgets(
      '${chinese ? 'Chinese' : 'English'} primary action announces its current disabled cause',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var submissions = 0;
        final model = TerminalComposerController(
          targetId: 'semantic-test',
          text: '',
          debounce: const Duration(days: 1),
          provider: (query, _) async => CompletionBatch(query, const []),
          submit: (_) async {
            submissions++;
            return ComposerSubmissionOutcome.accepted;
          },
        );
        addTearDown(model.dispose);
        void shell(ComposerOwnership ownership) => model.updateShell(
          contextKey: ownership.name,
          cwd: '/tmp',
          dialect: 'zsh',
          ownership: ownership,
          lease: ownership == ComposerOwnership.ready ? 'ready' : null,
        );
        shell(ComposerOwnership.ready);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: TerminalComposerView(
                    controller: model,
                    targetLabel: 'Local Shell',
                    chinese: chinese,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(const Key('composer-primary-action'));
          void disabled(String label, String reason) {
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.label, label);
            expect(data.hint, reason);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
            expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
          }

          disabled(
            chinese ? '执行' : 'Run',
            chinese ? '请输入完整命令后执行' : 'Enter a complete command to run',
          );
          model.editor.text = 'echo ready';
          shell(ComposerOwnership.submitting);
          // Submission intentionally keeps its progress indicator animating.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          disabled(
            chinese ? '发送中' : 'Sending',
            chinese ? '等待 Shell 恢复就绪' : 'Wait for the shell to be ready',
          );
          expect(model.editor.text, 'echo ready');
          expect(submissions, 0);

          shell(ComposerOwnership.ready);
          await tester.pumpAndSettle();
          final data = tester.getSemantics(button).getSemanticsData();
          expect(data.label, chinese ? '执行' : 'Run');
          expect(data.hint, chinese ? '执行命令 · Enter' : 'Run command · Enter');
          expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          tester.semantics.tap(find.semantics.byLabel(chinese ? '执行' : 'Run'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(submissions, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

TerminalComposerController _controller({
  CompletionProvider? provider,
  ComposerSubmit? submit,
}) =>
    TerminalComposerController(
      targetId: 'pane',
      text: 'echo draft',
      provider:
          provider ?? (query, _) async => CompletionBatch(query, const []),
      submit: submit ?? (_) async => ComposerSubmissionOutcome.accepted,
    )..updateShell(
      contextKey: 'ready',
      cwd: '/tmp',
      lease: 'lease',
      ownership: ComposerOwnership.ready,
    );

void main() {
  test('active notifications remain synchronous by default', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setActive(false);

    expect(controller.canRun, isFalse);
    expect(notifications, 1);
  });

  testWidgets(
    'deferred notification immediately revokes input and pending completion',
    (tester) async {
      final completion = Completer<CompletionBatch>();
      late CompletionCancellation cancellation;
      late CompletionQuery query;
      var submissions = 0;
      final controller = _controller(
        provider: (value, token) {
          query = value;
          cancellation = token;
          return completion.future;
        },
        submit: (_) async {
          submissions++;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      try {
        controller.completeOnTab();
        expect(controller.loading, isTrue);
        var notifications = 0;
        controller.addListener(() => notifications++);

        controller.setActive(false, deferNotification: true);

        expect(cancellation.isCancelled, isTrue);
        expect(controller.loading, isFalse);
        expect(controller.canRun, isFalse);
        expect(controller.primaryAction, ComposerPrimaryAction.disabled);
        expect(controller.editor.text, 'echo draft');
        expect(notifications, 0);
        await controller.run();
        expect(submissions, 0);

        // Multiple availability changes in one build produce one latest-state event.
        controller.setActive(true, deferNotification: true);
        controller.setActive(false, deferNotification: true);
        expect(notifications, 0);
        await tester.pump();
        expect(notifications, 1);

        completion.complete(
          CompletionBatch(query, [
            CompletionEdit(
              itemId: 'late',
              label: 'echo late',
              detail: 'Late candidate',
              kind: 'command',
              source: 'test',
              start: 0,
              end: query.value.text.length,
              newText: 'echo late',
              cursor: 9,
            ),
          ]),
        );
        await tester.pump();
        expect(controller.items, isEmpty);
        expect(controller.editor.text, 'echo draft');
        expect(submissions, 0);
      } finally {
        controller.dispose();
        if (!completion.isCompleted) {
          completion.complete(CompletionBatch(query, const []));
        }
        await tester.pump();
      }
    },
  );

  testWidgets('deferred active notification does not outlive its controller', (
    tester,
  ) async {
    final controller = _controller();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.setActive(false, deferNotification: true);
    controller.dispose();

    await tester.pump();

    expect(notifications, 0);
    expect(tester.takeException(), isNull);
  });
}

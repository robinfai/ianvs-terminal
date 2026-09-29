import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

CompletionEdit completion({
  int start = 4,
  int end = 7,
  String text = 'checkout',
}) => CompletionEdit(
  itemId: '$start:$end:$text',
  label: text,
  detail: 'Switch branches',
  kind: 'subcommand',
  source: 'fig:git',
  start: start,
  end: end,
  newText: text,
  cursor: start + text.length,
);

TerminalComposerController create({
  CompletionProvider? provider,
  ComposerSubmit? submit,
  String text = 'git che --help',
}) => TerminalComposerController(
  targetId: 'session-a',
  text: text,
  debounce: const Duration(milliseconds: 10),
  provider:
      provider ??
      (query, cancellation) async => CompletionBatch(query, [completion()]),
  submit: submit,
);

void ready(TerminalComposerController controller) => controller.updateShell(
  contextKey: 'prompt-1',
  cwd: '/tmp/project',
  ownership: ComposerOwnership.ready,
  lease: 'lease-1',
  dialect: 'zsh',
);

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  test(
    'policy and lifecycle changes cancel providers and keep sessions local',
    () async {
      var calls = 0;
      CompletionCancellation? firstCancellation;
      final controller = create(
        provider: (q, cancellation) async {
          calls++;
          firstCancellation ??= cancellation;
          return CompletionBatch(q, [completion()]);
        },
      );
      addTearDown(controller.dispose);
      ready(controller);
      controller.requestCompletions();
      await drain();
      final before = controller.snapshot;
      controller.toggleLocalSuggestions();
      expect(
        controller.snapshot.policyRevision,
        greaterThan(before.policyRevision),
      );
      controller.publishCompletions(
        CompletionBatch(before, [completion()]),
        cancellation: firstCancellation!,
      );
      expect(controller.items, isEmpty);
      controller.updateShell(
        contextKey: 'busy',
        cwd: '/tmp/project',
        ownership: ComposerOwnership.running,
      );
      await drain();
      final priorCalls = calls;
      controller.requestCompletions();
      await drain();
      expect(calls, priorCalls);
      expect(controller.items, isEmpty);
      controller.setActive(false);
      ready(controller);
      expect(controller.canRun, isFalse);
    },
  );

  test(
    'incremental batches preserve selection by stable item identity',
    () async {
      late CompletionCancellation cancellation;
      final gate = Completer<CompletionBatch>();
      final controller = create(
        provider: (q, c) {
          cancellation = c;
          return gate.future;
        },
      );
      addTearDown(controller.dispose);
      final query = controller.snapshot;
      final selected = completion();
      controller.requestCompletions();
      controller.publishCompletions(
        CompletionBatch(query, [selected]),
        cancellation: cancellation,
      );
      controller.selectNext(1);
      controller.publishCompletions(
        CompletionBatch(query, [completion(text: 'branch'), selected]),
        cancellation: cancellation,
      );
      expect(controller.selectedIndex, 1);
      gate.complete(CompletionBatch(query, controller.items));
      await drain();
    },
  );

  test(
    'dismissed incremental batches stay closed across an identical query',
    () async {
      final gates = <Completer<CompletionBatch>>[];
      final cancellations = <CompletionCancellation>[];
      final controller = create(
        provider: (q, c) {
          cancellations.add(c);
          final gate = Completer<CompletionBatch>();
          gates.add(gate);
          return gate.future;
        },
      );
      addTearDown(controller.dispose);
      final query = controller.snapshot;
      final batch = CompletionBatch(query, [completion()]);
      controller.requestCompletions();
      controller.publishCompletions(batch, cancellation: cancellations.first);
      expect(controller.items, isNotEmpty);
      controller.dismissCompletions();
      controller.publishCompletions(batch, cancellation: cancellations.first);
      expect(controller.items, isEmpty);
      gates.first.complete(batch);
      await drain();
      controller.requestCompletions();
      controller.publishCompletions(batch, cancellation: cancellations.first);
      expect(controller.items, isEmpty);
      controller.publishCompletions(batch, cancellation: cancellations.last);
      expect(controller.items, isNotEmpty);
      gates.last.complete(batch);
      await drain();
      expect(cancellations.last.isCancelled, isTrue);
    },
  );

  test(
    'middle token edit preserves suffix and undo restores selection',
    () async {
      final controller = create();
      addTearDown(controller.dispose);
      controller.editor.selection = const TextSelection.collapsed(offset: 7);
      controller.requestCompletions();
      await drain();
      controller.selectNext(1);
      expect(controller.accept(), isTrue);
      expect(controller.editor.text, 'git checkout --help');
      controller.undo();
      expect(controller.editor.text, 'git che --help');
      expect(controller.editor.selection.extentOffset, 7);
    },
  );

  test('same text cursor movement rejects old result', () async {
    final gate = Completer<CompletionBatch>();
    late CompletionQuery captured;
    final controller = create(
      provider: (q, _) {
        captured = q;
        return gate.future;
      },
    );
    addTearDown(controller.dispose);
    controller.requestCompletions();
    controller.editor.selection = const TextSelection.collapsed(offset: 4);
    gate.complete(CompletionBatch(captured, [completion()]));
    await drain();
    expect(controller.items, isEmpty);
  });

  test(
    'context change invalidates a displayed candidate on acceptance',
    () async {
      final controller = create();
      addTearDown(controller.dispose);
      controller.requestCompletions();
      await drain();
      final item = controller.items.first;
      ready(controller);
      expect(controller.accept(item), isFalse);
      expect(controller.editor.text, 'git che --help');
    },
  );

  test('composition and noncollapsed selection do not query', () async {
    var queries = 0;
    final controller = create(
      provider: (q, _) async {
        queries++;
        return CompletionBatch(q, const []);
      },
    );
    addTearDown(controller.dispose);
    controller.editor.value = const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    controller.requestCompletions();
    await drain();
    expect(queries, 0);
    controller.editor.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection(baseOffset: 5, extentOffset: 1),
    );
    controller.requestCompletions();
    expect(queries, 0);
  });

  test(
    'surrogate and grapheme splits and controls are refused without clamping',
    () async {
      for (final edit in [
        completion(start: 1, end: 2),
        completion(start: 0, end: 99),
        completion(start: 0, end: 2, text: '\x1b[31m'),
      ]) {
        final controller = create(
          text: '😀é',
          provider: (q, _) async => CompletionBatch(q, [edit]),
        );
        controller.requestCompletions();
        await drain();
        expect(controller.accept(controller.items.first), isFalse);
        expect(controller.editor.text, '😀é');
        controller.dispose();
      }
    },
  );

  test(
    'latest-wins queue holds only newest snapshot and cancels producer',
    () async {
      final gates = <Completer<CompletionBatch>>[];
      final queries = <CompletionQuery>[];
      final cancellations = <CompletionCancellation>[];
      final controller = create(
        provider: (q, c) {
          queries.add(q);
          cancellations.add(c);
          final gate = Completer<CompletionBatch>();
          gates.add(gate);
          return gate.future;
        },
      );
      addTearDown(controller.dispose);
      controller.requestCompletions();
      for (final text in ['git a', 'git b', 'git c']) {
        controller.editor.text = text;
        controller.editor.selection = TextSelection.collapsed(
          offset: text.length,
        );
        controller.requestCompletions();
      }
      expect(cancellations.first.isCancelled, isTrue);
      expect(queries.length, 1);
      gates.first.complete(CompletionBatch(queries.first, [completion()]));
      await drain();
      expect(queries.length, 2);
      expect(queries.last.value.text, 'git c');
      gates.last.complete(CompletionBatch(queries.last, const []));
      await drain();
    },
  );

  test(
    'late accepted submission cannot clear a newer draft; no double submit',
    () async {
      final gate = Completer<ComposerSubmissionOutcome>();
      var submits = 0;
      final controller = create(
        submit: (_) {
          submits++;
          return gate.future;
        },
      );
      addTearDown(controller.dispose);
      ready(controller);
      final pending = controller.run();
      await controller.run();
      controller.editor.text = 'next draft';
      gate.complete(ComposerSubmissionOutcome.accepted);
      await pending;
      expect(submits, 1);
      expect(controller.editor.text, 'next draft');
    },
  );

  test(
    'rejection and unknown outcomes preserve draft and never auto retry',
    () async {
      for (final outcome in [
        ComposerSubmissionOutcome.rejected,
        ComposerSubmissionOutcome.unknown,
      ]) {
        var submits = 0;
        final controller = create(
          submit: (_) async {
            submits++;
            return outcome;
          },
        );
        ready(controller);
        await controller.run();
        await controller.run();
        expect(controller.editor.text, 'git che --help');
        expect(submits, 1);
        if (outcome == ComposerSubmissionOutcome.unknown) {
          ready(controller);
          expect(controller.canRun, isFalse);
          controller.recoverDraft();
          expect(submits, 1);
        }
        controller.dispose();
      }
    },
  );

  test('sessions own independent drafts and revisions', () {
    final a = create(text: 'a');
    final b = create(text: 'b');
    expect(a.sessionEpoch, isNot(b.sessionEpoch));
    a.editor.text = 'edited';
    expect(b.editor.text, 'b');
    a.dispose();
    b.dispose();
  });

  test('batch rejects unknown fields, wrong identity and excessive items', () {
    final controller = create();
    addTearDown(controller.dispose);
    final query = controller.snapshot;
    final json = <String, Object?>{
      'schemaVersion': 1,
      'query': query.toJson(),
      'status': 'ok',
      'items': <Object?>[],
    };
    expect(CompletionBatch.fromJson(query, json).items, isEmpty);
    expect(
      () => CompletionBatch.fromJson(query, {...json, 'extra': true}),
      throwsFormatException,
    );
    expect(
      () => CompletionBatch.fromJson(query, {
        ...json,
        'query': <String, Object?>{...query.toJson(), 'sessionEpoch': 100},
      }),
      throwsFormatException,
    );
  });

  Future<void> show(
    WidgetTester tester,
    TerminalComposerController controller, {
    double width = 700,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 650),
              textScaler: TextScaler.linear(scale),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TerminalComposerView(
                  controller: controller,
                  targetLabel: 'Local · zsh',
                  autofocus: true,
                  onUseTerminal: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('Tab completion', () {
    test('local IO is scoped to the live Tab request', () async {
      final permissions = <bool>[];
      final cancellations = <CompletionCancellation>[];
      late TerminalComposerController controller;
      controller = create(
        text: 'ls ./',
        provider: (query, cancellation) async {
          permissions.add(controller.allowsLocalSuggestions(cancellation));
          cancellations.add(cancellation);
          return CompletionBatch(query, const []);
        },
      );
      addTearDown(controller.dispose);
      ready(controller);
      controller.requestCompletions();
      await drain();
      controller.completeOnTab();
      await drain();
      expect(permissions, [false, true]);
      expect(controller.localSuggestions, isFalse);
      expect(controller.status, 'no_completions');
      expect(controller.allowsLocalSuggestions(cancellations.last), isFalse);
      controller.editor.value = const TextEditingValue(
        text: 'ls ./d',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(controller.status, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(permissions, [false, true, false]);
      controller.toggleLocalSuggestions();
      await drain();
      expect(permissions, [false, true, false, true]);
    });

    for (final change in ['edit', 'dismiss', 'context', 'inactive']) {
      test('late Tab result is discarded after $change', () async {
        final gate = Completer<CompletionBatch>();
        late CompletionCancellation cancellation;
        final controller = create(
          text: 'ls ./',
          provider: (query, token) {
            cancellation = token;
            return gate.future;
          },
        );
        addTearDown(controller.dispose);
        ready(controller);
        final query = controller.snapshot;
        controller.completeOnTab();
        expect(controller.allowsLocalSuggestions(cancellation), isTrue);
        switch (change) {
          case 'edit':
            controller.editor.value = const TextEditingValue(
              text: 'ls ./new',
              selection: TextSelection.collapsed(offset: 8),
            );
          case 'dismiss':
            controller.dismissCompletions();
          case 'context':
            controller.updateShell(
              contextKey: 'prompt-2',
              cwd: '/tmp/other',
              ownership: ComposerOwnership.ready,
              lease: 'lease-2',
              dialect: 'zsh',
            );
          case 'inactive':
            controller.setActive(false);
        }
        expect(controller.allowsLocalSuggestions(cancellation), isFalse);
        gate.complete(
          CompletionBatch(query, [
            completion(start: 3, end: 5, text: './documents/'),
          ]),
        );
        await drain();
        expect(controller.editor.text, change == 'edit' ? 'ls ./new' : 'ls ./');
        expect(controller.items, isEmpty);
      });
    }

    testWidgets(
      'fills a unique directory without running or enabling automatic IO',
      (tester) async {
        var submissions = 0;
        final controller = create(
          text: 'ls ./',
          provider: (q, _) async => CompletionBatch(q, [
            completion(start: 3, end: 5, text: './documents/'),
          ]),
          submit: (_) async {
            submissions++;
            return ComposerSubmissionOutcome.accepted;
          },
        );
        addTearDown(controller.dispose);
        ready(controller);
        await show(tester, controller);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(controller.editor.text, 'ls ./documents/');
        expect(controller.localSuggestions, isFalse);
        expect(submissions, 0);
        expect(controller.ownership, ComposerOwnership.ready);
      },
    );

    testWidgets(
      'multiple directories open for selection; held Tab does not accept',
      (tester) async {
        var calls = 0;
        final controller = create(
          text: 'ls ./',
          provider: (q, _) async {
            calls++;
            return CompletionBatch(q, [
              completion(start: 3, end: 5, text: './documents/'),
              completion(start: 3, end: 5, text: './downloads/'),
            ]);
          },
        );
        addTearDown(controller.dispose);
        ready(controller);
        await show(tester, controller);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(controller.editor.text, 'ls ./');
        expect(controller.selectedIndex, 0);
        expect(find.text('./documents/'), findsOneWidget);
        expect(find.text('./downloads/'), findsOneWidget);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        expect(controller.editor.text, 'ls ./');
        expect(calls, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(controller.editor.text, 'ls ./downloads/');
        expect(controller.localSuggestions, isFalse);
        expect(controller.ownership, ComposerOwnership.ready);
      },
    );

    testWidgets(
      'Tab waits for local alternatives before accepting a static match',
      (tester) async {
        final gate = Completer<CompletionBatch>();
        var calls = 0;
        late CompletionCancellation cancellation;
        final controller = create(
          text: 'ls ./',
          provider: (q, token) {
            calls++;
            cancellation = token;
            return gate.future;
          },
        );
        addTearDown(controller.dispose);
        ready(controller);
        await show(tester, controller);
        final query = controller.snapshot;
        final first = completion(start: 3, end: 5, text: './documents/');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        controller.publishCompletions(
          CompletionBatch(query, [first]),
          cancellation: cancellation,
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(controller.editor.text, 'ls ./');
        expect(calls, 1);
        gate.complete(
          CompletionBatch(query, [
            first,
            completion(start: 3, end: 5, text: './downloads/'),
          ]),
        );
        await tester.pumpAndSettle();
        expect(controller.editor.text, 'ls ./');
        expect(controller.items, hasLength(2));
        expect(controller.selectedIndex, 0);
      },
    );
  });

  testWidgets(
    'Enter accepts selected completion only; next Enter submits once',
    (tester) async {
      var submits = 0;
      final controller = create(
        text: 'git che',
        submit: (_) async {
          submits++;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(controller.dispose);
      ready(controller);
      await show(tester, controller);
      controller.requestCompletions();
      await tester.pump();
      controller.selectNext(1);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.editor.text, 'git checkout');
      expect(submits, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 1);
    },
  );

  testWidgets('Shift Enter and IME Enter never submit', (tester) async {
    var submits = 0;
    final controller = create(
      text: 'echo hi',
      submit: (_) async {
        submits++;
        return ComposerSubmissionOutcome.accepted;
      },
    );
    addTearDown(controller.dispose);
    ready(controller);
    await show(tester, controller);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.editor.text, 'echo hi\n');
    controller.editor.value = const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submits, 0);
  });

  testWidgets('keyboard selection stays visible in scaled mixed-height lists', (
    tester,
  ) async {
    final controller = create(
      provider: (query, _) async => CompletionBatch(query, [
        for (var i = 0; i < 60; i++)
          CompletionEdit(
            itemId: 'choice-$i',
            label: 'choice-$i',
            detail: i.isEven ? 'Description' : '',
            kind: 'option',
            source: 'fixture',
            start: 4,
            end: 7,
            newText: 'choice-$i',
            cursor: 4 + 'choice-$i'.length,
          ),
      ]),
    );
    addTearDown(controller.dispose);
    await show(tester, controller, width: 340, scale: 2);
    controller.requestCompletions();
    await tester.pumpAndSettle();
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 39);
    expect(find.text('choice-39').hitTestable(), findsOneWidget);
    for (var i = 0; i < 21; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 18);
    expect(find.text('choice-18').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'compact ${brightness.name} supports 2x text without overflow',
      (tester) async {
        final controller = create(text: 'echo 你好😀\nsecond line');
        addTearDown(controller.dispose);
        ready(controller);
        await show(
          tester,
          controller,
          width: 340,
          scale: 2,
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('composer-editor')), findsOneWidget);
      },
    );
  }
}

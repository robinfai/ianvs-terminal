import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

TerminalComposerController create({String text = '', ComposerSubmit? submit}) =>
    TerminalComposerController(
      targetId: 'history-session',
      text: text,
      debounce: const Duration(milliseconds: 10),
      provider: (query, _) async => CompletionBatch(query, const []),
      submit: submit,
    )..updateShell(
      contextKey: 'prompt',
      cwd: '/tmp',
      dialect: 'zsh',
      ownership: ComposerOwnership.ready,
      lease: 'lease',
    );

Future<void> show(
  WidgetTester tester,
  TerminalComposerController model, {
  double width = 800,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 650));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TerminalComposerView(
              controller: model,
              targetLabel: 'Local · zsh',
              autofocus: true,
              onUseTerminal: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test(
    'history filters, deduplicates and restores the exact draft and undo',
    () {
      final model = create(text: 'git');
      addTearDown(model.dispose);
      model.editor.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      final draft = model.editor.value;
      model.updateHistory([
        'git checkout composer',
        'echo hi',
        'git status',
        'git status',
        ' secret',
        'echo\u001b[0m',
      ]);
      model.openHistory();
      expect(model.historyItems, ['git status', 'git checkout composer']);
      expect(model.historySelectedIndex, 1);
      model.editor.value = const TextEditingValue(
        text: 'STATUS GIT',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(model.historyItems, ['git status']);
      model.dismissHistory();
      expect(model.editor.value, draft);
      model.openHistory();
      model.selectHistory(-1);
      expect(model.acceptHistory(), isTrue);
      expect(model.editor.text, 'git status');
      expect(model.ownership, ComposerOwnership.ready);
      model.undo();
      expect(model.editor.value, draft);
    },
  );

  test('history is pane scoped and down past newest restores the draft', () {
    final a = create(text: 'git');
    final b = create(text: 'git');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.updateHistory(['git status']);
    a.openHistory();
    b.openHistory();
    expect(b.historyItems, isEmpty);
    a.selectHistory(1);
    expect(a.historyOpen, isFalse);
    expect(a.editor.text, 'git');
    a.openHistory();
    a.editor.text = 'filter';
    a.setActive(false);
    expect(a.editor.text, 'git');
    expect(a.inlineSuggestion, isEmpty);
  });

  test(
    'ghost text never enters submission and hides for selections, IME and context',
    () async {
      ComposerSubmission? sent;
      final model = create(
        text: 'git',
        submit: (s) async {
          sent = s;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      model.updateHistory(['git checkout composer']);
      expect(model.inlineSuggestion, ' checkout composer');
      model.editor.selection = const TextSelection.collapsed(offset: 1);
      expect(model.inlineSuggestion, isEmpty);
      model.editor.value = const TextEditingValue(
        text: 'git',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      expect(model.inlineSuggestion, isEmpty);
      model.editor.value = const TextEditingValue(
        text: 'git',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(model.inlineSuggestion, isEmpty);
      model.editor.selection = const TextSelection.collapsed(offset: 3);
      model.openHistory();
      expect(model.inlineSuggestion, isEmpty);
      model.dismissHistory();
      model.editor.value = const TextEditingValue(
        text: 'gi',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(model.inlineSuggestion, 't checkout composer');
      await model.run();
      expect(sent!.query.value.text, 'gi');
      expect(model.inlineSuggestion, isEmpty);
    },
  );

  testWidgets(
    'right and Ctrl+right accept ghost without execution; copy uses draft',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var submits = 0;
      final model = create(
        text: 'git',
        submit: (_) async {
          submits++;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      model.updateHistory(['git checkout composer']);
      await show(tester, model);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('composer-editor')))
            .controller!
            .text,
        'git',
      );
      await tester.tap(
        find.byTooltip('Copy draft · kept only in this session'),
      );
      await tester.pump();
      expect(copied, 'git');
      await tester.tap(find.byKey(const Key('composer-editor')));
      model.editor.selection = const TextSelection.collapsed(offset: 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(model.editor.text, 'git checkout ');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(model.editor.text, 'git checkout composer');
      expect(submits, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history filters in place; Enter accepts and Esc restores original selection',
    (tester) async {
      var submits = 0;
      final model = create(
        text: 'git',
        submit: (_) async {
          submits++;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      model.updateHistory(['git status', 'git log', 'echo unrelated']);
      await show(tester, model);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.byKey(const Key('composer-history-list')), findsOneWidget);
      expect(model.historySelectedIndex, 1);
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'git log',
      );
      await tester.pump();
      expect(model.historyItems, ['git log']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(model.editor.text, 'git');
      expect(model.editor.selection.extentOffset, 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'git status');
      expect(submits, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 1);
    },
  );

  testWidgets(
    'Up navigates wrapped and multiline drafts before opening history',
    (tester) async {
      final model = create(text: 'echo first\necho second');
      addTearDown(model.dispose);
      await show(tester, model, width: 360);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(model.historyOpen, isFalse);
      expect(model.editor.selection.extentOffset, lessThan(11));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(model.historyOpen, isTrue);
      model.dismissHistory();
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        List.filled(15, 'word').join(' '),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(model.historyOpen, isFalse);
      expect(
        model.editor.selection.extentOffset,
        lessThan(model.editor.text.length),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ctrl and Option Enter insert a newline without submitting', (
    tester,
  ) async {
    var submits = 0;
    final model = create(
      text: 'echo',
      submit: (_) async {
        submits++;
        return ComposerSubmissionOutcome.accepted;
      },
    );
    addTearDown(model.dispose);
    await show(tester, model);
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
    }
    expect(model.editor.text, 'echo\n\n');
    expect(submits, 0);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'scaled history scrolls to selection and displays an empty state',
    (tester) async {
      final model = create();
      addTearDown(model.dispose);
      model.updateHistory(List.generate(80, (i) => 'git branch $i'));
      await show(tester, model, width: 360, scale: 2);
      model.openHistory();
      await tester.pumpAndSettle();
      final newest = find.text('git branch 0', findRichText: true);
      expect(newest.hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'missing',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching commands'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'automatic menu stays closed while static suggestions remain inline',
    (tester) async {
      final model = TerminalComposerController(
        targetId: 'static',
        debounce: Duration.zero,
        provider: (q, _) async => CompletionBatch(q, [
          CompletionEdit(
            itemId: 'checkout',
            label: 'checkout',
            detail: 'Switch branches',
            kind: 'subcommand',
            source: 'catalog',
            start: 4,
            end: q.value.text.length,
            newText: 'checkout',
            cursor: 12,
          ),
        ]),
      );
      addTearDown(model.dispose);
      await show(tester, model);
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'git che',
      );
      await tester.pumpAndSettle();
      expect(model.inlineSuggestion, 'ckout');
      expect(find.byKey(const Key('composer-completion-list')), findsNothing);
      model.toggleLocalSuggestions();
      await tester.pumpAndSettle();
      expect(model.inlineSuggestion, isEmpty);
      expect(find.byKey(const Key('composer-completion-list')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        find.byKey(const Key('composer-completion-detail')),
        findsOneWidget,
      );
      expect(find.text('Switch branches'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
